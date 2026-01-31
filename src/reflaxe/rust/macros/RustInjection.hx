package reflaxe.rust.macros;

#if macro
import haxe.macro.Expr;
#end

/**
 * RustInjection: a typed macro shim around `untyped __rust__(...)`.
 *
 * Why:
 * - Reflaxe’s target-code injection mechanism requires the `__rust__` identifier to exist during typing.
 * - Calling `untyped __rust__("...")` directly works (like `untyped __elixir__` in the Elixir target),
 *   but it forces callsites to use `untyped` and provides no convenience helpers.
 *
 * What:
 * - `RustInjection.__rust__(code, args)` expands to `untyped __rust__(code, ...args)`.
 * - The Reflaxe backend recognizes the `__rust__` call and injects the raw Rust snippet into output.
 *
 * How:
 * - Use `{0}`, `{1}`, ... placeholders inside `code`; they are replaced with compiled Rust expressions.
 *   Example:
 *   - `RustInjection.__rust__("std::mem::take(&mut {0})", v)`
 * - If there are no placeholders, `code` is treated as a literal injection.
 *
 * Important:
 * - Treat this as an escape hatch. Apps/examples should not call `__rust__` directly; instead,
 *   hide injections behind stable Haxe APIs in `std/` so portable code stays portable.
 *
 * Design note:
 * - Reflaxe’s injection parser may report “no placeholders” as an empty-args list; the compiler must
 *   still treat that as a valid literal injection string.
 */
class RustInjection {
	public static macro function __rust__(code: String, args: Array<Expr>): Expr {
		var callArgs = [macro $v{code}].concat(args);
		return macro untyped __rust__($a{callArgs});
	}
}
