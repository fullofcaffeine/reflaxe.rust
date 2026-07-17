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
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSurfaceFact;

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
					if (abstractType.module == "StdTypes" && (abstractType.name == "Class" || abstractType.name == "Enum"))
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
						case KTypeParameter(_): null;
						case _ if (isHaxeArray(classType)): SourceArray;
						case _ if (isArrayIterator(classType, parameters)): SourceIterator;
						case _ if (path == "haxe.io.Bytes"): SourceBytesReference;
						case _ if (isNativeHandle(path)): SourceNativeHandle;
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
