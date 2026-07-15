#if macro
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustClosureParameter;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.passes.MutInferencePass;

/**
	Behavioral regression for lexical scopes in mutation inference.

	Why
	- The pass collects writes from nested expressions so captured outer locals become `mut`, but a
	  nested binding with the same spelling must stop contributing evidence after its declaration.
	- Declaration-only initialization and closure/async capture analysis must use the same shadow rules
	  as the primary collector or warning-clean Rust can gain a false `unused_mut` or miss required `mut`.

	What
	- Executes the pure block rewrite over nested `let`, `for`, closure, match, and async-move scopes.
	- Distinguishes writes in a nested initializer/iterable (outer scope) from writes in the nested
	  binding's body or subsequent statements (inner scope).

	How
	- The JavaScript contract invokes `run` through Haxe's macro hook, which admits the compiler-only
	  pass without constructing a complete `CompilationContext`.
**/
@:access(reflaxe.rust.passes.MutInferencePass)
class RustMutInferenceShadowingContract {
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

	static function isMutableLet(stmt:RustStmt, expectedName:String):Bool {
		return switch (stmt) {
			case RLet(name, mutable, _, _) if (name == expectedName): mutable;
			case _: throw 'Expected let binding `$expectedName`';
		};
	}

	static function nestedBlock(stmt:RustStmt):RustBlock {
		return switch (stmt) {
			case RExpr(EBlock(block), _): block;
			case _: throw "Expected nested block expression";
		};
	}

	public static function run():Void {
		var pass = new MutInferencePass();

		var guardRewrite = pass.rewriteBlock({
			stmts: [
				RLet("guard", false, null, ECall(EField(local("outer"), RustMember.plain("borrow")), [])),
				RExpr(EBlock({
					stmts: [RLet("guard", false, null, ECall(EField(local("inner"), RustMember.plain("borrow_mut")), []))],
					tail: null
				}), false)
			],
			tail: null
		});
		expect(!isMutableLet(guardRewrite.stmts[0], "guard"),
			"nested borrow_mut guard leaked mutability into the outer same-named binding");
		expect(isMutableLet(nestedBlock(guardRewrite.stmts[1]).stmts[0], "guard"),
			"nested borrow_mut guard lost its own required mutability");

		var sequentialRewrite = pass.rewriteBlock({
			stmts: [
				RLet("value", false, null, null),
				RExpr(EBlock({
					stmts: [
						RLet("value", false, null, EBlock({
							stmts: [RSemi(assignment("value", 1))],
							tail: ELitInt(0)
						})),
						RSemi(assignment("value", 2))
					],
					tail: null
				}), false)
			],
			tail: null
		});
		expect(!isMutableLet(sequentialRewrite.stmts[0], "value"),
			"one declaration-only outer initialization became mutation after a nested let shadow");
		expect(isMutableLet(nestedBlock(sequentialRewrite.stmts[1]).stmts[0], "value"),
			"writes after a nested let declaration did not make that inner binding mutable");

		var closureCaptureRewrite = pass.rewriteBlock({
			stmts: [
				RLet("captured", false, null, null),
				RExpr(EIf(local("condition"), assignment("captured", 1), assignment("captured", 2)), false),
				RLet("_capture", false, null, EClosure([], {
					stmts: [RSemi(assignment("captured", 3))],
					tail: null
				}, false))
			],
			tail: null
		});
		expect(isMutableLet(closureCaptureRewrite.stmts[0], "captured"),
			"closure reassignment was discarded as declaration-only initialization");

		var asyncCaptureRewrite = pass.rewriteBlock({
			stmts: [
				RLet("async_value", false, null, null),
				RExpr(EIf(local("condition"), assignment("async_value", 1), assignment("async_value", 2)), false),
				RLet("_future", false, null, EPinAsyncMove({
					stmts: [RSemi(assignment("async_value", 3))],
					tail: null
				}))
			],
			tail: null
		});
		expect(isMutableLet(asyncCaptureRewrite.stmts[0], "async_value"),
			"async-move reassignment was discarded as declaration-only initialization");

		var closureShadowRewrite = pass.rewriteBlock({
			stmts: [
				RLet("shadowed", false, null, ELitInt(0)),
				RLet("_closure", false, null, EClosure([RustClosureParameter.binding("shadowed")], {
					stmts: [RSemi(assignment("shadowed", 1))],
					tail: null
				}, false)),
				RExpr(EMatch(local("source"), [{
					pat: PBind("shadowed"),
					expr: assignment("shadowed", 2)
				}]), false)
			],
			tail: null
		});
		expect(!isMutableLet(closureShadowRewrite.stmts[0], "shadowed"),
			"closure or match pattern writes leaked through a structural shadow");

		var forBodyRewrite = pass.rewriteBlock({
			stmts: [
				RLet("item", false, null, ELitInt(0)),
				RFor("item", local("iter"), {stmts: [RSemi(assignment("item", 1))], tail: null})
			],
			tail: null
		});
		expect(!isMutableLet(forBodyRewrite.stmts[0], "item"),
			"for-body writes to the loop binding leaked into the outer same-named binding");

		var forIterableRewrite = pass.rewriteBlock({
			stmts: [
				RLet("item", false, null, ELitInt(0)),
				RFor("item", EBlock({stmts: [RSemi(assignment("item", 1))], tail: local("iter")}), {
					stmts: [RSemi(assignment("item", 2))],
					tail: null
				})
			],
			tail: null
		});
		expect(isMutableLet(forIterableRewrite.stmts[0], "item"),
			"for iterable stopped seeing the outer binding before the loop binder entered scope");
	}
}
#end
