#if macro
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.passes.StatementCleanupPass;

/**
	Behavioral regression for lexical scopes in statement cleanup.

	Why
	- The pass collapses `let value; value = init;` and decides whether the resulting binding still
	  needs `mut` by scanning later assignments.
	- A nested `let` or `for` binder with the same spelling owns later writes in that nested scope;
	  counting those writes against the outer binding emits a false `mut` and fails warning-clean Rust.
	- Pending uninitialized declarations must also be retired before a same-block shadow and must never
	  consume an assignment owned by a nested same-named binding.

	What
	- Exercises nested-let and loop-binder shadowing after a collapsed outer declaration.
	- Separately proves that a nested-let initializer and a loop iterable still see the outer binding
	  before the new binder enters scope.
	- Characterizes pending-declaration ordering and nested-block collapse rejection at shadow barriers.

	How
	- The JavaScript contract invokes `run` through Haxe's macro hook and inspects the pure AST rewrite.
	- Each case retains a real outer use after the nested scope so unused-binding cleanup cannot erase
	  the declaration whose mutability is under test.
**/
@:access(reflaxe.rust.passes.StatementCleanupPass)
class RustStatementCleanupShadowingContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function local(name:String):RustExpr {
		return EPath(RustPath.single(name));
	}

	static function assignment(name:String, value:Int):RustExpr {
		return EAssign(local(name), ELitInt(value));
	}

	static function retainUse(name:String):RustStmt {
		return RSemi(ECall(EField(local(name), RustMember.plain("consume")), []));
	}

	static function expectCollapsedMutable(block:RustBlock, expected:Bool, message:String):Void {
		switch (block.stmts[0]) {
			case RLet("value", mutable, _, ELitInt(1)):
				expect(mutable == expected, message);
			case _:
				throw "Expected collapsed outer value declaration";
		}
	}

	static function expectFirstBinding(block:RustBlock, expectedName:String, message:String):Void {
		switch (block.stmts[0]) {
			case RLet(name, _, _, _):
				expect(name == expectedName, message);
			case _:
				throw "Expected a leading let binding";
		}
	}

	static function outerFixture(nested:RustStmt):RustBlock {
		return {
			stmts: [
				RLet("value", false, null, null),
				RSemi(assignment("value", 1)),
				nested,
				retainUse("value")
			],
			tail: null
		};
	}

	public static function run():Void {
		var pass = new StatementCleanupPass();

		var nestedLet = pass.rewriteBlock(outerFixture(RExpr(EBlock({
			stmts: [
				RLet("value", false, null, ELitInt(2)),
				RSemi(assignment("value", 3))
			],
			tail: null
		}), false)));
		expectCollapsedMutable(nestedLet, false,
			"writes after a nested let binding leaked mutability into the outer collapsed declaration");

		var nestedLetInitializer = pass.rewriteBlock(outerFixture(RExpr(EBlock({
			stmts: [
				RLet("value", false, null, EBlock({
					stmts: [RSemi(assignment("value", 2))],
					tail: ELitInt(0)
				})),
				RSemi(assignment("value", 3))
			],
			tail: null
		}), false)));
		expectCollapsedMutable(nestedLetInitializer, true,
			"a nested let initializer stopped seeing the outer binding before the new binder entered scope");

		var forBody = pass.rewriteBlock(outerFixture(RFor("value", local("iter"), {
			stmts: [RSemi(assignment("value", 2))],
			tail: null
		})));
		expectCollapsedMutable(forBody, false,
			"writes to a for-loop binder leaked mutability into the outer collapsed declaration");

		var forIterable = pass.rewriteBlock(outerFixture(RFor("value", EBlock({
			stmts: [RSemi(assignment("value", 2))],
			tail: local("iter")
		}), {
			stmts: [RSemi(assignment("value", 3))],
			tail: null
		})));
		expectCollapsedMutable(forIterable, true,
			"a for iterable stopped seeing the outer binding before the loop binder entered scope");

		var unusedNestedLet = pass.rewriteBlock({
			stmts: [
				RLet("value", false, null, ECall(local("make_value"), [])),
				RExpr(EBlock({
					stmts: [RLet("value", false, null, ELitInt(2)), retainUse("value")],
					tail: null
				}), false)
			],
			tail: null
		});
		expectFirstBinding(unusedNestedLet, "_",
			"a nested let binding falsely retained an otherwise unused outer binding");

		var usedByNestedInitializer = pass.rewriteBlock({
			stmts: [
				RLet("value", false, null, ECall(local("make_value"), [])),
				RExpr(EBlock({
					stmts: [
						RLet("value", false, null, ECall(EField(local("value"), RustMember.plain("snapshot")), [])),
						retainUse("value")
					],
					tail: null
				}), false)
			],
			tail: null
		});
		expectFirstBinding(usedByNestedInitializer, "value",
			"a nested let initializer lost its use of the outer binding before shadowing began");

		var unusedForBinder = pass.rewriteBlock({
			stmts: [
				RLet("value", false, null, ECall(local("make_value"), [])),
				RFor("value", local("iter"), {stmts: [retainUse("value")], tail: null})
			],
			tail: null
		});
		expectFirstBinding(unusedForBinder, "_",
			"a for-loop binder falsely retained an otherwise unused outer binding");

		var pendingSiblingShadow = pass.rewriteBlock({
			stmts: [
				RLet("value", false, null, null),
				RLet("value", false, null, ELitInt(2)),
				retainUse("value")
			],
			tail: null
		});
		expect(pendingSiblingShadow.stmts.length == 3,
			"same-block shadowing changed the pending-declaration statement count");
		switch (pendingSiblingShadow.stmts[0]) {
			case RLet("value", _, _, null):
			case _:
				throw "pending outer declaration moved behind its same-block shadow";
		}
		switch (pendingSiblingShadow.stmts[1]) {
			case RLet("value", _, _, ELitInt(2)):
			case _:
				throw "initialized same-block shadow was replaced by the pending outer declaration";
		}

		var pendingNestedShadow = pass.rewriteBlock({
			stmts: [
				RLet("value", false, null, null),
				RExpr(EBlock({
					stmts: [
						RLet("value", false, null, ELitInt(1)),
						RSemi(assignment("value", 2))
					],
					tail: null
				}), false)
			],
			tail: null
		});
		expect(pendingNestedShadow.stmts.length == 2,
			"inner assignment was collapsed into a pending outer declaration");
		var foundPendingOuter = false;
		var foundNestedBlock = false;
		for (stmt in pendingNestedShadow.stmts) {
			switch (stmt) {
				case RLet("value", _, _, null):
					foundPendingOuter = true;
				case RExpr(EBlock(block), _):
					foundNestedBlock = block.stmts.length == 2;
				case _:
			}
		}
		expect(foundPendingOuter && foundNestedBlock,
			"pending outer declaration consumed an assignment owned by a nested let shadow");
	}
}
#end
