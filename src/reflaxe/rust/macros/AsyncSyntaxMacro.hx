package reflaxe.rust.macros;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
#end

/**
 * AsyncSyntaxMacro
 *
 * Why:
 * - `@:await expr` metadata does not change Haxe typing on its own.
 * - Users expect await-style syntax to type as the inner value (`T`), not `Future<T>`.
 *
 * What:
 * - Rewrites `@:await e` / `@:rustAwait e` to `rust.async.Async.await(e)` before typing.
 *
 * How:
 * - Registered as a global `@:build(...)` macro while `-D rust_async_preview` is enabled.
 * - Applies to function bodies and field initializers in user/framework code.
 */
class AsyncSyntaxMacro {
	static var installed:Bool = false;

	public static function init():Void {
		#if eval
		if (installed)
			return;
		installed = true;
		Compiler.addGlobalMetadata("", "@:build(reflaxe.rust.macros.AsyncSyntaxMacro.apply())");
		#end
	}

	#if eval
	public static function apply():Null<Array<Field>> {
		var fields = Context.getBuildFields();
		for (field in fields) {
			switch (field.kind) {
				case FFun(fn):
					if (fn.expr != null) {
						var rewritten = rewriteExpr(fn.expr);
						if (hasAsyncFunctionMeta(field)) {
							rewritten = rewriteAsyncFunctionBody(rewritten);
						}
						fn.expr = rewritten;
					}
				case FVar(t, expr):
					if (expr != null)
						field.kind = FVar(t, rewriteExpr(expr));
				case FProp(get, set, t, expr):
					if (expr != null)
						field.kind = FProp(get, set, t, rewriteExpr(expr));
			}
		}
		return fields;
	}

	static function rewriteExpr(expr:Expr):Expr {
		return switch (expr.expr) {
			case EMeta(meta, inner) if (isAwaitMeta(meta.name)):
				if (meta.params != null && meta.params.length > 0) {
					Context.error("`@" + meta.name + "` does not take parameters.", meta.pos);
				}
				var rewrittenInner = rewriteExpr(inner);
				var call = macro rust.async.Async.await($rewrittenInner);
				call.pos = expr.pos;
				call;
			case _:
				ExprTools.map(expr, rewriteExpr);
		}
	}

	static function hasAsyncFunctionMeta(field:Field):Bool {
		if (field.meta == null)
			return false;
		for (meta in field.meta) {
			if (isAsyncMeta(meta.name))
				return true;
		}
		return false;
	}

	static function rewriteAsyncFunctionBody(expr:Expr):Expr {
		var rewritten = rewriteAsyncReturns(expr);
		return ensureTopLevelReturn(rewritten);
	}

	static function rewriteAsyncReturns(expr:Expr):Expr {
		return switch (expr.expr) {
			case EFunction(_, _):
				// Keep nested/local functions untouched.
				expr;
			case EReturn(value):
				if (value == null) {
					expr;
				} else {
					var rewrittenValue = rewriteAsyncReturns(value);
					{
						expr: EReturn(isAsyncReadyCallExpr(rewrittenValue) ? rewrittenValue : makeReady(rewrittenValue)),
						pos: expr.pos
					};
				}
			case EBlock(exprs):
				{expr: EBlock([for (e in exprs) rewriteAsyncReturns(e)]), pos: expr.pos};
			case _:
				ExprTools.map(expr, rewriteAsyncReturns);
		}
	}

	static function ensureTopLevelReturn(expr:Expr):Expr {
		var unwrapped = unwrapMetaParen(expr);
		return switch (unwrapped.expr) {
			case EBlock(exprs):
				var rewrittenExprs = exprs.copy();
				if (rewrittenExprs.length > 0) {
					var lastIdx = rewrittenExprs.length - 1;
					var last = rewrittenExprs[lastIdx];
					if (!isTerminatingExpr(last)) {
						rewrittenExprs[lastIdx] = makeReturn(last);
					}
				}
				{expr: EBlock(rewrittenExprs), pos: expr.pos};
			case EReturn(_) | EThrow(_) | EBreak | EContinue:
				expr;
			case _:
				makeBlockReturn(expr);
		}
	}

	static function makeReturn(value:Expr):Expr {
		var outValue = isAsyncReadyCallExpr(value) ? value : makeReady(value);
		return {expr: EReturn(outValue), pos: value.pos};
	}

	static function makeBlockReturn(value:Expr):Expr {
		return {expr: EBlock([makeReturn(value)]), pos: value.pos};
	}

	static function makeReady(value:Expr):Expr {
		var call = macro rust.async.Async.ready($value);
		call.pos = value.pos;
		return call;
	}

	static function isTerminatingExpr(expr:Expr):Bool {
		return switch (unwrapMetaParen(expr).expr) {
			case EReturn(_) | EThrow(_) | EBreak | EContinue: true;
			case _: false;
		}
	}

	static function isAsyncReadyCallExpr(expr:Expr):Bool {
		return switch (unwrapMetaParen(expr).expr) {
			case ECall(target, args) if (args.length == 1):
				isAsyncReadyTarget(target);
			case _:
				false;
		}
	}

	static function isAsyncReadyTarget(expr:Expr):Bool {
		return switch (unwrapMetaParen(expr).expr) {
			case EField(owner, field): field == "ready" && switch (unwrapMetaParen(owner).expr) {
					case EField(pkg, asyncName): asyncName == "Async" && switch (unwrapMetaParen(pkg).expr) {
							case EField(rustPkg, asyncPkg): asyncPkg == "async" && switch (unwrapMetaParen(rustPkg).expr) {
									case EConst(CIdent("rust")): true;
									case _: false;
								} case _: false;
						} case _: false;
				};
			case _:
				false;
		}
	}

	static function unwrapMetaParen(expr:Expr):Expr {
		var cur = expr;
		while (true) {
			cur = switch (cur.expr) {
				case EMeta(_, inner): inner;
				case EParenthesis(inner): inner;
				case _:
					return cur;
			}
		}
		return cur;
	}

	static inline function isAsyncMeta(name:String):Bool {
		return name == ":async" || name == "async" || name == ":rustAsync" || name == "rustAsync";
	}

	static inline function isAwaitMeta(name:String):Bool {
		return name == ":await" || name == "await" || name == ":rustAwait" || name == "rustAwait";
	}
	#end
}
