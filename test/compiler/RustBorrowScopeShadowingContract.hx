#if macro
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustPathAnalysis;
import reflaxe.rust.passes.BorrowScopeTighteningPass;

/**
	Behavioral regression for lexical shadows in borrow-scope tightening.

	Why
	- A nested `let` initializer and a `for` iterable execute before their same-named binder enters
	  scope, but subsequent block statements and the loop body resolve that spelling to the binder.
	- Counting and replacement must agree on that boundary or the pass can retain an unnecessary outer
	  borrow alias, leak its borrow expression into a shadowed region, or remove an alias that still has
	  a genuine outer use.

	What
	- Exercises the pass's pure path-use counting and replacement helpers for sequential `let` and
	  `for` scopes.
	- Exercises the complete block rewrite both when the initializer is the only outer use and when a
	  later statement still consumes the outer alias.

	How
	- The JavaScript contract invokes `run` through Haxe's macro hook, which admits the compiler-only
	  pass without constructing a complete `CompilationContext`.
**/
@:access(reflaxe.rust.passes.BorrowScopeTighteningPass)
class RustBorrowScopeShadowingContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function local(name:String):RustExpr {
		return EPath(RustPath.single(name));
	}

	static function borrow(owner:String):RustExpr {
		return ECall(EField(local(owner), RustMember.plain("borrow")), []);
	}

	static function isLocal(expr:RustExpr, expectedName:String):Bool {
		return switch (expr) {
			case EPath(path): RustPathAnalysis.localIdentifierName(path) == expectedName;
			case _: false;
		};
	}

	static function isBorrow(expr:RustExpr, expectedOwner:String):Bool {
		return switch (expr) {
			case ECall(EField(owner, member), []):
				isLocal(owner, expectedOwner) && RustPathAnalysis.matchesPlainMember(member, "borrow");
			case _: false;
		};
	}

	static function nestedLetConsumer():RustExpr {
		return EBlock({
			stmts: [
				RLet("alias", false, null, local("alias")),
				RSemi(local("alias"))
			],
			tail: local("alias")
		});
	}

	static function expectNestedLetReplacement(expr:RustExpr):Void {
		switch (expr) {
			case EBlock(block):
				expect(block.stmts.length == 2, "nested let replacement changed statement count");
				switch (block.stmts[0]) {
					case RLet(name, _, _, initializer):
						expect(name == "alias", "nested let replacement changed the shadow binder");
						expect(initializer != null && isBorrow(initializer, "owner"),
							"outer borrow replacement did not reach the nested let initializer");
					case _:
						throw "expected nested let declaration";
				}
				switch (block.stmts[1]) {
					case RSemi(afterBinding):
						expect(isLocal(afterBinding, "alias"),
							"outer borrow replacement leaked past the nested let binder");
					case _:
						throw "expected nested statement after the let binder";
				}
				expect(block.tail != null && isLocal(block.tail, "alias"),
					"outer borrow replacement leaked into the nested block tail");
			case _:
				throw "expected nested block expression";
		}
	}

	static function expectForReplacement(stmt:RustStmt):Void {
		switch (stmt) {
			case RFor(name, iter, body):
				expect(name == "alias", "for replacement changed the loop binder");
				expect(isBorrow(iter, "owner"), "outer borrow replacement did not reach the for iterable");
				expect(body.stmts.length == 1, "for replacement changed the loop body statement count");
				switch (body.stmts[0]) {
					case RSemi(bodyUse):
						expect(isLocal(bodyUse, "alias"), "outer borrow replacement leaked into the for body");
					case _:
						throw "expected loop-body alias use";
				}
				expect(body.tail != null && isLocal(body.tail, "alias"),
					"outer borrow replacement leaked into the for body tail");
			case _:
				throw "expected for statement";
		}
	}

	public static function run():Void {
		var pass = new BorrowScopeTighteningPass();
		var nestedLet = nestedLetConsumer();
		expect(pass.countPathUsesInExpr(nestedLet, "alias") == 1,
			"nested let shadow uses were counted as outer borrow-alias uses");
		expectNestedLetReplacement(pass.replacePathInExpr(nestedLet, "alias", borrow("owner")));

		var forStmt:RustStmt = RFor("alias", local("alias"), {
			stmts: [RSemi(local("alias"))],
			tail: local("alias")
		});
		expect(pass.countPathUsesInStmt(forStmt, "alias") == 1,
			"for-body binder uses were counted as outer borrow-alias uses");
		expectForReplacement(pass.replacePathInStmt(forStmt, "alias", borrow("owner")));

		var soleOuterUse = pass.rewriteBlock({
			stmts: [
				RLet("alias", false, null, borrow("owner")),
				RExpr(nestedLetConsumer(), false)
			],
			tail: null
		}, false);
		expect(soleOuterUse.stmts.length == 1,
			"sole outer use in a nested let initializer did not tighten the borrow alias");
		switch (soleOuterUse.stmts[0]) {
			case RExpr(expr, _): expectNestedLetReplacement(expr);
			case _: throw "expected tightened nested-let consumer";
		}

		var laterOuterUse = pass.rewriteBlock({
			stmts: [
				RLet("alias", false, null, borrow("owner")),
				RExpr(nestedLetConsumer(), false),
				RSemi(local("alias"))
			],
			tail: null
		}, false);
		expect(laterOuterUse.stmts.length == 3,
			"outer borrow alias was removed despite a later use outside the nested shadow scope");
		switch (laterOuterUse.stmts[0]) {
			case RLet(name, _, _, initializer):
				expect(name == "alias" && initializer != null && isBorrow(initializer, "owner"),
					"retained outer borrow alias changed unexpectedly");
			case _:
				throw "expected retained outer borrow alias";
		}

		var siblingShadow = pass.rewriteBlock({
			stmts: [
				RLet("alias", false, null, borrow("owner")),
				RSemi(local("alias")),
				RLet("alias", false, null, local("replacement")),
				RSemi(local("alias"))
			],
			tail: local("alias")
		}, false);
		expect(siblingShadow.stmts.length == 3,
			"later sibling uses behind a same-name let prevented immediate borrow tightening");
		switch (siblingShadow.stmts[0]) {
			case RSemi(expr):
				expect(isBorrow(expr, "owner"), "tightened sibling consumer did not receive the borrow expression");
			case _:
				throw "expected tightened sibling consumer";
		}

		var siblingInitializerUse = pass.rewriteBlock({
			stmts: [
				RLet("alias", false, null, borrow("owner")),
				RSemi(local("alias")),
				RLet("alias", false, null, local("alias")),
				RSemi(local("alias"))
			],
			tail: null
		}, false);
		expect(siblingInitializerUse.stmts.length == 4,
			"a same-name let initializer lost its genuine outer alias use during after-consumer analysis");
	}
}
#end
