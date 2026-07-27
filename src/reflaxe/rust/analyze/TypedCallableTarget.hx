package reflaxe.rust.analyze;

import haxe.macro.Type;
import haxe.macro.TypeTools;

/**
	Finds the real method or enum-constructor target behind wrappers that do not create a function value.

	Why
	- Haxe and macros can retain metadata, parentheses, or a same-type cast around a call target.
	- Treating those wrappers differently in representation and no-runtime analysis can invent a stored
	  function value or miss the exact `Sys`, `Type`, or `Reflect` call that requires runtime support.

	What
	- Removes metadata and parentheses.
	- Removes a cast only when both sides are function types with the same complete typed spelling.

	How
	- Callers inspect the returned expression only to classify the immediately invoked target.
	- Type-changing casts, locals, assignments, nested calls, and other expressions remain visible because
	  they may genuinely create or transform a first-class function value.
**/
class TypedCallableTarget {
	public static function transparent(expression:TypedExpr):TypedExpr {
		var current = expression;
		var changed = true;
		while (changed && current != null) {
			changed = false;
			switch (current.expr) {
				case TMeta(_, inner) | TParenthesis(inner):
					current = inner;
					changed = true;
				case TCast(inner, _) if (sameFunctionType(current.t, inner.t)):
					current = inner;
					changed = true;
				case _:
			}
		}
		return current;
	}

	static function sameFunctionType(outer:Type, inner:Type):Bool {
		if (outer == null || inner == null)
			return false;
		return switch [TypeTools.follow(outer), TypeTools.follow(inner)] {
			case [TFun(outerArguments, outerResult), TFun(innerArguments, innerResult)]:
				if (outerArguments.length != innerArguments.length || typeKey(outerResult) != typeKey(innerResult)) {
					false;
				} else {
					var same = true;
					for (index in 0...outerArguments.length) {
						var outerArgument = outerArguments[index];
						var innerArgument = innerArguments[index];
						if (outerArgument.opt != innerArgument.opt || typeKey(outerArgument.t) != typeKey(innerArgument.t)) {
							same = false;
							break;
						}
					}
					same;
				}
			case _:
				false;
		};
	}

	static inline function typeKey(type:Type):String
		return TypeTools.toString(TypeTools.follow(type));
}
