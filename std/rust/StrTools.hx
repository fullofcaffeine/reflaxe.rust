package rust;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.TypeTools;
import reflaxe.rust.macros.BorrowRegionMacroGuard;
#end

/**
 * StrTools
 *
 * Helpers for producing short-lived `rust.Str` values without using `__rust__` in apps.
 *
 * Why:
 * - `rust.Str` is a borrowed `&str`-style view, so Haxe code must not store or return it outside
 *   the callback that created it.
 *
 * What / How:
 * - `with(...)` mirrors the borrow-region model used by `rust.Borrow` and `rust.SliceTools`.
 * - The macro rejects direct escapes of the callback token before Rust code is emitted.
 */
class StrTools {
	/**
	 * Borrow a Haxe `String` as `rust.Str` for the duration of the callback.
	 */
	public static macro function with(value:Expr, fn:Expr):Expr {
		#if macro
		var f = switch (fn.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("StrTools.with expects a function expression: (s) -> { ... }", fn.pos);
				return macro null;
		}

		if (f.args.length != 1) {
			Context.error("StrTools.with callback must take exactly one argument", fn.pos);
		}

		var argName = f.args[0].name;
		BorrowRegionMacroGuard.rejectEscapingBorrow("rust.StrTools.with", "rust.Str", argName, f.expr);

		var decl:Expr = {
			expr: EVars([
				{
					name: argName,
					type: TPath({pack: ["rust"], name: "Str"}),
					expr: {expr: ECast({expr: EConst(CIdent("__hx_ref")), pos: fn.pos}, null), pos: fn.pos}
				}
			]),
			pos: fn.pos
		};

		// Expand to:
		// `rust.Borrow.withRef(value, __hx_ref -> { var s: rust.Str = cast __hx_ref; body; })`
		return macro rust.Borrow.withRef($value, function(__hx_ref) {
			$decl;
			${f.expr};
		});
		#else
		return macro null;
		#end
	}
}
