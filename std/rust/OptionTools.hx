package rust;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
 * OptionTools
 *
 * Pure-Haxe helpers for `rust.Option<T>` (maps to Rust `Option<T>`).
 *
 * These are intentionally implemented without `__rust__` so they can be `inline`
 * and stay usable from application code without breaking the escape-hatch rule.
 */
class OptionTools {
	#if macro
	static function asValueExpr(e: Expr): Expr {
		return { expr: EParenthesis(e), pos: e.pos };
	}

	static function stripReturn(e: Expr): Expr {
		return switch (e.expr) {
			case EReturn(ret):
				ret == null ? macro null : ret;
			case EBlock(stmts):
				if (stmts.length == 0) {
					e;
				} else {
					var out = stmts.copy();
					var last = out[out.length - 1];
					out[out.length - 1] = switch (last.expr) {
						case EReturn(ret): ret == null ? macro null : ret;
						case _: last;
					}
					{ expr: EBlock(out), pos: e.pos };
				}
			case _:
				e;
		}
	}
	#end

	@:rustGeneric("T: Clone")
	public static inline function isSome<T>(o: Option<T>): Bool {
		return switch (o) {
			case Some(_): true;
			case None: false;
		}
	}

	@:rustGeneric("T: Clone")
	public static inline function isNone<T>(o: Option<T>): Bool {
		return !isSome(o);
	}

	@:rustGeneric("T: Clone")
	public static inline function unwrapOr<T>(o: Option<T>, fallback: T): T {
		return switch (o) {
			case Some(v): v;
			case None: fallback;
		}
	}

	/**
	 * Macro version to avoid requiring runtime function types in the Rust target POC.
	 *
	 * Usage: `o.unwrapOrElse(() -> expr)`
	 */
	public static macro function unwrapOrElse<T>(
		o: ExprOf<Option<T>>,
		fallback: Expr
	): ExprOf<T> {
		#if macro
		var f = switch (fallback.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("unwrapOrElse expects a function expression: () -> expr", fallback.pos);
				return macro null;
		}

		if (f.args.length != 0) {
			Context.error("unwrapOrElse fallback must take 0 arguments", fallback.pos);
		}

		var body = stripReturn(f.expr);
		var v = "v";
		var outExpr: Expr = {
			expr: ESwitch(
				o,
				[
					{ values: [macro Some($i{v})], guard: null, expr: macro $i{v} },
					{ values: [macro None], guard: null, expr: asValueExpr(body) }
				],
				null
			),
			pos: o.pos
		};
		return outExpr;
		#else
		return macro null;
		#end
	}

	/**
	 * Macro `map` to avoid requiring runtime function types in the Rust target POC.
	 *
	 * Usage: `o.map(v -> expr)`
	 */
	public static macro function map<T, U>(o: ExprOf<Option<T>>, f: Expr): ExprOf<Option<U>> {
		#if macro
		var fn = switch (f.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("map expects a function expression: (v) -> expr", f.pos);
				return macro null;
		}

		if (fn.args.length != 1) {
			Context.error("map callback must take 1 argument", f.pos);
		}

		var argName = fn.args[0].name;
		var body = stripReturn(fn.expr);
		var outExpr: Expr = {
			expr: ESwitch(
				o,
				[
					{
						values: [macro Some($i{argName})],
						guard: null,
						expr: macro Some(${asValueExpr(body)})
					},
					{ values: [macro None], guard: null, expr: macro None }
				],
				null
			),
			pos: o.pos
		};
		return outExpr;
		#else
		return macro null;
		#end
	}

	/**
	 * Macro `andThen` to avoid requiring runtime function types in the Rust target POC.
	 *
	 * Usage: `o.andThen(v -> exprReturningOption)`
	 */
	public static macro function andThen<T, U>(
		o: ExprOf<Option<T>>,
		f: Expr
	): ExprOf<Option<U>> {
		#if macro
		var fn = switch (f.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("andThen expects a function expression: (v) -> optionExpr", f.pos);
				return macro null;
		}

		if (fn.args.length != 1) {
			Context.error("andThen callback must take 1 argument", f.pos);
		}

		var argName = fn.args[0].name;
		var body = stripReturn(fn.expr);
		var outExpr: Expr = {
			expr: ESwitch(
				o,
				[
					{ values: [macro Some($i{argName})], guard: null, expr: asValueExpr(body) },
					{ values: [macro None], guard: null, expr: macro None }
				],
				null
			),
			pos: o.pos
		};
		return outExpr;
		#else
		return macro null;
		#end
	}
}
