package reflaxe.rust.analyze;

import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.helpers.TypeHelper;

private typedef TypedSwitchCase = {
	var values:Array<TypedExpr>;
	var expr:TypedExpr;
}

/**
	Shares the conservative typed-Haxe control-flow facts used before and during Rust construction.

	Why / What / How
	- Early analysis used to keep scanning after an exhaustive switch while Rust lowering stopped, which
	  created saved `Dynamic` actions that could never be used. Nullable mutable-reference lowering had
	  the inverse problem: it treated the same exhaustive switch as incomplete and moved its `Option`.
	- This helper recognizes only control flow Haxe's typed tree proves: direct exits, complete `if`
	  expressions, and complete Bool or enum switches.
	- Uncertain patterns, nullable subjects, guards, and incomplete switches return `false`. Callers may
	  miss an optimization, but they must never discard reachable source or move a value on a guess.
**/
class TypedExprControlFlow {
	public static function stopsFollowingStatements(expression:TypedExpr):Bool {
		if (expression == null)
			return false;
		var current = unwrap(expression);
		return switch (current.expr) {
			case TReturn(_) | TThrow(_) | TBreak | TContinue:
				true;
			case TCast(inner, _):
				stopsFollowingStatements(inner);
			case TBlock(expressions):
				var stops = false;
				for (child in expressions) {
					if (stopsFollowingStatements(child)) {
						stops = true;
						break;
					}
				}
				stops;
			case TIf(_, thenExpression, elseExpression) if (elseExpression != null):
				stopsFollowingStatements(thenExpression) && stopsFollowingStatements(elseExpression);
			case TSwitch(subject, cases, defaultExpression):
				var complete = switchIsExhaustive(subject, cases, defaultExpression);
				if (complete) {
					for (entry in cases)
						if (!stopsFollowingStatements(entry.expr)) {
							complete = false;
							break;
						}
					if (complete && defaultExpression != null)
						complete = stopsFollowingStatements(defaultExpression);
				}
				complete;
			case _:
				false;
		};
	}

	/** Returns true only when every possible typed Bool/enum value has an unguarded case. */
	public static function switchIsExhaustive(subject:TypedExpr, cases:Array<TypedSwitchCase>, defaultExpression:Null<TypedExpr>):Bool {
		if (defaultExpression != null)
			return true;
		if (subject == null || cases == null || cases.length == 0 || isNullable(subject.t))
			return false;
		for (entry in cases)
			if (entry == null)
				return false;

		var current = unwrap(subject);
		switch (current.expr) {
			case TEnumIndex(enumExpression):
				var enumType = enumFromType(enumExpression.t);
				if (enumType == null || isNullable(enumExpression.t))
					return false;
				var seen:Map<Int, Bool> = [];
				for (entry in cases)
					for (value in entry.values)
						switch (unwrap(value).expr) {
							case TConst(TInt(index)): seen.set(index, true);
							case _: return false;
						}
				for (field in enumType.constructs)
					if (!seen.exists(field.index))
						return false;
				return true;
			case _:
		}

		if (TypeHelper.isBool(TypeTools.follow(subject.t))) {
			var sawTrue = false;
			var sawFalse = false;
			for (entry in cases)
				for (value in entry.values)
					switch (unwrap(value).expr) {
						case TConst(TBool(true)): sawTrue = true;
						case TConst(TBool(false)): sawFalse = true;
						case _: return false;
					}
			return sawTrue && sawFalse;
		}

		var enumType = enumFromType(subject.t);
		if (enumType == null)
			return false;
		var seenNames:Map<String, Bool> = [];
		for (entry in cases)
			for (value in entry.values) {
				var name = enumConstructorName(value);
				if (name == null)
					return false;
				seenNames.set(name, true);
			}
		for (name in enumType.constructs.keys())
			if (!seenNames.exists(name))
				return false;
		return true;
	}

	static function enumConstructorName(expression:TypedExpr):Null<String> {
		var current = unwrap(expression);
		return switch (current.expr) {
			case TCast(inner, _): enumConstructorName(inner);
			case TField(_, FEnum(_, field)): field.name;
			case TCall(target, _): switch (unwrap(target).expr) {
					case TField(_, FEnum(_, field)): field.name;
					case _: null;
				}
			case _: null;
		};
	}

	static function enumFromType(type:Type):Null<EnumType> {
		if (type == null)
			return null;
		return switch (TypeTools.follow(type)) {
			case TEnum(enumRef, _): enumRef.get();
			case _: null;
		};
	}

	static function isNullable(type:Type):Bool {
		if (type == null)
			return false;
		var spelling = TypeTools.toString(type);
		return spelling == "Null" || StringTools.startsWith(spelling, "Null<");
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
