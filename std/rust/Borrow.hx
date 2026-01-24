package rust;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.TypeTools;
#end

class Borrow {
	public static macro function withRef(value: haxe.macro.Expr, fn: haxe.macro.Expr): haxe.macro.Expr {
		return expand(value, fn, false);
	}

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

		var bodyExpr = f.expr;
		return macro { $varDecl; $bodyExpr; };
	}
	#end
}
