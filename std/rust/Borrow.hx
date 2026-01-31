package rust;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.TypeTools;
#end

class Borrow {
	/**
	 * `Borrow.withRef(value, ref -> { ... })`
	 *
	 * Why:
	 * - Rust APIs often want `&T` / `&mut T` borrows, but Haxe cannot express lifetimes.
	 * - If users store `rust.Ref<T>` / `rust.MutRef<T>` in locals/fields “for later”, it’s easy to
	 *   accidentally model an impossible lifetime and get confusing Rust borrow errors.
	 *
	 * What:
	 * - These helpers create a short borrow “scope” in Haxe syntax: you pass a value and a callback,
	 *   and inside the callback you get a `rust.Ref<T>` or `rust.MutRef<T>`.
	 *
	 * How:
	 * - The macro expands the callback *inline* into a block:
	 *   - `Borrow.withRef(v, r -> body)` becomes `{ var r: rust.Ref<T> = v; body; }`
	 *   - `Borrow.withMut(v, r -> body)` becomes `{ var r: rust.MutRef<T> = v; body; }`
	 * - The compiler recognizes `rust.Ref<T>` / `rust.MutRef<T>` as compile-time-only core types and
	 *   prints them as Rust `&T` / `&mut T` at the usage sites.
	 *
	 * Important:
	 * - Because the callback body is inlined, `return` inside it would become `return` from the caller.
	 *   To prevent surprising control-flow, this macro strips `return` statements from the callback body.
	 */
	public static macro function withRef(value: haxe.macro.Expr, fn: haxe.macro.Expr): haxe.macro.Expr {
		return expand(value, fn, false);
	}

	/** See `withRef`; this variant provides a mutable borrow (`rust.MutRef<T>` / `&mut T`). */
	public static macro function withMut(value: haxe.macro.Expr, fn: haxe.macro.Expr): haxe.macro.Expr {
		return expand(value, fn, true);
	}

	#if macro
	static function expand(value: Expr, fn: Expr, mut: Bool): Expr {
		var f = switch (fn.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("Borrow helper expects a function expression: (ref) -> { ... }", fn.pos);
				return macro null;
		}

		if (f.args.length != 1) {
			Context.error("Borrow helper callback must take exactly one argument", fn.pos);
		}

		var argName = f.args[0].name;
		var typedValue = Context.typeExpr(value);
		var valueCt = TypeTools.toComplexType(typedValue.t);

		var refType: ComplexType = TPath({
			pack: ["rust"],
			name: mut ? "MutRef" : "Ref",
			params: [TPType(valueCt)]
		});

		// Expand `Borrow.withRef(v, r -> body)` to:
		// `{ var r: rust.Ref<T> = v; body; }`
		//
		// Expand `Borrow.withMut(v, r -> body)` to:
		// `{ var r: rust.MutRef<T> = v; body; }`
		//
		// The compiler maps `rust.Ref<T>` / `rust.MutRef<T>` to `&T` / `&mut T`.
		var varDecl: Expr = {
			expr: EVars([{
				name: argName,
				type: refType,
				expr: value
			}]),
			pos: fn.pos
		};

		// IMPORTANT:
		// This helper *inlines* the callback body to avoid allocating a closure (and to allow mutating
		// captured locals in a way that matches Haxe semantics).
		//
		// However, `return` statements inside the callback body would become `return` from the caller
		// after macro expansion. This is almost never intended, so we strip them.
		function sanitize(e: Expr): Expr {
			return switch (e.expr) {
				case EFunction(_, _):
					e;
				case EReturn(v): {
					// `return;` / `return expr;` inside an inlined callback would return from the caller.
					// Rewrite it to just evaluate the returned expression (if any) and continue.
					if (v == null) {
						{ expr: EBlock([]), pos: e.pos };
					} else {
						sanitize(v);
					}
				}
				case EBlock(exprs):
					{ expr: EBlock([for (x in exprs) sanitize(x)]), pos: e.pos };
				case _:
					ExprTools.map(e, sanitize);
			}
		}

		var bodyExpr = sanitize(f.expr);
		return macro { $varDecl; $bodyExpr; };
	}
	#end
}
