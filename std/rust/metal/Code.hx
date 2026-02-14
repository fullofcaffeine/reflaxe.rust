package rust.metal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
 * Typed code-injection façade for the `metal` profile.
 *
 * Why
 * - The raw `__rust__` escape hatch is intentionally restricted in app code (strict boundary mode).
 * - Metal still needs an ergonomic way to reach Rust-only constructs that are not yet modeled as
 *   dedicated Haxe APIs.
 *
 * What
 * - `expr(code, ...args)` emits a Rust expression and returns it as a typed Haxe expression.
 * - `stmt(code, ...args)` emits Rust statement/block code in a `Void` context.
 * - Placeholder interpolation follows Reflaxe injection rules: `{0}`, `{1}`, ...
 *
 * How
 * - This macro delegates to the framework-owned `RustInjection.__rust__` shim.
 * - Keeping the boundary in `std/rust/metal/*` provides a single documented surface for metal interop.
 * - Callers should keep snippets minimal and prefer dedicated typed `std/` APIs when available.
 */
class Code {
	public static macro function expr(code:String, args:Array<Expr>):Expr {
		if (code == null || code.length == 0) {
			Context.error("`rust.metal.Code.expr` requires a non-empty Rust snippet.", Context.currentPos());
		}
		var callArgs = [macro $v{code}].concat(args);
		return macro reflaxe.rust.macros.RustInjection.__rust__($a{callArgs});
	}

	public static macro function stmt(code:String, args:Array<Expr>):Expr {
		if (code == null || code.length == 0) {
			Context.error("`rust.metal.Code.stmt` requires a non-empty Rust snippet.", Context.currentPos());
		}
		var callArgs = [macro $v{code}].concat(args);
		return macro {
			reflaxe.rust.macros.RustInjection.__rust__($a{callArgs});
		};
	}
}
