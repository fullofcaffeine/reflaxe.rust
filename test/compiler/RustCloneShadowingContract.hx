#if macro
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustASTPrinter;
import reflaxe.rust.passes.CloneElisionPass;

/**
	Behavioral regression for lexical shadowing in last-use clone elision.

	Why
	- A match arm, sequential `let`, or `for` binder can reuse an outer local's spelling; outer
	  last-use evidence must never authorize moving the nested value.
	- This is type-sensitive: cloning a reference-like inner binding may produce an owned value, while
	  moving that binding preserves the reference and changes the emitted Rust program.

	What
	- Executes the pass's pure use counter and recursive rewrite in macro context for shadowed and
	  captured locals.

	How
	- The test invokes `run` through Haxe's command-line macro hook, which provides the compiler-only
	  APIs imported by `CloneElisionPass` without adding a runtime test dependency.
**/
@:access(reflaxe.rust.passes.CloneElisionPass)
class RustCloneShadowingContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function path(names:Array<String>):RustPath {
		return RustPath.relative([for (name in names) reflaxe.rust.ast.RustAST.RustPathSegment.plain(name)]);
	}

	static function local(name:String):RustExpr {
		return EPath(RustPath.single(name));
	}

	static function dynamicFromClone(name:String):RustExpr {
		return ECall(EPath(path(["hxrt", "dynamic", "from"])), [
			ECall(EField(local(name), RustMember.plain("clone")), [])
		]);
	}

	public static function run():Void {
		var pass = new CloneElisionPass();
		var shadowed:RustExpr = EMatch(local("source"), [{
			pat: PBind("value"),
			expr: EBlock({
				stmts: [RSemi(dynamicFromClone("value"))],
				tail: local("value")
			})
		}]);
		var shadowedRewrite = pass.rewriteLastUseCloneSites(shadowed, _ -> null);
		if (RustASTPrinter.printExprForInjection(shadowedRewrite).indexOf("value.clone()") == -1)
			throw "clone elision applied outer-local move evidence to a match-arm binding";

		var captured:RustExpr = EMatch(local("source"), [{
			pat: PBind("inner"),
			expr: dynamicFromClone("value")
		}]);
		var capturedRewrite = pass.rewriteLastUseCloneSites(captured, _ -> null);
		if (RustASTPrinter.printExprForInjection(capturedRewrite).indexOf("value.clone()") != -1)
			throw "unshadowed outer local unexpectedly lost eligible clone elision";

		var sequential:RustExpr = EBlock({
			stmts: [
				RLet("value", false, RBorrow(RI32, false, null), dynamicFromClone("value")),
				RSemi(dynamicFromClone("value"))
			],
			tail: local("value")
		});
		expect(pass.countPathUsesInExpr(sequential, "value") == 1,
			"sequential let shadow did not stop outer-local use counting after its initializer");
		var sequentialPrinted = RustASTPrinter.printExprForInjection(pass.rewriteLastUseCloneSites(sequential, _ -> null));
		expect(sequentialPrinted.indexOf("let value: &i32 = hxrt::dynamic::from(value);") != -1,
			"sequential let initializer stopped seeing eligible outer-local move evidence");
		expect(sequentialPrinted.indexOf("hxrt::dynamic::from(value.clone());") != -1,
			"outer movability evidence removed the reference-like inner binding's clone");

		var forScope:RustExpr = EBlock({
			stmts: [
				RFor("item", dynamicFromClone("item"), {
					stmts: [RSemi(dynamicFromClone("item"))],
					tail: local("item")
				})
			],
			tail: null
		});
		expect(pass.countPathUsesInExpr(forScope, "item") == 1,
			"for-body loop binding leaked into outer-local use counting");
		var forPrinted = RustASTPrinter.printExprForInjection(pass.rewriteLastUseCloneSites(forScope, _ -> null));
		expect(forPrinted.indexOf("for item in hxrt::dynamic::from(item.clone())") != -1,
			"clone elision unexpectedly rewrote the intentionally disabled for-loop statement");
		expect(forPrinted.indexOf("hxrt::dynamic::from(item.clone());") != -1,
			"outer movability evidence crossed the for binder into its body");

		var siblingShadow = pass.rewriteBlock({
			stmts: [
				RLet("value", false, RString, ELitString("outer")),
				RSemi(dynamicFromClone("value")),
				RLet("value", false, RBorrow(RI32, false, null), local("inner_ref")),
				RSemi(dynamicFromClone("value"))
			],
			tail: local("value")
		}, false);
		var siblingPrinted = RustASTPrinter.printExprForInjection(EBlock(siblingShadow));
		expect(siblingPrinted.indexOf("hxrt::dynamic::from(value);") != -1,
			"later sibling uses behind a same-name let prevented outer last-use clone elision");
		expect(siblingPrinted.indexOf("hxrt::dynamic::from(value.clone());") != -1,
			"outer move evidence crossed the sibling let into its reference-like binding");

		var initializerShadow = pass.rewriteBlock({
			stmts: [
				RLet("value", false, RString, ELitString("outer")),
				RLet("value", false, RBorrow(RI32, false, null), dynamicFromClone("value")),
				RSemi(dynamicFromClone("value"))
			],
			tail: local("value")
		}, false);
		var initializerPrinted = RustASTPrinter.printExprForInjection(EBlock(initializerShadow));
		expect(initializerPrinted.indexOf("let value: &i32 = hxrt::dynamic::from(value);") != -1,
			"a same-name let initializer did not retain outer last-use move authority");
		expect(initializerPrinted.indexOf("hxrt::dynamic::from(value.clone());") != -1,
			"the new reference-like binding lost its required clone after its initializer");
	}
}
#end
