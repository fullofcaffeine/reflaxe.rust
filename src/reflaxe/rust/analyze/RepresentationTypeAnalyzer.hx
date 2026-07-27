package reflaxe.rust.analyze;

import haxe.macro.Context;
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.helpers.TypeHelper;
import reflaxe.rust.analyze.RepresentationPlan.RustBoundaryKind;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustEscapeFact;
import reflaxe.rust.analyze.RepresentationPlan.RustIdentityFact;
import reflaxe.rust.analyze.RepresentationPlan.RustMutationFact;
import reflaxe.rust.analyze.RepresentationPlan.RustNullabilityFact;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationFacts;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationPlanner;
import reflaxe.rust.analyze.RepresentationPlan.RustReusePolicy;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSurfaceFact;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustDynamicCrossingTypeCheck;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustDynamicCrossingSourceFingerprint;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustDynamicValueMaterialization;

/**
	Extracts the shared Rust representation plan from real typed Haxe values.

	Why
	- Type lowering, clone insertion, runtime planning, and no-hxrt checks previously classified the
	  same `Type` independently.
	- The pure planner cannot inspect Haxe compiler types itself, so it needs one typed adapter that
	  turns source-language facts into its closed vocabulary.

	What
	- Recognizes the value families whose representation contract is already explicit: scalars,
	  enums, class identity, trait objects, Rust borrows and owned values, native RAII handles,
	  dynamic values, strings, arrays, anonymous objects, functions, and iterators.
	- Returns `null` from `tryDecide` for an as-yet unmodeled compiler type instead of inventing a
	  misleading plan. `decide` is the fail-closed contract entry used by focused tests.

	How
	- Null/typedef/lazy wrappers are normalized before classification, while Rust borrow abstracts are
	  inspected before following would erase their target-shaped meaning.
	- Identity, mutation, escape, surface, and nullability facts are derived once from the selected
	  source family, then validated by `RustRepresentationFacts.of` and decided by the pure planner.
**/
class RepresentationTypeAnalyzer {
	/** Build one required local decision, failing when the typed family has no admitted model yet. */
	public static function decide(subjectId:String, type:Type, pos:Position, origin:RustDecisionOrigin, nullableStringCompat:Bool,
			?boundary:RustBoundaryKind = BoundaryLocal, ?classHasSubclasses:ClassType->Bool):RustRepresentationDecision {
		var decision = tryDecide(subjectId, type, pos, origin, nullableStringCompat, boundary, classHasSubclasses);
		if (decision == null)
			throw 'No Rust representation decision is modeled for `${TypeTools.toString(type)}`';
		return decision;
	}

	/**
		Build one local decision when the value family is modeled.

		Why / What / How
		- Compiler internals still contain a few open monomorph/core-type compatibility fallbacks. Those
		  are not allowed to masquerade as an ordinary owned value.
		- Callers may preserve their existing explicit fallback only when this method returns `null`.
	**/
	public static function tryDecide(subjectId:String, type:Type, pos:Position, origin:RustDecisionOrigin, nullableStringCompat:Bool,
			?boundary:RustBoundaryKind = BoundaryLocal, ?classHasSubclasses:ClassType->Bool):Null<RustRepresentationDecision> {
		if (type == null || origin == null)
			return null;
		var normalized = unwrapAliasesAndNull(type);
		var sourceKind = sourceKind(normalized.type, nullableStringCompat, classHasSubclasses);
		if (sourceKind == null)
			return null;
		return decideSourceKind(subjectId, sourceKind, normalized.nullable, origin, boundary);
	}

	/**
		Builds the decision for a real value crossing into a different representation boundary.

		Why
		- A concrete argument passed to `Dynamic` still has a scalar/class/enum source type in Haxe's
		  typed AST. Looking only at that local type cannot explain the runtime boxing emitted later.
		- Callers previously inferred this crossing independently from the expected parameter type.

		What
		- Returns a `BoundaryDynamic` decision for a modeled non-Dynamic value whose expected type is
		  Dynamic (including typedef aliases such as `haxe.Json`'s input type).
		- For `rust.Ref<T>`, describes the copied or cloned `T` value that lowering can materialize. A
		  mutable borrow and an owned native value without a proven clone stay unmodeled instead of claiming
		  that the short-lived reference itself can enter Dynamic.
		- Returns `null` when no representation-changing crossing occurs.

		How
		- Both actual and expected types pass through the same normalization/classification authority as
		  ordinary storage decisions. The returned decision retains the actual source family and exact
		  expression origin while the boundary adds Dynamic runtime requirements and bounds.
	**/
	public static function tryDecideCrossing(subjectId:String, actualType:Type, expectedType:Type, pos:Position, origin:RustDecisionOrigin,
			nullableStringCompat:Bool, ?classHasSubclasses:ClassType->Bool):Null<RustRepresentationDecision> {
		if (actualType == null || expectedType == null || origin == null)
			return null;
		var typeCheck = tryDynamicCrossingTypeCheck(actualType, expectedType, nullableStringCompat, classHasSubclasses);
		if (typeCheck == null)
			return null;
		var crossingType = typeCheck.carrierKind == SourceBorrowedRef ? immutableReferenceValueType(actualType) : actualType;
		if (crossingType == null)
			return null;
		var decision = tryDecide(subjectId, crossingType, pos, origin, nullableStringCompat, BoundaryDynamic, classHasSubclasses);
		return decision != null && decision.sourceKind == typeCheck.valueKind ? decision : null;
	}

	/**
		Builds the small source-shape check that must match before lowering consumes a saved action.

		Why / What / How
		- Lowering must verify the actual carrier and expected boundary without rebuilding the planner's
		  representation decision.
		- Direct values retain their source family. Immutable `rust.Ref<T>` values are admitted only when
		  the compiler can prove how to obtain an owned `T`: dereference a Copy value or clone a known
		  concrete Clone value.
		- Generic/native-handle/mutable borrow cases return `null`, so they fail at the Haxe boundary rather
		  than attempting to store a short-lived Rust reference.
	**/
	public static function tryDynamicCrossingTypeCheck(actualType:Type, expectedType:Type, nullableStringCompat:Bool,
			?classHasSubclasses:ClassType->Bool):Null<RustDynamicCrossingTypeCheck> {
		if (actualType == null || expectedType == null
			|| classify(expectedType, nullableStringCompat, classHasSubclasses) != SourceDynamic)
			return null;
		var carrierKind = classify(actualType, nullableStringCompat, classHasSubclasses);
		if (carrierKind == null || carrierKind == SourceDynamic)
			return null;
		var valueKind = carrierKind;
		var materialization = RustDynamicValueMaterialization.DynamicValueDirect;
		if (isBorrowed(carrierKind)) {
			if (carrierKind != SourceBorrowedRef)
				return null;
			var innerType = immutableReferenceValueType(actualType);
			if (innerType == null)
				return null;
			valueKind = classify(innerType, nullableStringCompat, classHasSubclasses);
			if (valueKind == null)
				return null;
			materialization = if (valueKind == SourceScalar || valueKind == SourceCoreHandle) {
				RustDynamicValueMaterialization.DynamicValueBorrowCopy;
			} else if (knownConcreteBorrowCloneValue(innerType, valueKind, nullableStringCompat, classHasSubclasses)) {
				RustDynamicValueMaterialization.DynamicValueBorrowClone;
			} else {
				return null;
			}
		}
		var fingerprint = RustDynamicCrossingSourceFingerprint.validated(TypeTools.toString(actualType), carrierKind, valueKind, materialization);
		return RustDynamicCrossingTypeCheck.validated(fingerprint, "Dynamic");
	}

	/**
		Explains why a scoped borrowed value cannot become owned `Dynamic` storage.

		Why / What / How
		- A missing saved action used to reach Rust construction and appear as an internal compiler error,
		  even when typed Haxe already proved that a temporary reference could not outlive its borrow scope.
		- Return a beginner-readable reason only for a real borrowed-to-Dynamic boundary that this compiler
		  cannot materialize as an owned value.
		- Keep supported Copy and known concrete Clone cases silent. Generic inner values, native resources,
		  mutable borrows, strings/slices, and unproved shapes fail at the exact Haxe expression instead.
	**/
	public static function dynamicCrossingRejectionReason(actualType:Type, expectedType:Type, nullableStringCompat:Bool,
			?classHasSubclasses:ClassType->Bool):Null<String> {
		if (actualType == null || expectedType == null
			|| classify(expectedType, nullableStringCompat, classHasSubclasses) != SourceDynamic)
			return null;
		var carrierKind = classify(actualType, nullableStringCompat, classHasSubclasses);
		if (carrierKind == null || !isBorrowed(carrierKind)
			|| tryDynamicCrossingTypeCheck(actualType, expectedType, nullableStringCompat, classHasSubclasses) != null)
			return null;

		var source = TypeTools.toString(actualType);
		if (carrierKind != SourceBorrowedRef)
			return '`$source` cannot enter Dynamic because this borrowed view has no admitted owned conversion. '
				+ "Create an owned value inside the borrow callback before storing or passing it.";

		var innerType = immutableReferenceValueType(actualType);
		if (innerType != null && containsTypeParameter(innerType))
			return '`$source` cannot enter Dynamic because its generic inner type does not prove Copy or Clone. '
				+ "Add a supported owned conversion at the source boundary.";
		var innerKind = innerType == null ? null : classify(innerType, nullableStringCompat, classHasSubclasses);
		if (innerKind == SourceNativeHandle)
			return '`$source` cannot enter Dynamic because its native handle cannot be copied or cloned into owned runtime storage. '
				+ "Convert the resource to an owned supported value instead.";
		return '`$source` cannot enter Dynamic because the compiler cannot prove how to copy or clone an owned inner value. '
			+ "Create an owned value inside the borrow callback before the boundary.";
	}

	/**
		Answers whether an immutable `rust.Ref<T>` can provide one owned `T` for Dynamic storage.

		Why / What / How
		- Ordinary reuse policy says whether a source value normally moves or clones; it does not prove that
		  a value behind a borrow can be copied out before the borrow ends.
		- Admit concrete Haxe/runtime reference carriers and a closed set of Rust-native Clone values. Check
		  `Vec`/`HashMap` element types recursively.
		- Reject type parameters, mutable/other borrow carriers, Dynamic, and native resource handles until
		  a real bound or owned conversion proves the operation.
	**/
	static function knownConcreteBorrowCloneValue(type:Type, kind:RustSourceValueKind, nullableStringCompat:Bool,
			classHasSubclasses:Null<ClassType->Bool>):Bool {
		if (type == null || containsTypeParameter(type) || kind == SourceDynamic || kind == SourceNativeHandle || isBorrowed(kind))
			return false;
		if (kind != SourceNativeOwned)
			return kind != SourceScalar && kind != SourceCoreHandle;
		return switch (unwrapAliasesAndNull(type).type) {
			case TInst(classRef, parameters):
				var classType = classRef.get();
				if (classType == null) {
					false;
				} else {
					var path = typePath(classType.pack, classType.name);
					var declaredModule = classType.module;
					switch (declaredModule) {
						case "rust.PathBuf" | "rust.OsString" | "rust.Duration" | "rust.Instant" | "rust.SystemTime"
							| "rust.net.SocketAddr":
							true;
						case "rust.Vec" | "rust.HashMap":
							var cloneable = parameters.length > 0;
							for (parameter in parameters) {
								var parameterKind = classify(parameter, nullableStringCompat, classHasSubclasses);
								if (parameterKind == null
									|| !knownConcreteBorrowCloneValue(parameter, parameterKind, nullableStringCompat, classHasSubclasses)
										&& parameterKind != SourceScalar && parameterKind != SourceCoreHandle) {
									cloneable = false;
									break;
								}
							}
							cloneable;
						case _:
							// Before Reflaxe target-name shaping, the declared package/name path is still
							// available directly. After shaping (for example PathBuf -> std::path::PathBuf),
							// `module` above remains the stable Haxe facade identity.
							path == "rust.PathBuf" || path == "rust.OsString" || path == "rust.Duration" || path == "rust.Instant"
								|| path == "rust.SystemTime" || path == "rust.net.SocketAddr";
					}
				}
			case _:
				false;
		};
	}

	/**
		Returns the owned value that current Dynamic lowering copies out of a Rust reference.

		Why / What / How
		- `rust.Ref<T>` is emitted as `&T`; calling `.clone()` at a Dynamic boundary copies `T`, not the
		  reference token. Describing the token as escaping would violate the planner's borrow-scope rule.
		- Unwrap aliases and `Null`, then admit only one-parameter immutable `rust.Ref`.
		- Borrowed strings and slices need different owned conversions, so they stay unmodeled here instead
		  of receiving a misleading decision.
	**/
	public static function immutableReferenceValueType(type:Type):Null<Type> {
		var normalized = unwrapAliasesAndNull(type).type;
		return switch (normalized) {
			case TAbstract(abstractRef, parameters) if (parameters.length == 1):
				var abstractType = abstractRef.get();
				if (abstractType == null)
					null;
				else {
					var path = typePath(abstractType.pack, abstractType.name);
					path == "rust.Ref" ? parameters[0] : null;
				}
			case _:
				null;
		};
	}

	/**
		Explains why a runtime anonymous-object field cannot expose `rust.Ref<T>`.

		Why
		- Anonymous storage owns a concrete runtime value and reads it back by its exact stored Rust type.
		- Turning `rust.Ref<T>` into owned `T` on write but still reading the declared field as `&T` makes
		  the runtime downcast fail. Keeping the short-lived `&T` would instead let a borrow escape.

		What
		- Rejects immutable `rust.Ref<T>` fields, including `Null<rust.Ref<T>>`, before Rust construction.

		How
		- Reuse the same alias/null-aware reference recognizer as Dynamic materialization.
		- Full support requires a future stored-versus-exposed field contract with a guard-bound read
		  lifetime; this compiler does not pretend that an owned clone is still a scoped reference.
	**/
	public static function anonymousBorrowedFieldRejectionReason(type:Type):Null<String> {
		if (type == null || immutableReferenceValueType(type) == null)
			return null;
		return "runtime anonymous objects cannot safely expose this `rust.Ref<T>` field: storing the reference would let a "
			+ "short-lived borrow escape, while storing an owned `T` would no longer match the declared reference type. "
			+ "Store an owned value instead.";
	}

	/**
		Reports whether Haxe-style string conversion needs the runtime Dynamic formatter.

		Why / What / How
		- `Std.string` is declared with a Dynamic parameter, but the Rust backend directly formats strings,
		  numbers, booleans, and open generic values without creating a Dynamic box.
		- Saving a Dynamic action for those direct conversions would make no-hxrt reject code that emits no
		  Dynamic runtime call, and the saved action could never be consumed by lowering.
		- Keep this one typed rule shared by early call analysis and lowering. All other modeled concrete
		  values use the runtime formatter and therefore require a saved Dynamic action.
	**/
	public static function stringFormattingNeedsDynamic(type:Type, nullableStringCompat:Bool,
			?classHasSubclasses:ClassType->Bool):Bool {
		if (type == null || containsTypeParameter(type))
			return false;
		return switch (classify(type, nullableStringCompat, classHasSubclasses)) {
			case SourceString | SourceNullableStringCompat | SourceScalar | SourceDynamic:
				false;
			case null:
				false;
			case _:
				true;
		};
	}

	/**
		Builds a crossing decision from an expression whose outer Haxe type may already be contextual.

		Why / What / How
		- Haxe can type `return if (...) 1 else 2` as Dynamic because the function result is Dynamic,
		  even though the control expression still boxes a concrete scalar result.
		- Follow transparent block/control/cast result edges only when the outer expression is already
		  Dynamic, and admit a concrete source type only when every reachable result branch has the same
		  modeled source family.
		- The decision remains anchored to the complete crossing expression, not to an arbitrary branch.
	**/
	public static function tryDecideExprCrossing(subjectId:String, expression:TypedExpr, expectedType:Type, origin:RustDecisionOrigin,
			nullableStringCompat:Bool, ?classHasSubclasses:ClassType->Bool):Null<RustRepresentationDecision> {
		if (expression == null)
			return null;
		var actualType = concreteContextualResultType(expression, nullableStringCompat, classHasSubclasses);
		return tryDecideCrossing(subjectId, actualType, expectedType, expression.pos, origin, nullableStringCompat, classHasSubclasses);
	}

	static function concreteContextualResultType(expression:TypedExpr, nullableStringCompat:Bool,
			classHasSubclasses:Null<ClassType->Bool>):Type {
		if (expression == null || classify(expression.t, nullableStringCompat, classHasSubclasses) != SourceDynamic)
			return expression == null ? null : expression.t;

		function commonResult(expressions:Array<TypedExpr>):Null<Type> {
			var selected:Null<Type> = null;
			var selectedKind:Null<RustSourceValueKind> = null;
			for (candidate in expressions) {
				if (candidate == null)
					return null;
				var candidateType = concreteContextualResultType(candidate, nullableStringCompat, classHasSubclasses);
				var candidateKind = classify(candidateType, nullableStringCompat, classHasSubclasses);
				if (candidateKind == null || candidateKind == SourceDynamic)
					return null;
				if (selectedKind == null) {
					selectedKind = candidateKind;
					selected = candidateType;
				} else if (selectedKind != candidateKind) {
					return null;
				}
			}
			return selected;
		}

		var current = expression;
		var changed = true;
		while (changed) {
			changed = false;
			switch (current.expr) {
				case TMeta(_, inner) | TParenthesis(inner):
					current = inner;
					changed = true;
				case _:
			}
		}

		return switch (current.expr) {
			case TIf(_, thenExpr, elseExpr) if (elseExpr != null):
				var common = commonResult([thenExpr, elseExpr]);
				common == null ? expression.t : common;
			case TSwitch(_, cases, defaultExpr):
				var results = [for (entry in cases) entry.expr];
				if (defaultExpr != null) results.push(defaultExpr);
				var common = commonResult(results);
				common == null ? expression.t : common;
			case TBlock(expressions) if (expressions.length > 0):
				concreteContextualResultType(expressions[expressions.length - 1], nullableStringCompat, classHasSubclasses);
			case TCast(inner, _):
				concreteContextualResultType(inner, nullableStringCompat, classHasSubclasses);
			case _:
				expression.t;
		};
	}

	/**
		Build a decision for a typed-AST construct whose syntax preserves a more precise family than its
		coerced result type.

		Why / What / How
		- A Haxe anonymous-object literal coerced to `Dynamic` has a dynamic result type, but creating it
		  still requires anonymous-object storage.
		- Callers may use this only with a closed source kind established by typed syntax; all remaining
		  facts are derived and validated here exactly as they are for ordinary `Type` extraction.
	**/
	public static function decideSourceKind(subjectId:String, sourceKind:RustSourceValueKind, explicitlyNullable:Bool, origin:RustDecisionOrigin,
			?boundary:RustBoundaryKind = BoundaryLocal):RustRepresentationDecision {
		if (sourceKind == null || origin == null)
			throw "Typed representation source decisions require a source kind and origin";
		var identity:RustIdentityFact = switch (sourceKind) {
			case SourceClassReference | SourcePolymorphicReference | SourceArray | SourceAnonymousObject | SourceFunctionValue | SourceIterator
				| SourceBytesReference:
				IdentityStable;
			case _:
				IdentityNone;
		};
		var mutation:RustMutationFact = switch (sourceKind) {
			case SourceBorrowedMutRef | SourceBorrowedMutSlice:
				MutationExclusiveBorrow;
			case SourceClassReference | SourcePolymorphicReference | SourceArray | SourceAnonymousObject | SourceIterator | SourceBytesReference
				| SourceDynamic:
				MutationShared;
			case SourceNativeOwned | SourceNativeHandle:
				MutationOwned;
			case _:
				MutationImmutable;
		};
		var borrowed = isBorrowed(sourceKind);
		var escape:RustEscapeFact = borrowed ? EscapeLocal : EscapeMay;
		var surface:RustSurfaceFact = switch (sourceKind) {
			case SourceBorrowedRef | SourceBorrowedMutRef | SourceBorrowedStr | SourceBorrowedSlice | SourceBorrowedMutSlice | SourceNativeOwned
				| SourceNativeHandle:
				SurfaceRustNative;
			case SourcePortableFacade:
				SurfacePortableFacade;
			case _:
				SurfacePortableHaxe;
		};
		var intrinsicallyNullable = switch (sourceKind) {
			case SourceClassReference | SourcePolymorphicReference | SourceDynamic | SourceArray | SourceAnonymousObject | SourceFunctionValue
				| SourceNullableStringCompat | SourceCoreHandle | SourceBytesReference:
				true;
			case _:
				false;
		};
		var nullability:RustNullabilityFact = explicitlyNullable || intrinsicallyNullable ? Nullable : NonNullable;
		var facts = RustRepresentationFacts.of(subjectId, sourceKind, identity, mutation, escape, surface, nullability, boundary, origin);
		return RustRepresentationPlanner.decide(facts);
	}

	/** Returns the normalized source family without constructing a decision. */
	public static function classify(type:Type, nullableStringCompat:Bool, ?classHasSubclasses:ClassType->Bool):Null<RustSourceValueKind> {
		if (type == null)
			return null;
		return sourceKind(unwrapAliasesAndNull(type).type, nullableStringCompat, classHasSubclasses);
	}

	static function sourceKind(type:Type, nullableStringCompat:Bool, classHasSubclasses:Null<ClassType->Bool>):Null<RustSourceValueKind> {
		if (TypeHelper.isBool(type) || TypeHelper.isInt(type) || TypeHelper.isFloat(type))
			return SourceScalar;
		if (isString(type))
			return nullableStringCompat ? SourceNullableStringCompat : SourceString;

		switch (type) {
			case TDynamic(_):
				return SourceDynamic;
			case TAbstract(abstractRef, parameters):
				var abstractType = abstractRef.get();
				if (abstractType == null)
					return null;
				var path = typePath(abstractType.pack, abstractType.name);
				switch (path) {
					case "Map" | "haxe.ds.Map": return SourceClassReference;
					case "rust.Ref" if (parameters.length == 1): return SourceBorrowedRef;
					case "rust.MutRef" if (parameters.length == 1): return SourceBorrowedMutRef;
					case "rust.Str" if (parameters.length == 0): return SourceBorrowedStr;
					case "rust.Slice" if (parameters.length == 1): return SourceBorrowedSlice;
					case "rust.MutSlice" if (parameters.length == 1): return SourceBorrowedMutSlice;
					case "rust.HxRef" if (parameters.length == 1): return SourceClassReference;
					case _:
				}
				if (abstractType.meta != null && abstractType.meta.has(":coreType")) {
					if (abstractType.module == "StdTypes" && abstractType.name == "Dynamic")
						return SourceDynamic;
					if ((abstractType.name == "Class" || abstractType.name == "Enum")
						&& (abstractType.module == "StdTypes" || abstractType.pack.length == 0))
						return SourceCoreHandle;
					return null;
				}
				var followedAbstract = followType(type);
				var remainsSameAbstract = switch (followedAbstract) {
					case TAbstract(followedRef, _):
						var followedType = followedRef.get();
						followedType != null && typePath(followedType.pack, followedType.name) == path;
					case _: false;
				};
				if (!remainsSameAbstract)
					return sourceKind(unwrapAliasesAndNull(followedAbstract).type, nullableStringCompat, classHasSubclasses);
				var underlying = abstractType.type;
				if (abstractType.params != null && abstractType.params.length > 0 && parameters.length == abstractType.params.length)
					underlying = TypeTools.applyTypeParameters(underlying, abstractType.params, parameters);
				return sourceKind(unwrapAliasesAndNull(underlying).type, nullableStringCompat, classHasSubclasses);
			case _:
		}

		return switch (type) {
			case TFun(_, _):
				SourceFunctionValue;
			case TAnonymous(anonymousRef):
				isIteratorAnonymous(anonymousRef.get()) ? SourceIterator : SourceAnonymousObject;
			case TEnum(enumRef, _):
				var enumType = enumRef.get();
				if (enumType == null) null else if (isPortableFacade(typePath(enumType.pack, enumType.name))) SourcePortableFacade else SourceEnumValue;
			case TInst(classRef, parameters):
				var classType = classRef.get();
				if (classType == null) {
					null;
				} else {
					var path = typePath(classType.pack, classType.name);
					switch (classType.kind) {
						case _ if ((path == "Class" || path == "Enum") && (classType.module == "StdTypes" || classType.pack.length == 0)):
							SourceCoreHandle;
						case KTypeParameter(_): null;
						case _ if (isHaxeArray(classType)): SourceArray;
						case _ if (isArrayIterator(classType, parameters)): SourceIterator;
						case _ if (path == "haxe.io.Bytes"): SourceBytesReference;
						case _ if (isNativeHandle(path) || isNativeHandle(classType.module)): SourceNativeHandle;
						case _ if (isNativeOwned(classType, path)): SourceNativeOwned;
						case _ if (classType.isInterface || (classHasSubclasses != null && classHasSubclasses(classType))): SourcePolymorphicReference;
						case _ if (!classType.isExtern): SourceClassReference;
						case _: null;
					}
				}
			case TDynamic(_): SourceDynamic;
			case TMono(monomorphRef):
				var resolved = monomorphRef.get();
				resolved == null ? null : sourceKind(unwrapAliasesAndNull(resolved).type, nullableStringCompat, classHasSubclasses);
			case _: null;
		};
	}

	/**
		Reports whether a value type still depends on an open Haxe type parameter.

		Why / What / How
		- Runtime Dynamic boxing requires Rust `Any + 'static`, which an unresolved generic parameter cannot
		  promise until the later contextual-bound milestone is implemented.
		- Follow aliases, lazy/monomorph nodes, container parameters, function signatures, and anonymous
		  fields so a nested open parameter is not mistaken for a concrete boxable value.
		- String formatting uses this conservative answer to retain its direct Debug fallback rather than
		  saving a Dynamic action lowering cannot legally emit.
	**/
	static function containsTypeParameter(type:Type):Bool {
		if (type == null)
			return false;
		return switch (type) {
			case TLazy(resolve):
				containsTypeParameter(resolve());
			case TType(typeRef, parameters):
				var typedefType = typeRef.get();
				if (typedefType == null) {
					false;
				} else {
					var underlying = typedefType.type;
					if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
						underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
					containsTypeParameter(underlying);
				}
			case TInst(classRef, parameters):
				var classType = classRef.get();
				if (classType != null) {
					switch (classType.kind) {
						case KTypeParameter(_): true;
						case _: anyTypeParameter(parameters);
					}
				} else {
					anyTypeParameter(parameters);
				}
			case TEnum(_, parameters) | TAbstract(_, parameters):
				anyTypeParameter(parameters);
			case TFun(arguments, result):
				var found = containsTypeParameter(result);
				if (!found)
					for (argument in arguments)
						if (containsTypeParameter(argument.t)) {
							found = true;
							break;
						}
				found;
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				var found = false;
				if (anonymous != null && anonymous.fields != null)
					for (field in anonymous.fields)
						if (containsTypeParameter(field.type)) {
							found = true;
							break;
						}
				found;
			case TDynamic(inner):
				inner != null && containsTypeParameter(inner);
			case TMono(monomorphRef):
				var resolved = monomorphRef.get();
				resolved != null && containsTypeParameter(resolved);
		};
	}

	static function anyTypeParameter(types:Array<Type>):Bool {
		if (types == null)
			return false;
		for (type in types)
			if (containsTypeParameter(type))
				return true;
		return false;
	}

	static function unwrapAliasesAndNull(type:Type):{type:Type, nullable:Bool} {
		var current = type;
		var nullable = false;
		var changed = true;
		while (changed && current != null) {
			changed = false;
			switch (current) {
				case TLazy(resolve):
					current = resolve();
					changed = true;
				case TType(typeRef, parameters):
					var typedefType = typeRef.get();
					if (typedefType != null) {
						var underlying = typedefType.type;
						if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
							underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
						current = underlying;
						changed = true;
					}
				case TAbstract(abstractRef, parameters):
					var abstractType = abstractRef.get();
					if (abstractType != null && abstractType.module == "StdTypes" && abstractType.name == "Null" && parameters.length == 1) {
						nullable = true;
						current = parameters[0];
						changed = true;
					}
				case _:
			}
		}
		return {type: current, nullable: nullable};
	}

	static function isString(type:Type):Bool {
		if (TypeHelper.isString(type))
			return true;
		return switch (type) {
			case TInst(classRef, []):
				var classType = classRef.get();
				classType != null && classType.pack.length == 0 && classType.name == "String";
			case TAbstract(abstractRef, []):
				var abstractType = abstractRef.get();
				abstractType != null && abstractType.module == "StdTypes" && abstractType.name == "String";
			case _: TypeTools.toString(type) == "String" || TypeTools.toString(type) == "StdTypes.String";
		};
	}

	static function isIteratorAnonymous(anonymous:AnonType):Bool {
		if (anonymous == null || anonymous.fields == null || anonymous.fields.length != 2)
			return false;
		var hasNext = false;
		var next = false;
		for (field in anonymous.fields) {
			var method = switch (field.kind) {
				case FMethod(_): true;
				case _: false;
			};
			if (!method)
				continue;
			switch (field.name) {
				case "hasNext": hasNext = true;
				case "next": next = true;
				case _:
			}
		}
		return hasNext && next;
	}

	static inline function isHaxeArray(classType:ClassType):Bool {
		return classType.pack.length == 0 && classType.module == "Array" && classType.name == "Array";
	}

	static function isArrayIterator(classType:ClassType, parameters:Array<Type>):Bool {
		if (parameters == null || parameters.length != 1 || classType.pack.join(".") != "haxe.iterators")
			return false;
		return classType.module == "haxe.iterators.ArrayIterator" && classType.name == "ArrayIterator"
			|| classType.module == "haxe.iterators.ArrayKeyValueIterator" && classType.name == "ArrayKeyValueIterator";
	}

	static function isPortableFacade(path:String):Bool {
		return path == "reflaxe.std.Option" || path == "reflaxe.std.Result";
	}

	static function isNativeOwned(classType:ClassType, path:String):Bool {
		if (!classType.isExtern)
			return false;
		return isNativeOwnedPath(path) || isNativeOwnedPath(classType.module);
	}

	static function isNativeOwnedPath(path:String):Bool {
		return path == "rust.Vec" || path == "rust.HashMap" || path == "rust.Iter" || path == "rust.PathBuf" || path == "rust.OsString"
			|| path == "rust.Duration" || path == "rust.Instant" || path == "rust.SystemTime" || path == "rust.SystemTimeError"
			|| path == "rust.net.SocketAddr" || path == "rust.net.SocketError";
	}

	static function isNativeHandle(path:String):Bool {
		return path == "rust.net.TcpStream" || path == "rust.net.TcpListener" || path == "rust.net.UdpSocket" || path == "rust.process.CommandChild";
	}

	static inline function isBorrowed(sourceKind:RustSourceValueKind):Bool {
		return sourceKind == SourceBorrowedRef || sourceKind == SourceBorrowedMutRef || sourceKind == SourceBorrowedStr
			|| sourceKind == SourceBorrowedSlice || sourceKind == SourceBorrowedMutSlice;
	}

	static function followType(type:Type):Type {
		#if eval
		return Context.followWithAbstracts(TypeTools.follow(type));
		#else
		return TypeTools.follow(type);
		#end
	}

	static inline function typePath(pack:Array<String>, name:String):String {
		return pack == null || pack.length == 0 ? name : pack.join(".") + "." + name;
	}
}
