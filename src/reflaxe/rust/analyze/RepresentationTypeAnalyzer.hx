package reflaxe.rust.analyze;

import haxe.ds.ObjectMap;
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

private enum RustBorrowTypeMatch {
	BorrowMatchRef(valueType:Type);
	BorrowMatchMutRef(valueType:Type);
	BorrowMatchSlice(valueType:Type);
	BorrowMatchMutSlice(valueType:Type);
	BorrowMatchStr;
}

private enum RustTypeDefinitionVisit {
	VisitEntered(key:String);
	VisitExactCycle;
	VisitChangingCycle;
}

private enum RustStoredBorrowInspection {
	StoredOwned;
	StoredBorrowed;
	StoredUnsupportedRecursive;
}

/**
	Tracks real typed-node and declaration identity during one type walk.

	Why
	- `TypeTools.toString` is display text, not identity: a resolved monomorph or lazy node prints like
	  its child, while a recursive generic can keep changing its printed arguments forever.
	- Early safety checks must terminate without calling an unresolved or changing recursive type owned.

	What
	- Uses stable declaration identity for named Haxe definitions and request-local identity only for
	  anonymous or unresolved typed nodes.
	- Records the complete applied-argument graph for definitions that analysis opens.

	How
	- Re-entering the same definition with the same arguments is an ordinary recursive cycle.
	- Re-entering it with different arguments is parameter-growing recursion and remains unsupported at
	  a borrow-safety boundary.
**/
private class RustTypeTraversalState {
	final objectIds:ObjectMap<{}, Int> = new ObjectMap();
	final activeDefinitions:Map<String, String> = [];
	final activeNodes:ObjectMap<{}, Bool> = new ObjectMap();
	var nextObjectId:Int = 1;

	public function new() {}

	public function enterNode(type:Type):Bool {
		var node:{} = cast type;
		if (activeNodes.exists(node))
			return false;
		activeNodes.set(node, true);
		return true;
	}

	public function leaveNode(type:Type):Void {
		activeNodes.remove(cast type);
	}

	public function enterDefinition(key:String, parameters:Array<Type>):RustTypeDefinitionVisit {
		var signature = typeListFingerprint(parameters, new ObjectMap());
		var previous = activeDefinitions.get(key);
		if (previous != null)
			return previous == signature ? VisitExactCycle : VisitChangingCycle;
		activeDefinitions.set(key, signature);
		return VisitEntered(key);
	}

	public function leaveDefinition(key:String):Void {
		activeDefinitions.remove(key);
	}

	public function typeFingerprint(type:Type):String {
		return fingerprint(type, new ObjectMap());
	}

	public function inventoryIdentity(type:Type):String {
		if (type == null)
			return "null";
		return switch (type) {
			case TMono(monomorphRef): "mono-node:" + objectId(monomorphRef);
			case TLazy(_): "lazy-node:" + objectId(cast type);
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				"anonymous-node:" + objectId(anonymous == null ? cast anonymousRef : cast anonymous);
			case _: typeFingerprint(type);
		};
	}

	public static function namedDefinitionKey(kind:String, module:String, pack:Array<String>, name:String):String {
		return kind + ":" + (module == null ? "" : module) + ":" + (pack == null ? "" : pack.join(".")) + ":" + name;
	}

	function typeListFingerprint(types:Array<Type>, visiting:ObjectMap<{}, Bool>):String {
		if (types == null || types.length == 0)
			return "[]";
		return "[" + [for (type in types) fingerprint(type, visiting)].join(",") + "]";
	}

	function fingerprint(type:Type, visiting:ObjectMap<{}, Bool>):String {
		if (type == null)
			return "null";
		var node:{} = cast type;
		if (visiting.exists(node))
			return "node-cycle:" + objectId(node);
		visiting.set(node, true);
		var result = switch (type) {
			case TMono(monomorphRef):
				var resolved = monomorphRef.get();
				resolved == null ? "mono:" + objectId(monomorphRef) : fingerprint(resolved, visiting);
			case TLazy(resolve):
				fingerprint(resolve(), visiting);
			case TType(typeRef, parameters):
				var definition = typeRef.get();
				(definition == null ? "typedef-ref:" + objectId(typeRef) : namedDefinitionKey("typedef", definition.module, definition.pack, definition.name))
					+ typeListFingerprint(parameters, visiting);
			case TAbstract(abstractRef, parameters):
				var definition = abstractRef.get();
				(definition == null ? "abstract-ref:" + objectId(abstractRef) : namedDefinitionKey("abstract", definition.module, definition.pack, definition.name))
					+ typeListFingerprint(parameters, visiting);
			case TInst(classRef, parameters):
				var definition = classRef.get();
				(definition == null ? "class-ref:" + objectId(classRef) : namedDefinitionKey("class", definition.module, definition.pack, definition.name))
					+ typeListFingerprint(parameters, visiting);
			case TEnum(enumRef, parameters):
				var definition = enumRef.get();
				(definition == null ? "enum-ref:" + objectId(enumRef) : namedDefinitionKey("enum", definition.module, definition.pack, definition.name))
					+ typeListFingerprint(parameters, visiting);
			case TAnonymous(anonymousRef):
				"anonymous:" + objectId(anonymousRef.get() == null ? (cast anonymousRef : Dynamic) : (cast anonymousRef.get() : Dynamic));
			case TFun(arguments, resultType):
				"function:[" + [for (argument in arguments) fingerprint(argument.t, visiting)].join(",") + "]->"
					+ fingerprint(resultType, visiting);
			case TDynamic(inner):
				"dynamic:" + (inner == null ? "none" : fingerprint(inner, visiting));
		};
		visiting.remove(node);
		return result;
	}

	function objectId(value:Dynamic):Int {
		var object:{} = cast value;
		var existing = objectIds.get(object);
		if (existing != null)
			return existing;
		var assigned = nextObjectId++;
		objectIds.set(object, assigned);
		return assigned;
	}
}

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
		- Unwrap aliases, `Null`, and ordinary non-core abstracts, then admit only one-parameter
		  immutable `rust.Ref`.
		- Borrowed strings and slices need different owned conversions, so they stay unmodeled here instead
		  of receiving a misleading decision.
	**/
	public static function immutableReferenceValueType(type:Type):Null<Type> {
		return switch (borrowTypeMatch(type)) {
			case BorrowMatchRef(valueType): valueType;
			case _: null;
		};
	}

	/**
		Names the scoped Rust borrow represented by a Haxe type.

		Why
		- Most ordinary Haxe abstracts disappear in generated Rust and use their backing type. An abstract
		  such as `BorrowedAlias<T>(rust.Ref<T>)` therefore carries the same lifetime restriction as
		  `rust.Ref<T>`.
		- Representation checks and borrow-escape checks must not disagree merely because one follows that
		  transparent wrapper and the other does not.

		What
		- Recognizes the five compiler-supported borrowed carriers through lazy values, typedefs, `Null`,
		  and ordinary non-core abstracts.
		- Stops at every other `@:coreType` abstract because those types have no safe general backing-type
		  rule.

		How
		- `borrowTypeMatch` substitutes applied type parameters while it opens each transparent wrapper,
		  then stops as soon as it reaches a known `rust.*` borrow carrier.
	**/
	@:allow(reflaxe.rust.analyze.BorrowRegionAnalyzer)
	static function borrowOnlyReason(type:Type):Null<String> {
		return switch (borrowTypeMatch(type)) {
			case BorrowMatchRef(_): "rust.Ref<T>";
			case BorrowMatchMutRef(_): "rust.MutRef<T>";
			case BorrowMatchSlice(_): "rust.Slice<T>";
			case BorrowMatchMutSlice(_): "rust.MutSlice<T>";
			case BorrowMatchStr: "rust.Str";
			case null: null;
		};
	}

	/**
		Reports whether a type stores or returns any scoped Rust borrow.

		Why / What / How
		- Borrow-region validation needs the same transparent-abstract rule as representation analysis,
		  including when the borrow is nested in a function, record, container parameter, or ordinary
		  abstract backing type.
		- This shared walk prevents a wrapper from looking owned to the escape checker while lowering to a
		  Rust reference later.
		- Unknown core abstracts remain opaque; their visible type parameters are still inspected
		  conservatively.
	**/
	@:allow(reflaxe.rust.analyze.BorrowRegionAnalyzer)
	static function containsBorrowOnlyType(type:Type):Bool {
		return containsBorrowOnlyTypeRecursive(type, new RustTypeTraversalState());
	}

	/**
		Creates one identity function for a complete representation inventory walk.

		Why / What / How
		- Request-local anonymous, monomorph, and lazy identities are meaningful only when every node in the
		  same walk shares the allocator that issued them.
		- A transparent wrapper deliberately has a different inventory key from its resolved child so the
		  child still contributes its structural type arguments and fields.
		- Named types retain a structural declaration-plus-arguments key; display text is never used.
	**/
	@:allow(reflaxe.rust.analyze.RepresentationDecisionAnalyzer)
	@:allow(reflaxe.rust.RustCompiler)
	static function traversalIdentityFactory():Type->String {
		var state = new RustTypeTraversalState();
		return type -> state.inventoryIdentity(type);
	}

	/**
		Explains why a runtime anonymous-object field cannot expose a scoped Rust borrow.

		Why
		- Anonymous storage owns a concrete runtime value and reads it back by its exact stored Rust type.
		- Turning a borrowed value into an owned value on write but still reading the declared field as a
		  Rust reference makes the runtime downcast fail. Keeping the short-lived reference would instead
		  let a borrow escape.

		What
		- Rejects `rust.Ref<T>`, `rust.MutRef<T>`, `rust.Slice<T>`, `rust.MutSlice<T>`, and `rust.Str`
		  fields, including nullable and ordinary-abstract wrappers, before Rust construction.

		How
		- Reuse the same transparent-wrapper-aware reference recognizer as Dynamic materialization and
		  borrow-region checking.
		- Full support requires a future stored-versus-exposed field contract with a guard-bound read
		  lifetime; this compiler does not pretend that an owned clone is still a scoped reference.
	**/
	public static function anonymousBorrowedFieldRejectionReason(type:Type):Null<String> {
		if (type == null)
			return null;
		return switch (inspectStoredBorrow(type, new RustTypeTraversalState())) {
			case StoredOwned:
				null;
			case StoredBorrowed:
				"runtime anonymous objects cannot safely expose this scoped Rust borrow field: storing the reference would let a "
				+ "short-lived borrow escape, while storing an owned value would no longer match the declared borrowed type. "
				+ "Store an owned value instead.";
			case StoredUnsupportedRecursive:
				"runtime anonymous objects cannot safely prove the stored Rust type for this parameter-changing recursive field. "
				+ "Use a finite owned field type instead.";
		};
	}

	/**
		Finds an unsupported borrowed field anywhere in a runtime anonymous-record shape.

		Why
		- A record literal may omit an `@:optional` field, so checking only the values physically written
		  by that literal does not inspect the complete declared shape.
		- Once the record is converted to `Dynamic`, runtime-name reflection no longer carries the field
		  declaration needed to catch a later mismatched write.

		What
		- Returns the first declared scoped-borrow field on a real runtime anonymous record, including
		  omitted optional fields and ordinary Haxe abstracts around either the field or complete record.
		- Iterator-shaped anonymous values remain iterator carriers rather than runtime record storage.

		How
		- Follow typedef aliases, applied type parameters, outer `Null`, and ordinary non-core abstracts,
		  then inspect a name-sorted copy of every declared field through the same reference recognizer
		  used by Dynamic materialization.
		- Callers choose the useful source location: the exact stored value for a direct write, or the
		  anonymous value/type materialization when no field value exists yet.
	**/
	public static function anonymousBorrowedField(type:Type):Null<ClassField> {
		if (type == null)
			return null;
		var anonymous = transparentAnonymousBacking(type, new RustTypeTraversalState());
		if (anonymous == null || anonymous.fields == null || isIteratorAnonymous(anonymous))
			return null;
		var fields = anonymous.fields.copy();
		fields.sort((left, right) -> {
			if (left.name < right.name)
				-1;
			else if (left.name > right.name)
				1;
			else
				0;
		});
		for (field in fields)
			if (field != null && anonymousBorrowedFieldRejectionReason(field.type) != null)
				return field;
		return null;
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

	static function sourceKind(type:Type, nullableStringCompat:Bool, classHasSubclasses:Null<ClassType->Bool>,
			?state:RustTypeTraversalState):Null<RustSourceValueKind> {
		if (state == null)
			state = new RustTypeTraversalState();
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
				return switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("abstract", abstractType.module, abstractType.pack, abstractType.name), parameters)) {
					case VisitEntered(key):
						var underlying = abstractType.type;
						if (abstractType.params != null && abstractType.params.length > 0 && parameters.length == abstractType.params.length)
							underlying = TypeTools.applyTypeParameters(underlying, abstractType.params, parameters);
						var result = sourceKind(unwrapAliasesAndNull(underlying).type, nullableStringCompat, classHasSubclasses, state);
						state.leaveDefinition(key);
						result;
					case VisitExactCycle | VisitChangingCycle:
						null;
				};
			case _:
		}

		return switch (type) {
			case TFun(_, _):
				SourceFunctionValue;
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				if (anonymous == null) null else if (isIteratorAnonymous(anonymous)) SourceIterator else if (isRuntimeAnonymous(anonymous)) SourceAnonymousObject else SourceCoreHandle;
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
				resolved == null ? null : sourceKind(unwrapAliasesAndNull(resolved).type, nullableStringCompat, classHasSubclasses, state);
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

	/**
		Finds a scoped Rust borrow behind representation-transparent Haxe wrappers.

		Why / What / How
		- Rust type emission follows arbitrarily deep acyclic typedef and ordinary-abstract wrappers, so
		  stopping analysis at a fixed depth would let the two stages disagree about whether a value borrows.
		- Recognize the five compiler-owned borrow carriers before opening ordinary wrappers, and preserve
		  the applied type arguments used by the concrete source program.
		- Resolve monomorph/lazy wrappers before comparing real declaration identity and applied arguments.
		  Human-readable type text is used only in diagnostics, never as cycle identity.
	**/
	static function borrowTypeMatch(type:Type):Null<RustBorrowTypeMatch> {
		return borrowTypeMatchRecursive(type, new RustTypeTraversalState());
	}

	static function borrowTypeMatchRecursive(type:Type, state:RustTypeTraversalState):Null<RustBorrowTypeMatch> {
		if (type == null)
			return null;
		return switch (type) {
			case TMono(monomorphRef):
				if (!state.enterNode(type))
					return null;
				var resolved = monomorphRef.get();
				var result = resolved == null ? null : borrowTypeMatchRecursive(resolved, state);
				state.leaveNode(type);
				result;
			case TLazy(resolve):
				if (!state.enterNode(type))
					return null;
				var result = borrowTypeMatchRecursive(resolve(), state);
				state.leaveNode(type);
				result;
			case TType(typeRef, parameters):
				var typedefType = typeRef.get();
				if (typedefType == null) {
					null;
				} else {
					switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("typedef", typedefType.module, typedefType.pack, typedefType.name), parameters)) {
						case VisitEntered(key):
							var underlying = typedefType.type;
							if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
								underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
							var result = borrowTypeMatchRecursive(underlying, state);
							state.leaveDefinition(key);
							result;
						case VisitExactCycle | VisitChangingCycle:
							null;
					}
				}
			case TAbstract(abstractRef, parameters):
				var abstractType = abstractRef.get();
				if (abstractType == null) {
					null;
				} else {
					var path = typePath(abstractType.pack, abstractType.name);
					switch (path) {
						case "rust.Ref" if (parameters.length == 1):
							BorrowMatchRef(parameters[0]);
						case "rust.MutRef" if (parameters.length == 1):
							BorrowMatchMutRef(parameters[0]);
						case "rust.Slice" if (parameters.length == 1):
							BorrowMatchSlice(parameters[0]);
						case "rust.MutSlice" if (parameters.length == 1):
							BorrowMatchMutSlice(parameters[0]);
						case "rust.Str" if (parameters.length == 0):
							BorrowMatchStr;
						case _ if (abstractType.module == "StdTypes" && abstractType.name == "Null" && parameters.length == 1):
							borrowTypeMatchRecursive(parameters[0], state);
						case _ if (abstractType.meta != null && abstractType.meta.has(":coreType")):
							null;
						case _:
							switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("abstract", abstractType.module, abstractType.pack, abstractType.name), parameters)) {
								case VisitEntered(key):
									var underlying = abstractType.type;
									if (abstractType.params != null
										&& abstractType.params.length > 0
										&& parameters.length == abstractType.params.length)
										underlying = TypeTools.applyTypeParameters(underlying, abstractType.params, parameters);
									var result = borrowTypeMatchRecursive(underlying, state);
									state.leaveDefinition(key);
									result;
								case VisitExactCycle | VisitChangingCycle:
									null;
							}
					}
				}
			case _:
				null;
		};
	}

	static function inspectStoredBorrow(type:Type, state:RustTypeTraversalState):RustStoredBorrowInspection {
		if (type == null)
			return StoredOwned;
		return switch (type) {
			case TMono(monomorphRef):
				if (!state.enterNode(type))
					return StoredUnsupportedRecursive;
				var resolved = monomorphRef.get();
				var result = resolved == null ? StoredUnsupportedRecursive : inspectStoredBorrow(resolved, state);
				state.leaveNode(type);
				result;
			case TLazy(resolve):
				if (!state.enterNode(type))
					return StoredUnsupportedRecursive;
				var result = inspectStoredBorrow(resolve(), state);
				state.leaveNode(type);
				result;
			case TType(typeRef, parameters):
				var typedefType = typeRef.get();
				if (typedefType == null) {
					StoredUnsupportedRecursive;
				} else {
					switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("typedef", typedefType.module, typedefType.pack, typedefType.name), parameters)) {
						case VisitEntered(key):
							var underlying = typedefType.type;
							if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
								underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
							var result = inspectStoredBorrow(underlying, state);
							state.leaveDefinition(key);
							result;
						case VisitExactCycle:
							StoredOwned;
						case VisitChangingCycle:
							StoredUnsupportedRecursive;
					}
				}
			case TAbstract(abstractRef, parameters):
				var abstractType = abstractRef.get();
				if (abstractType == null) {
					StoredUnsupportedRecursive;
				} else {
					var path = typePath(abstractType.pack, abstractType.name);
					switch (path) {
						case "rust.Ref" | "rust.MutRef" | "rust.Slice" | "rust.MutSlice" if (parameters.length == 1):
							StoredBorrowed;
						case "rust.Str" if (parameters.length == 0):
							StoredBorrowed;
						case _ if (abstractType.module == "StdTypes" && abstractType.name == "Null" && parameters.length == 1):
							inspectStoredBorrow(parameters[0], state);
						case _ if (abstractType.meta != null && abstractType.meta.has(":coreType")):
							StoredOwned;
						case _:
							switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("abstract", abstractType.module, abstractType.pack, abstractType.name), parameters)) {
								case VisitEntered(key):
									var underlying = abstractType.type;
									if (abstractType.params != null
										&& abstractType.params.length > 0
										&& parameters.length == abstractType.params.length)
										underlying = TypeTools.applyTypeParameters(underlying, abstractType.params, parameters);
									var result = inspectStoredBorrow(underlying, state);
									state.leaveDefinition(key);
									result;
								case VisitExactCycle:
									StoredOwned;
								case VisitChangingCycle:
									StoredUnsupportedRecursive;
							}
					}
				}
			case TInst(classRef, parameters):
				var classType = classRef.get();
				if (classType != null && (classType.name == "Class" || classType.name == "Enum")
					&& (classType.module == "StdTypes" || classType.pack.length == 0))
					StoredOwned;
				else
					inspectStoredBorrowList(parameters, state);
			case TEnum(_, parameters):
				inspectStoredBorrowList(parameters, state);
			case TFun(arguments, resultType):
				var result = inspectStoredBorrow(resultType, state);
				if (result == StoredOwned)
					result = inspectStoredBorrowList([for (argument in arguments) argument.t], state);
				result;
			case TAnonymous(_):
				// A nested runtime record is stored as HxRef<Anon>; its field types are not retained in this slot.
				StoredOwned;
			case TDynamic(_):
				StoredOwned;
		};
	}

	static function inspectStoredBorrowList(types:Array<Type>, state:RustTypeTraversalState):RustStoredBorrowInspection {
		if (types == null)
			return StoredOwned;
		var unsupported = false;
		for (type in types) {
			var result = inspectStoredBorrow(type, state);
			if (result == StoredBorrowed)
				return StoredBorrowed;
			if (result == StoredUnsupportedRecursive)
				unsupported = true;
		}
		return unsupported ? StoredUnsupportedRecursive : StoredOwned;
	}

	static function containsBorrowOnlyTypeRecursive(type:Type, state:RustTypeTraversalState):Bool {
		if (type == null)
			return false;
		if (borrowTypeMatch(type) != null)
			return true;
		return switch (type) {
			case TMono(monomorphRef):
				if (!state.enterNode(type))
					return true;
				var resolved = monomorphRef.get();
				var result = resolved == null || containsBorrowOnlyTypeRecursive(resolved, state);
				state.leaveNode(type);
				result;
			case TLazy(resolve):
				if (!state.enterNode(type))
					return true;
				var result = containsBorrowOnlyTypeRecursive(resolve(), state);
				state.leaveNode(type);
				result;
			case TType(typeRef, parameters):
				var typedefType = typeRef.get();
				if (typedefType == null) {
					true;
				} else {
					switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("typedef", typedefType.module, typedefType.pack, typedefType.name), parameters)) {
						case VisitEntered(key):
							var underlying = typedefType.type;
							if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
								underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
							var result = containsBorrowOnlyTypeRecursive(underlying, state);
							state.leaveDefinition(key);
							result;
						case VisitExactCycle:
							false;
						case VisitChangingCycle:
							true;
					}
				}
			case TAbstract(abstractRef, parameters):
				var abstractType = abstractRef.get();
				if (abstractType == null) {
					true;
				} else if (abstractType.module == "StdTypes" && abstractType.name == "Null" && parameters.length == 1) {
					containsBorrowOnlyTypeRecursive(parameters[0], state);
				} else if (abstractType.meta != null && abstractType.meta.has(":coreType")) {
					containsBorrowOnlyTypeList(parameters, state);
				} else {
					switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("abstract", abstractType.module, abstractType.pack, abstractType.name), parameters)) {
						case VisitEntered(key):
							var underlying = abstractType.type;
							if (abstractType.params != null
								&& abstractType.params.length > 0
								&& parameters.length == abstractType.params.length)
								underlying = TypeTools.applyTypeParameters(underlying, abstractType.params, parameters);
							var result = containsBorrowOnlyTypeRecursive(underlying, state);
							state.leaveDefinition(key);
							result;
						case VisitExactCycle:
							false;
						case VisitChangingCycle:
							true;
					}
				}
			case TInst(_, parameters) | TEnum(_, parameters):
				containsBorrowOnlyTypeList(parameters, state);
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				if (anonymous == null) {
					true;
				} else if (!isRuntimeAnonymous(anonymous)) {
					false;
				} else {
					switch (state.enterDefinition("anonymous:" + state.typeFingerprint(type), [])) {
						case VisitEntered(key):
							var found = false;
							if (anonymous.fields != null)
								for (field in anonymous.fields)
									if (field != null && containsBorrowOnlyTypeRecursive(field.type, state)) {
										found = true;
										break;
									}
							state.leaveDefinition(key);
							found;
						case VisitExactCycle:
							false;
						case VisitChangingCycle:
							true;
					}
				}
			case TFun(arguments, result):
				var found = containsBorrowOnlyTypeRecursive(result, state);
				if (!found && arguments != null)
					for (argument in arguments)
						if (argument != null && containsBorrowOnlyTypeRecursive(argument.t, state)) {
							found = true;
							break;
						}
				found;
			case TDynamic(inner):
				inner != null && containsBorrowOnlyTypeRecursive(inner, state);
		};
	}

	static function containsBorrowOnlyTypeList(types:Array<Type>, state:RustTypeTraversalState):Bool {
		if (types == null)
			return false;
		for (type in types)
			if (containsBorrowOnlyTypeRecursive(type, state))
				return true;
		return false;
	}

	/**
		Finds the runtime anonymous-record shape behind transparent Haxe wrappers.

		Why / What / How
		- Rust lowering opens ordinary abstracts, so the early safety check must not stop at an abstract
		  wrapped around the complete record while later emission reaches its borrowed fields.
		- Resolve lazy and typedef nodes, remove outer `Null`, and open ordinary non-core abstracts with
		  applied type arguments. Exact compiler-owned core abstracts remain opaque.
		- Track real declaration identity plus applied arguments so recursive owned types terminate without
		  confusing a monomorph/lazy display string with a cycle.
	**/
	static function transparentAnonymousBacking(type:Type, state:RustTypeTraversalState):Null<AnonType> {
		if (type == null)
			return null;
		return switch (type) {
			case TMono(monomorphRef):
				if (!state.enterNode(type))
					return null;
				var resolved = monomorphRef.get();
				var result = resolved == null ? null : transparentAnonymousBacking(resolved, state);
				state.leaveNode(type);
				result;
			case TLazy(resolve):
				if (!state.enterNode(type))
					return null;
				var result = transparentAnonymousBacking(resolve(), state);
				state.leaveNode(type);
				result;
			case TType(typeRef, parameters):
				var typedefType = typeRef.get();
				if (typedefType == null) {
					null;
				} else {
					switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("typedef", typedefType.module, typedefType.pack, typedefType.name), parameters)) {
						case VisitEntered(key):
							var underlying = typedefType.type;
							if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
								underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
							var result = transparentAnonymousBacking(underlying, state);
							state.leaveDefinition(key);
							result;
						case VisitExactCycle | VisitChangingCycle:
							null;
					}
				}
			case TAbstract(abstractRef, parameters):
				var abstractType = abstractRef.get();
				if (abstractType == null) {
					null;
				} else if (abstractType.module == "StdTypes" && abstractType.name == "Null" && parameters.length == 1) {
					transparentAnonymousBacking(parameters[0], state);
				} else if (abstractType.meta != null && abstractType.meta.has(":coreType")) {
					null;
				} else {
					switch (state.enterDefinition(RustTypeTraversalState.namedDefinitionKey("abstract", abstractType.module, abstractType.pack, abstractType.name), parameters)) {
						case VisitEntered(key):
							var underlying = abstractType.type;
							if (abstractType.params != null
								&& abstractType.params.length > 0
								&& parameters.length == abstractType.params.length)
								underlying = TypeTools.applyTypeParameters(underlying, abstractType.params, parameters);
							var result = transparentAnonymousBacking(underlying, state);
							state.leaveDefinition(key);
							result;
						case VisitExactCycle | VisitChangingCycle:
							null;
					}
				}
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				anonymous != null && isRuntimeAnonymous(anonymous) ? anonymous : null;
			case _:
				null;
		};
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

	/**
		Distinguishes runtime record storage from Haxe's anonymous-looking type namespaces.

		Why / What / How
		- Haxe represents class, enum, and abstract static fields with `TAnonymous`, but generated Rust
		  treats those values as type handles rather than `hxrt::anon::Anon` records.
		- Scanning a static method signature as a stored record field can reject valid programs before the
		  diagnostic that actually owns the source construct.
		- Keep closed, open, const, and extended structures as runtime records; exclude only the three
		  explicit static-namespace statuses.
	**/
	static function isRuntimeAnonymous(anonymous:AnonType):Bool {
		if (anonymous == null)
			return false;
		return switch (anonymous.status) {
			case AClassStatics(_) | AEnumStatics(_) | AAbstractStatics(_): false;
			case AClosed | AOpened | AConst | AExtend(_): true;
		};
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
