package reflaxe.rust.analyze;

import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;

/**
	Shares source-expression rules that decide whether one Haxe expression is emitted more than once.

	Why / What / How
	- Haxe stores a default argument on the function declaration, while Rust lowering inserts that
	  expression at every omitted call. Early analysis must save an action only when lowering will
	  actually replay the expression.
	- The rule admits constants and recursively literal-shaped expressions. It rejects locals, `this`,
	  control flow, and other shapes whose meaning depends on the declaration-side scope.
	- Both the early saved-decision collector and call/constructor lowering call this exact helper, so
	  an unsafe default cannot create an unused action and a safe default cannot be emitted unplanned.
**/
class TypedExprEmissionPolicy {
	/**
		Returns the literal initializer that Rust lowering inserts at each read of a read-only static field.

		Why / What / How
		- Reflaxe may omit storage for `static final` literal values, so the Rust builder emits the literal at
		  every read instead.
		- Haxe exposes the same read-only fact in two lifecycle shapes: `isFinal` during early typed
		  analysis and `AccNever` once field access has been normalized for lowering. Accept either shape,
		  then require a constant through metadata, parentheses, or harmless casts. Calls, objects, arrays,
		  and other identity/effect-bearing values remain rejected.
		- Early analysis calls this same helper at static-read sites, so an unused declaration creates no
		  saved action and every emitted read uses the one explicit replay family.
	**/
	public static function staticReadOnlyConstantExpr(field:ClassField):Null<TypedExpr> {
		if (field == null)
			return null;
		var readOnly = field.isFinal;
		switch (field.kind) {
			case FVar(_, AccNever):
				readOnly = true;
			case _:
		}
		if (!readOnly)
			return null;
		var initializer:Null<TypedExpr> = null;
		try
			initializer = field.expr()
		catch (_:haxe.Exception) {}
		if (initializer == null)
			return null;
		return constantThroughWrappers(initializer);
	}

	public static function defaultArgumentIsCallsiteSafe(expression:TypedExpr):Bool {
		if (expression == null)
			return false;
		var current = unwrap(expression);
		return switch (current.expr) {
			case TConst(_):
				true;
			case TArrayDecl(values):
				all(values, defaultArgumentIsCallsiteSafe);
			case TObjectDecl(fields):
				if (fields == null) {
					true;
				} else {
					var safe = true;
					for (field in fields)
						if (field == null || !defaultArgumentIsCallsiteSafe(field.expr)) {
							safe = false;
							break;
						}
					safe;
				}
			case TBinop(_, left, right):
				defaultArgumentIsCallsiteSafe(left) && defaultArgumentIsCallsiteSafe(right);
			case TUnop(_, _, value):
				defaultArgumentIsCallsiteSafe(value);
			case TCall(target, arguments):
				defaultArgumentIsCallsiteSafe(target) && all(arguments, defaultArgumentIsCallsiteSafe);
			case TNew(_, _, arguments):
				all(arguments, defaultArgumentIsCallsiteSafe);
			case TCast(inner, _):
				defaultArgumentIsCallsiteSafe(inner);
			case TTypeExpr(_):
				true;
			case _:
				false;
		};
	}

	static function all(values:Array<TypedExpr>, predicate:TypedExpr->Bool):Bool {
		if (values == null)
			return true;
		for (value in values)
			if (value == null || !predicate(value))
				return false;
		return true;
	}

	static function constantThroughWrappers(expression:TypedExpr):Null<TypedExpr> {
		var current = unwrap(expression);
		return switch (current.expr) {
			case TConst(_): current;
			case TCast(inner, _): constantThroughWrappers(inner);
			case _: null;
		};
	}

	static function unwrap(expression:TypedExpr):TypedExpr {
		var current = expression;
		var changed = true;
		while (changed && current != null) {
			changed = false;
			switch (current.expr) {
				case TMeta(_, inner) | TParenthesis(inner):
					current = inner;
					changed = true;
				case _:
			}
		}
		return current;
	}
}
