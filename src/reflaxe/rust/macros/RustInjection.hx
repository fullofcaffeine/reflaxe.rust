package reflaxe.rust.macros;

#if macro
import haxe.macro.Expr;
#end

/**
 * RustInjection: Provides __rust__ as a macro function.
 *
 * WHY: Reflaxe's injection mechanism needs the `__rust__` identifier to exist during typing.
 *
 * WHAT: A macro function that returns an AST node Reflaxe recognizes as target code injection.
 *
 * HOW:
 * - Call as `RustInjection.__rust__("some_rust({0}, {1})", arg0, arg1)`.
 * - Reflaxe replaces `{0}`, `{1}`, ... with compiled arguments.
 * - Returns `macro untyped __rust__($a{[code].concat(args)})`.
 */
class RustInjection {
	public static macro function __rust__(code: String, args: Array<Expr>): Expr {
		var callArgs = [macro $v{code}].concat(args);
		return macro untyped __rust__($a{callArgs});
	}
}
