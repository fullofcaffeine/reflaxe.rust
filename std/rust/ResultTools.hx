package rust;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
 * ResultTools
 *
 * Pure-Haxe helpers for `rust.Result<T,E>` (maps to Rust `Result<T,E>`).
 *
 * The goal is ergonomic composition in the `rusty` profile without requiring
 * application code to call `__rust__` directly.
 */
class ResultTools {
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

	@:rustGeneric("T: Clone, E: Clone")
	public static inline function isOk<T, E>(r: Result<T, E>): Bool {
		return switch (r) {
			case Ok(_): true;
			case Err(_): false;
		}
	}

	@:rustGeneric("T: Clone, E: Clone")
	public static inline function isErr<T, E>(r: Result<T, E>): Bool {
		return !isOk(r);
	}

	@:rustGeneric("T: Clone, E: Clone")
	public static inline function unwrapOr<T, E>(r: Result<T, E>, fallback: T): T {
		return switch (r) {
			case Ok(v): v;
			case Err(_): fallback;
		}
	}

	/**
	 * Add string context to a `Result<T, String>` error (common Rust pattern: `map_err` / `context`).
	 *
	 * Example: `r.context(\"reading config\")` yields `Err(\"reading config: <e>\")`.
	 */
	@:rustGeneric("T: Clone")
	public static inline function context<T>(r: Result<T, String>, prefix: String): Result<T, String> {
		return switch (r) {
			case Ok(v): Ok(v);
			case Err(e): Err(prefix + ": " + e);
		}
	}

	/**
	 * Macro version to avoid requiring runtime function types in the Rust target POC.
	 *
	 * Usage: `r.unwrapOrElse(e -> expr)`
	 */
	public static macro function unwrapOrElse<T, E>(
		r: ExprOf<Result<T, E>>,
		fallback: Expr
	): ExprOf<T> {
		#if macro
		var f = switch (fallback.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("unwrapOrElse expects a function expression: (e) -> expr", fallback.pos);
				return macro null;
		}

		if (f.args.length != 1) {
			Context.error("unwrapOrElse callback must take 1 argument", fallback.pos);
		}

		var argName = f.args[0].name;
		var body = stripReturn(f.expr);
		var v = "v";
		var outExpr: Expr = {
			expr: ESwitch(
				r,
				[
					{ values: [macro Ok($i{v})], guard: null, expr: macro $i{v} },
					{ values: [macro Err($i{argName})], guard: null, expr: asValueExpr(body) }
				],
				null
			),
			pos: r.pos
		};
		return outExpr;
		#else
		return macro null;
		#end
	}

	/**
	 * Macro `mapOk` to avoid requiring runtime function types in the Rust target POC.
	 *
	 * Usage: `r.mapOk(v -> expr)`
	 */
	public static macro function mapOk<T, E, U>(
		r: ExprOf<Result<T, E>>,
		f: Expr
	): ExprOf<Result<U, E>> {
		#if macro
		var fn = switch (f.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("mapOk expects a function expression: (v) -> expr", f.pos);
				return macro null;
		}

		if (fn.args.length != 1) {
			Context.error("mapOk callback must take 1 argument", f.pos);
		}

		var argName = fn.args[0].name;
		var body = stripReturn(fn.expr);
		var outExpr: Expr = {
			expr: ESwitch(
				r,
				[
					{ values: [macro Ok($i{argName})], guard: null, expr: macro Ok(${asValueExpr(body)}) },
					{ values: [macro Err(__e)], guard: null, expr: macro Err(__e) }
				],
				null
			),
			pos: r.pos
		};
		return outExpr;
		#else
		return macro null;
		#end
	}

	/**
	 * Macro `mapErr` to avoid requiring runtime function types in the Rust target POC.
	 *
	 * Usage: `r.mapErr(e -> expr)`
	 */
	public static macro function mapErr<T, E, F>(
		r: ExprOf<Result<T, E>>,
		f: Expr
	): ExprOf<Result<T, F>> {
		#if macro
		var fn = switch (f.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("mapErr expects a function expression: (e) -> expr", f.pos);
				return macro null;
		}

		if (fn.args.length != 1) {
			Context.error("mapErr callback must take 1 argument", f.pos);
		}

		var argName = fn.args[0].name;
		var body = stripReturn(fn.expr);
		var outExpr: Expr = {
			expr: ESwitch(
				r,
				[
					{ values: [macro Ok(__v)], guard: null, expr: macro Ok(__v) },
					{ values: [macro Err($i{argName})], guard: null, expr: macro Err(${asValueExpr(body)}) }
				],
				null
			),
			pos: r.pos
		};
		return outExpr;
		#else
		return macro null;
		#end
	}

	/**
	 * Macro `andThen` to avoid requiring runtime function types in the Rust target POC.
	 *
	 * Usage: `r.andThen(v -> exprReturningResult)`
	 */
	public static macro function andThen<T, E, U>(
		r: ExprOf<Result<T, E>>,
		f: Expr
	): ExprOf<Result<U, E>> {
		#if macro
		var fn = switch (f.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("andThen expects a function expression: (v) -> resultExpr", f.pos);
				return macro null;
		}

		if (fn.args.length != 1) {
			Context.error("andThen callback must take 1 argument", f.pos);
		}

		var argName = fn.args[0].name;
		var body = stripReturn(fn.expr);
		var outExpr: Expr = {
			expr: ESwitch(
				r,
				[
					{ values: [macro Ok($i{argName})], guard: null, expr: asValueExpr(body) },
					{ values: [macro Err(__e)], guard: null, expr: macro Err(__e) }
				],
				null
			),
			pos: r.pos
		};
		return outExpr;
		#else
		return macro null;
		#end
	}

	/**
	 * Bridge portable exceptions to `Result` without changing normal `try/catch` semantics.
	 *
	 * Useful at framework boundaries (e.g. converting a throwing API to `Result`).
	 */
	public static macro function catchAny<T>(fn: Expr): ExprOf<Result<T, Dynamic>> {
		#if macro
		var f = switch (fn.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("catchAny expects a function expression: () -> expr", fn.pos);
				return macro null;
		}

		if (f.args.length != 0) {
			Context.error("catchAny callback must take 0 arguments", fn.pos);
		}

		var body = stripReturn(f.expr);
		return macro (try Ok(${asValueExpr(body)}) catch (e: Dynamic) Err(e));
		#else
		return macro null;
		#end
	}

	/**
	 * Like `catchAny`, but captures the error as a `String` via `Std.string`.
	 */
	public static macro function catchString<T>(fn: Expr): ExprOf<Result<T, String>> {
		#if macro
		var f = switch (fn.expr) {
			case EFunction(_, f): f;
			case _:
				Context.error("catchString expects a function expression: () -> expr", fn.pos);
				return macro null;
		}

		if (f.args.length != 0) {
			Context.error("catchString callback must take 0 arguments", fn.pos);
		}

		var body = stripReturn(f.expr);
		return macro (try Ok(${asValueExpr(body)}) catch (e: Dynamic) Err(Std.string(e)));
		#else
		return macro null;
		#end
	}
}
