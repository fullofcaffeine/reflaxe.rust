package reflaxe.rust.analyze;

import reflaxe.rust.RustSourcePath;

/**
	Module anchor for the representation-plan types.

	Why / What / How
	- Haxe multi-type modules need a primary type so callers can address the sibling decision types as
	  `RepresentationPlan.*` without creating one file per small closed vocabulary.
	- This class has no instances or behavior; use the validated factories below.
**/
class RepresentationPlan {}

// BEGIN GENERATED RUST REPRESENTATION VOCABULARIES
/**
	The normalized typed-Haxe value family presented to the representation planner.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustSourceValueKind(String) to String {
	var SourceScalar = "scalar";
	var SourceEnumValue = "enum_value";
	var SourceClassReference = "class_reference";
	var SourcePolymorphicReference = "polymorphic_reference";
	var SourceBorrowedRef = "borrowed_ref";
	var SourceBorrowedMutRef = "borrowed_mut_ref";
	var SourceBorrowedStr = "borrowed_str";
	var SourceBorrowedSlice = "borrowed_slice";
	var SourceBorrowedMutSlice = "borrowed_mut_slice";
	var SourceNativeOwned = "native_owned";
	var SourceNativeHandle = "native_handle";
	var SourceDynamic = "dynamic";
	var SourceString = "string";
	var SourceArray = "array";
	var SourceAnonymousObject = "anonymous_object";
	var SourceFunctionValue = "function_value";
	var SourceIterator = "iterator";
	var SourcePortableFacade = "portable_facade";
	var SourceCoreHandle = "core_handle";
	var SourceBytesReference = "bytes_reference";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustSourceValueKind {
		return switch (value) {
			case "scalar": SourceScalar;
			case "enum_value": SourceEnumValue;
			case "class_reference": SourceClassReference;
			case "polymorphic_reference": SourcePolymorphicReference;
			case "borrowed_ref": SourceBorrowedRef;
			case "borrowed_mut_ref": SourceBorrowedMutRef;
			case "borrowed_str": SourceBorrowedStr;
			case "borrowed_slice": SourceBorrowedSlice;
			case "borrowed_mut_slice": SourceBorrowedMutSlice;
			case "native_owned": SourceNativeOwned;
			case "native_handle": SourceNativeHandle;
			case "dynamic": SourceDynamic;
			case "string": SourceString;
			case "array": SourceArray;
			case "anonymous_object": SourceAnonymousObject;
			case "function_value": SourceFunctionValue;
			case "iterator": SourceIterator;
			case "portable_facade": SourcePortableFacade;
			case "core_handle": SourceCoreHandle;
			case "bytes_reference": SourceBytesReference;
			case _: throw 'Unsupported RustSourceValueKind id: $value';
		};
	}
}

/**
	Whether observable source semantics require stable reference identity.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustIdentityFact(String) to String {
	var IdentityNone = "none";
	var IdentityStable = "stable";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustIdentityFact {
		return switch (value) {
			case "none": IdentityNone;
			case "stable": IdentityStable;
			case _: throw 'Unsupported RustIdentityFact id: $value';
		};
	}
}

/**
	How mutation is observable through the typed source value.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustMutationFact(String) to String {
	var MutationImmutable = "immutable";
	var MutationOwned = "owned";
	var MutationExclusiveBorrow = "exclusive_borrow";
	var MutationShared = "shared";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustMutationFact {
		return switch (value) {
			case "immutable": MutationImmutable;
			case "owned": MutationOwned;
			case "exclusive_borrow": MutationExclusiveBorrow;
			case "shared": MutationShared;
			case _: throw 'Unsupported RustMutationFact id: $value';
		};
	}
}

/**
	Whether a value may outlive its immediate lexical region.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustEscapeFact(String) to String {
	var EscapeLocal = "local";
	var EscapeMay = "may_escape";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustEscapeFact {
		return switch (value) {
			case "local": EscapeLocal;
			case "may_escape": EscapeMay;
			case _: throw 'Unsupported RustEscapeFact id: $value';
		};
	}
}

/**
	The source-language authority that admits the representation.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustSurfaceFact(String) to String {
	var SurfacePortableHaxe = "portable_haxe";
	var SurfacePortableFacade = "portable_facade";
	var SurfaceRustNative = "rust_native";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustSurfaceFact {
		return switch (value) {
			case "portable_haxe": SurfacePortableHaxe;
			case "portable_facade": SurfacePortableFacade;
			case "rust_native": SurfaceRustNative;
			case _: throw 'Unsupported RustSurfaceFact id: $value';
		};
	}
}

/**
	Whether the typed source value admits null.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustNullabilityFact(String) to String {
	var NonNullable = "non_nullable";
	var Nullable = "nullable";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustNullabilityFact {
		return switch (value) {
			case "non_nullable": NonNullable;
			case "nullable": Nullable;
			case _: throw 'Unsupported RustNullabilityFact id: $value';
		};
	}
}

/**
	The contextual boundary at which Rust trait or lifetime requirements apply.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustBoundaryKind(String) to String {
	var BoundaryLocal = "local";
	var BoundaryThread = "thread";
	var BoundaryTask = "task";
	var BoundaryDynamic = "dynamic";
	var BoundaryStaticStorage = "static_storage";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustBoundaryKind {
		return switch (value) {
			case "local": BoundaryLocal;
			case "thread": BoundaryThread;
			case "task": BoundaryTask;
			case "dynamic": BoundaryDynamic;
			case "static_storage": BoundaryStaticStorage;
			case _: throw 'Unsupported RustBoundaryKind id: $value';
		};
	}
}

/**
	The closed Rust storage shape selected before AST emission.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustRepresentationKind(String) to String {
	var RepresentationCopyValue = "copy_value";
	var RepresentationOwnedValue = "owned_value";
	var RepresentationSharedIdentity = "shared_identity";
	var RepresentationSharedTraitObject = "shared_trait_object";
	var RepresentationBorrowedToken = "borrowed_token";
	var RepresentationNativeHandle = "native_handle";
	var RepresentationDynamicPayload = "dynamic_payload";
	var RepresentationRuntimeString = "runtime_string";
	var RepresentationRuntimeArray = "runtime_array";
	var RepresentationRuntimeAnonymousObject = "runtime_anonymous_object";
	var RepresentationSharedFunction = "shared_function";
	var RepresentationRuntimeIterator = "runtime_iterator";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustRepresentationKind {
		return switch (value) {
			case "copy_value": RepresentationCopyValue;
			case "owned_value": RepresentationOwnedValue;
			case "shared_identity": RepresentationSharedIdentity;
			case "shared_trait_object": RepresentationSharedTraitObject;
			case "borrowed_token": RepresentationBorrowedToken;
			case "native_handle": RepresentationNativeHandle;
			case "dynamic_payload": RepresentationDynamicPayload;
			case "runtime_string": RepresentationRuntimeString;
			case "runtime_array": RepresentationRuntimeArray;
			case "runtime_anonymous_object": RepresentationRuntimeAnonymousObject;
			case "shared_function": RepresentationSharedFunction;
			case "runtime_iterator": RepresentationRuntimeIterator;
			case _: throw 'Unsupported RustRepresentationKind id: $value';
		};
	}
}

/**
	How the selected Rust representation preserves source-level nullability.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustNullEncoding(String) to String {
	var NullNotAdmitted = "not_admitted";
	var NullIntrinsic = "intrinsic";
	var NullOuterOption = "outer_option";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustNullEncoding {
		return switch (value) {
			case "not_admitted": NullNotAdmitted;
			case "intrinsic": NullIntrinsic;
			case "outer_option": NullOuterOption;
			case _: throw 'Unsupported RustNullEncoding id: $value';
		};
	}
}

/**
	The ownership behavior of the selected Rust representation.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustOwnershipPolicy(String) to String {
	var OwnershipCopy = "copy";
	var OwnershipMove = "move";
	var OwnershipShared = "shared";
	var OwnershipBorrowed = "borrowed";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustOwnershipPolicy {
		return switch (value) {
			case "copy": OwnershipCopy;
			case "move": OwnershipMove;
			case "shared": OwnershipShared;
			case "borrowed": OwnershipBorrowed;
			case _: throw 'Unsupported RustOwnershipPolicy id: $value';
		};
	}
}

/**
	How lowering preserves source-level reuse without blanket Clone bounds.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustReusePolicy(String) to String {
	var ReuseCopy = "copy";
	var ReuseMoveOnce = "move_once";
	var ReuseCloneWhenNeeded = "clone_when_needed";
	var ReuseBorrow = "borrow";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustReusePolicy {
		return switch (value) {
			case "copy": ReuseCopy;
			case "move_once": ReuseMoveOnce;
			case "clone_when_needed": ReuseCloneWhenNeeded;
			case "borrow": ReuseBorrow;
			case _: throw 'Unsupported RustReusePolicy id: $value';
		};
	}
}

/**
	The stable reason why a Rust storage shape was selected.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustRepresentationReason(String) to String {
	var ReasonHaxeScalar = "haxe_scalar_value";
	var ReasonHaxeEnum = "haxe_enum_value";
	var ReasonHaxeClassIdentity = "haxe_class_identity";
	var ReasonHaxePolymorphicIdentity = "haxe_polymorphic_identity";
	var ReasonRustBorrowSurface = "rust_borrow_surface";
	var ReasonRustOwnedSurface = "rust_owned_surface";
	var ReasonRustNativeHandle = "rust_native_handle";
	var ReasonHaxeDynamicPayload = "haxe_dynamic_payload";
	var ReasonHaxeStringContract = "haxe_string_contract";
	var ReasonHaxeArrayContract = "haxe_array_contract";
	var ReasonHaxeAnonymousObject = "haxe_anonymous_object";
	var ReasonHaxeFunctionValue = "haxe_function_value";
	var ReasonHaxeIteratorContract = "haxe_iterator_contract";
	var ReasonAdmittedPortableFacade = "admitted_portable_facade";
	var ReasonHaxeCoreHandle = "haxe_core_handle";
	var ReasonHaxeBytesIdentity = "haxe_bytes_identity";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustRepresentationReason {
		return switch (value) {
			case "haxe_scalar_value": ReasonHaxeScalar;
			case "haxe_enum_value": ReasonHaxeEnum;
			case "haxe_class_identity": ReasonHaxeClassIdentity;
			case "haxe_polymorphic_identity": ReasonHaxePolymorphicIdentity;
			case "rust_borrow_surface": ReasonRustBorrowSurface;
			case "rust_owned_surface": ReasonRustOwnedSurface;
			case "rust_native_handle": ReasonRustNativeHandle;
			case "haxe_dynamic_payload": ReasonHaxeDynamicPayload;
			case "haxe_string_contract": ReasonHaxeStringContract;
			case "haxe_array_contract": ReasonHaxeArrayContract;
			case "haxe_anonymous_object": ReasonHaxeAnonymousObject;
			case "haxe_function_value": ReasonHaxeFunctionValue;
			case "haxe_iterator_contract": ReasonHaxeIteratorContract;
			case "admitted_portable_facade": ReasonAdmittedPortableFacade;
			case "haxe_core_handle": ReasonHaxeCoreHandle;
			case "haxe_bytes_identity": ReasonHaxeBytesIdentity;
			case _: throw 'Unsupported RustRepresentationReason id: $value';
		};
	}
}

/**
	The semantic reason a decision requires hxrt rather than ordinary Rust alone.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustRuntimeRequirementKind(String) to String {
	var RuntimeObjectIdentity = "object_identity";
	var RuntimeReferenceMutation = "reference_mutation";
	var RuntimeDynamic = "dynamic";
	var RuntimeReflection = "reflection";
	var RuntimeAnonymousObject = "anonymous_object";
	var RuntimeException = "exception";
	var RuntimeNullableCompat = "nullable_compat";
	var RuntimeSharedClosureCell = "shared_closure_cell";
	var RuntimePlatformAbstraction = "platform_abstraction";
	var RuntimeHaxeArraySemantics = "haxe_array_semantics";
	var RuntimeHaxeStringSemantics = "haxe_string_semantics";
	var RuntimeFunctionValue = "function_value";
	var RuntimeIteratorSemantics = "iterator_semantics";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustRuntimeRequirementKind {
		return switch (value) {
			case "object_identity": RuntimeObjectIdentity;
			case "reference_mutation": RuntimeReferenceMutation;
			case "dynamic": RuntimeDynamic;
			case "reflection": RuntimeReflection;
			case "anonymous_object": RuntimeAnonymousObject;
			case "exception": RuntimeException;
			case "nullable_compat": RuntimeNullableCompat;
			case "shared_closure_cell": RuntimeSharedClosureCell;
			case "platform_abstraction": RuntimePlatformAbstraction;
			case "haxe_array_semantics": RuntimeHaxeArraySemantics;
			case "haxe_string_semantics": RuntimeHaxeStringSemantics;
			case "function_value": RuntimeFunctionValue;
			case "iterator_semantics": RuntimeIteratorSemantics;
			case _: throw 'Unsupported RustRuntimeRequirementKind id: $value';
		};
	}
}

/**
	The contextual Rust trait or lifetime requirement introduced at a real boundary.

	Why / What / How
	- Serialized planner values are closed and generated from `rust-representation-policy.json`.
	- Use typed values internally and `fromId` only when rebuilding untrusted report data.
**/
enum abstract RustRequiredBound(String) to String {
	var BoundClone = "clone";
	var BoundSend = "send";
	var BoundSync = "sync";
	var BoundStatic = "static";

	public inline function id():String {
		return this;
	}

	public static function fromId(value:String):RustRequiredBound {
		return switch (value) {
			case "clone": BoundClone;
			case "send": BoundSend;
			case "sync": BoundSync;
			case "static": BoundStatic;
			case _: throw 'Unsupported RustRequiredBound id: $value';
		};
	}
}

// END GENERATED RUST REPRESENTATION VOCABULARIES

/**
	An exact, source-private Haxe origin for one representation decision.

	Why
	- A representation report without a source location cannot explain which Haxe value selected a
	  runtime or ownership contract.
	- Raw Haxe positions may contain absolute paths, which would leak checkout-specific information.

	What
	- Stores a canonical relative source file, exact half-open byte range, and resolved module path.

	How
	- Construct through `at`; path and byte validation happens immediately.
	- The compiler adapter will resolve Haxe `Position` values through the same source-path authority.
**/
class RustDecisionOrigin {
	public final sourceFile:String;
	public final startByte:Int;
	public final endByte:Int;
	public final modulePath:String;

	private function new(sourceFile:String, startByte:Int, endByte:Int, modulePath:String) {
		this.sourceFile = sourceFile;
		this.startByte = startByte;
		this.endByte = endByte;
		this.modulePath = modulePath;
	}

	/**
		Builds one path-private, half-open source origin.

		Why / What / How
		- Reports must reject local absolute paths, traversal, malformed module names, and reversed spans
		  at construction time rather than leaking or failing during serialization.
		- Pass a canonical project-relative file, UTF-8 byte offsets, and the owning Haxe module path.
	**/
	public static function at(sourceFile:String, startByte:Int, endByte:Int, modulePath:String):RustDecisionOrigin {
		var stableFile = RustSourcePath.requireRelativePath(sourceFile, "Representation source file");
		if (startByte < 0 || endByte < startByte)
			throw "Representation source origin requires a valid half-open byte range";
		if (modulePath == null || !~/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$/.match(modulePath))
			throw 'Representation source origin has an invalid Haxe module path: $modulePath';
		return new RustDecisionOrigin(stableFile, startByte, endByte, modulePath);
	}
}

/**
	Validated typed facts supplied to the representation planner.

	Why
	- Type names alone do not say whether identity, alias-visible mutation, escape, or a real crossing
	  must be preserved.
	- Passing loose booleans would admit contradictory states such as an escaping lexical borrow.

	What
	- Captures the normalized source family plus identity, mutation, escape, surface, nullability, and
	  crossing facts available before Rust AST emission.

	How
	- `of` validates the complete combination and owns only immutable scalar/enum values.
	- Later compiler extraction may grow, but every new state must enter this closed validation point.
**/
class RustRepresentationFacts {
	public final subjectId:String;
	public final sourceKind:RustSourceValueKind;
	public final identity:RustIdentityFact;
	public final mutation:RustMutationFact;
	public final escape:RustEscapeFact;
	public final surface:RustSurfaceFact;
	public final nullability:RustNullabilityFact;
	public final boundary:RustBoundaryKind;
	public final origin:RustDecisionOrigin;

	private function new(subjectId:String, sourceKind:RustSourceValueKind, identity:RustIdentityFact, mutation:RustMutationFact,
			escape:RustEscapeFact, surface:RustSurfaceFact, nullability:RustNullabilityFact, boundary:RustBoundaryKind,
			origin:RustDecisionOrigin) {
		this.subjectId = subjectId;
		this.sourceKind = sourceKind;
		this.identity = identity;
		this.mutation = mutation;
		this.escape = escape;
		this.surface = surface;
		this.nullability = nullability;
		this.boundary = boundary;
		this.origin = origin;
	}

	/**
		Validates the normalized facts for one typed value at one real boundary.

		Why / What / How
		- Loose fact combinations can describe impossible states, such as an escaping lexical borrow or
		  an owned native handle with Haxe alias identity.
		- Supply facts extracted from typed Haxe once; this factory rejects contradictions before the
		  pure planner selects Rust storage.
	**/
	public static function of(subjectId:String, sourceKind:RustSourceValueKind, identity:RustIdentityFact, mutation:RustMutationFact,
			escape:RustEscapeFact, surface:RustSurfaceFact, nullability:RustNullabilityFact, boundary:RustBoundaryKind,
			origin:RustDecisionOrigin):RustRepresentationFacts {
		if (subjectId == null || !~/^[^\x00-\x1f\x7f]+$/.match(subjectId))
			throw "Representation subject id must be a non-empty value without control characters";
		if (sourceKind == null || identity == null || mutation == null || escape == null || surface == null || nullability == null || boundary == null)
			throw "Representation facts cannot contain null enum values";
		if (origin == null)
			throw "Representation facts require an exact Haxe source origin";
		if (boundary == BoundaryThread || boundary == BoundaryTask || boundary == BoundaryStaticStorage)
			require(escape == EscapeMay, "thread, task, and static-storage boundaries require a value that may escape");

		var isBorrowed = sourceKind == SourceBorrowedRef || sourceKind == SourceBorrowedMutRef || sourceKind == SourceBorrowedStr
			|| sourceKind == SourceBorrowedSlice || sourceKind == SourceBorrowedMutSlice;
		if (isBorrowed) {
			require(identity == IdentityNone, "borrowed values do not own stable identity");
			require(escape == EscapeLocal, "borrowed values cannot escape their admitted lexical region");
			require(surface == SurfaceRustNative, "borrowed values require an explicit Rust-native surface");
			require(nullability == NonNullable, "borrow tokens cannot carry Haxe nullability");
			require(boundary == BoundaryLocal, "borrow tokens cannot cross thread, task, dynamic, or static boundaries");
			var mutableBorrow = sourceKind == SourceBorrowedMutRef || sourceKind == SourceBorrowedMutSlice;
			require(mutableBorrow ? mutation == MutationExclusiveBorrow : mutation == MutationImmutable,
				"borrow mutation facts must match the immutable or exclusive token family");
		}

		switch (sourceKind) {
			case SourceClassReference | SourcePolymorphicReference | SourceArray | SourceAnonymousObject | SourceBytesReference:
				require(identity == IdentityStable, "reference values require stable identity");
				require(mutation == MutationShared, "reference values require alias-visible shared mutation");
				require(surface == SurfacePortableHaxe, "Haxe reference values require the portable Haxe surface contract");
			case SourceNativeOwned:
				require(identity == IdentityNone, "owned native values do not use Haxe reference identity");
				require(mutation == MutationImmutable || mutation == MutationOwned,
					"owned native values allow only immutable or uniquely owned mutation");
				require(surface == SurfaceRustNative, "owned native values require an explicit Rust-native surface");
			case SourceNativeHandle:
				require(identity == IdentityNone, "owned native handles do not provide Haxe alias identity");
				require(mutation == MutationImmutable || mutation == MutationOwned,
					"native handles allow only immutable or uniquely owned mutation");
				require(surface == SurfaceRustNative, "native handles require an explicit Rust-native surface");
			case SourceDynamic:
				require(identity == IdentityNone, "the dynamic carrier owns payload identity separately");
				require(surface == SurfacePortableHaxe, "dynamic is a portable Haxe runtime boundary");
				require(mutation != MutationExclusiveBorrow, "dynamic cannot carry a lexical borrow mutation fact");
			case SourceString:
				require(identity == IdentityNone && mutation == MutationImmutable, "String is an immutable reusable value");
				require(surface != SurfacePortableFacade, "String must use either the portable Haxe or explicit Rust-native surface");
			case SourceFunctionValue:
				require(identity == IdentityStable, "shared callable values require stable handle identity");
				require(mutation == MutationImmutable || mutation == MutationShared,
					"shared callable mutation is either absent or alias-visible");
				require(surface == SurfacePortableHaxe, "Haxe function values require the portable Haxe surface contract");
			case SourceIterator:
				require(identity == IdentityStable && mutation == MutationShared,
					"Haxe iterator aliases require stable identity and shared cursor mutation");
				require(surface == SurfacePortableHaxe, "Haxe iterators require the portable Haxe surface contract");
			case SourcePortableFacade:
				require(surface == SurfacePortableFacade, "portable facade values require explicit facade admission");
				require(identity == IdentityNone && (mutation == MutationImmutable || mutation == MutationOwned),
					"admitted owned facade values cannot claim Haxe reference identity or shared mutation");
			case SourceScalar | SourceEnumValue | SourceCoreHandle:
				require(identity == IdentityNone && (mutation == MutationImmutable || mutation == MutationOwned),
					"ordinary values allow only immutable or uniquely owned mutation");
				require(surface != SurfacePortableFacade, "ordinary values cannot borrow portable-facade authority");
			case SourceBorrowedRef | SourceBorrowedMutRef | SourceBorrowedStr | SourceBorrowedSlice | SourceBorrowedMutSlice:
		}

		return new RustRepresentationFacts(subjectId, sourceKind, identity, mutation, escape, surface, nullability, boundary, origin);
	}

	static inline function require(condition:Bool, message:String):Void {
		if (!condition)
			throw 'Invalid representation facts: $message';
	}
}

/**
	One immutable representation and boundary decision.

	Why
	- Lowering, clone insertion, runtime planning, no-hxrt, and crossing diagnostics need to consume the
	  same answer instead of reclassifying a type independently.

	What
	- Records storage shape, null encoding, ownership, reuse policy, one selection reason, semantic
	  runtime reasons, contextual Rust bounds, no-hxrt eligibility, and exact source origin.

	How
	- Only `RustRepresentationPlanner` can construct a decision.
	- Array accessors return defensive copies so later report code cannot mutate planner truth.
**/
class RustRepresentationDecision {
	public final subjectId:String;
	public final sourceKind:RustSourceValueKind;
	public final identity:RustIdentityFact;
	public final mutation:RustMutationFact;
	public final escape:RustEscapeFact;
	public final surface:RustSurfaceFact;
	public final nullability:RustNullabilityFact;
	public final boundary:RustBoundaryKind;
	public final representation:RustRepresentationKind;
	public final nullEncoding:RustNullEncoding;
	public final ownership:RustOwnershipPolicy;
	public final reuse:RustReusePolicy;
	public final reason:RustRepresentationReason;
	public final noHxrtEligible:Bool;
	public final origin:RustDecisionOrigin;
	final runtime:Array<RustRuntimeRequirementKind>;
	final bounds:Array<RustRequiredBound>;

	@:allow(reflaxe.rust.analyze.RustRepresentationPlanner)
	private function new(facts:RustRepresentationFacts, representation:RustRepresentationKind, nullEncoding:RustNullEncoding, ownership:RustOwnershipPolicy,
			reuse:RustReusePolicy, reason:RustRepresentationReason, runtime:Array<RustRuntimeRequirementKind>, bounds:Array<RustRequiredBound>) {
		this.subjectId = facts.subjectId;
		this.sourceKind = facts.sourceKind;
		this.identity = facts.identity;
		this.mutation = facts.mutation;
		this.escape = facts.escape;
		this.surface = facts.surface;
		this.nullability = facts.nullability;
		this.boundary = facts.boundary;
		this.representation = representation;
		this.nullEncoding = nullEncoding;
		this.ownership = ownership;
		this.reuse = reuse;
		this.reason = reason;
		this.runtime = runtime.copy();
		this.bounds = bounds.copy();
		this.noHxrtEligible = runtime.length == 0;
		this.origin = facts.origin;
	}

	public inline function runtimeRequirements():Array<RustRuntimeRequirementKind> {
		return runtime.copy();
	}

	public inline function requiredBounds():Array<RustRequiredBound> {
		return bounds.copy();
	}

	public function canonicalKey():String {
		return subjectId + "\u0000" + origin.sourceFile + "\u0000" + origin.startByte + "\u0000" + origin.endByte + "\u0000" + boundary.id();
	}
}

/**
	The single pure decision function for normalized representation facts.

	Why
	- Compiler-private predicates currently answer overlapping questions about storage, cloning,
	  runtime use, and crossings. A pure planner gives every consumer one auditable answer.

	What
	- Chooses the Rust storage/null/ownership/reuse tuple and stable reason for each admitted source family.
	- Adds bounds only for the supplied real boundary.

	How
	- Facts are validated before entry. Runtime reasons are lexicographically canonical; bounds use
	  Rust's review-friendly `Clone, Send, Sync, static` policy order.
**/
class RustRepresentationPlanner {
	/**
		Selects the complete representation tuple for validated facts.

		Why / What / How
		- Every downstream consumer needs the same storage, null, ownership, reuse, runtime, and boundary
		  answer. Re-deriving any part later would reintroduce drift.
		- The function is deterministic and side-effect free; construction remains private so callers
		  cannot forge a decision that disagrees with its reason.
	**/
	public static function decide(facts:RustRepresentationFacts):RustRepresentationDecision {
		if (facts == null)
			throw "Representation planner facts cannot be null";

		var representation:RustRepresentationKind;
		var ownership:RustOwnershipPolicy;
		var reuse:RustReusePolicy;
		var reason:RustRepresentationReason;
		var runtime:Array<RustRuntimeRequirementKind> = [];

		switch (facts.sourceKind) {
			case SourceScalar | SourceCoreHandle:
				representation = RepresentationCopyValue;
				ownership = OwnershipCopy;
				reuse = ReuseCopy;
				reason = facts.sourceKind == SourceCoreHandle ? ReasonHaxeCoreHandle : ReasonHaxeScalar;
			case SourceEnumValue:
				representation = RepresentationOwnedValue;
				ownership = OwnershipMove;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxeEnum;
			case SourceClassReference | SourceBytesReference:
				representation = RepresentationSharedIdentity;
				ownership = OwnershipShared;
				reuse = ReuseCloneWhenNeeded;
				reason = facts.sourceKind == SourceBytesReference ? ReasonHaxeBytesIdentity : ReasonHaxeClassIdentity;
				runtime = [RuntimeObjectIdentity, RuntimeReferenceMutation];
			case SourcePolymorphicReference:
				representation = RepresentationSharedTraitObject;
				ownership = OwnershipShared;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxePolymorphicIdentity;
				runtime = [RuntimeObjectIdentity, RuntimeReferenceMutation];
			case SourceBorrowedRef | SourceBorrowedMutRef | SourceBorrowedStr | SourceBorrowedSlice | SourceBorrowedMutSlice:
				representation = RepresentationBorrowedToken;
				ownership = OwnershipBorrowed;
				reuse = ReuseBorrow;
				reason = ReasonRustBorrowSurface;
			case SourceNativeOwned:
				representation = RepresentationOwnedValue;
				ownership = OwnershipMove;
				reuse = ReuseMoveOnce;
				reason = ReasonRustOwnedSurface;
			case SourceNativeHandle:
				representation = RepresentationNativeHandle;
				ownership = OwnershipMove;
				reuse = ReuseMoveOnce;
				reason = ReasonRustNativeHandle;
			case SourceDynamic:
				representation = RepresentationDynamicPayload;
				ownership = OwnershipMove;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxeDynamicPayload;
				runtime = [RuntimeDynamic];
			case SourceString:
				if (facts.surface == SurfaceRustNative) {
					representation = RepresentationOwnedValue;
					runtime = [];
				} else {
					representation = RepresentationRuntimeString;
					runtime = [RuntimeHaxeStringSemantics];
					if (facts.nullability == Nullable)
						runtime.push(RuntimeNullableCompat);
				}
				ownership = OwnershipMove;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxeStringContract;
			case SourceArray:
				representation = RepresentationRuntimeArray;
				ownership = OwnershipShared;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxeArrayContract;
				runtime = [RuntimeHaxeArraySemantics, RuntimeReferenceMutation];
			case SourceAnonymousObject:
				representation = RepresentationRuntimeAnonymousObject;
				ownership = OwnershipShared;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxeAnonymousObject;
				runtime = [RuntimeAnonymousObject, RuntimeObjectIdentity, RuntimeReferenceMutation];
			case SourceFunctionValue:
				representation = RepresentationSharedFunction;
				ownership = OwnershipShared;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxeFunctionValue;
				runtime = [RuntimeFunctionValue];
				if (facts.mutation == MutationShared)
					runtime.push(RuntimeSharedClosureCell);
			case SourceIterator:
				representation = RepresentationRuntimeIterator;
				ownership = OwnershipShared;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonHaxeIteratorContract;
				runtime = [RuntimeIteratorSemantics];
			case SourcePortableFacade:
				representation = RepresentationOwnedValue;
				ownership = OwnershipMove;
				reuse = ReuseCloneWhenNeeded;
				reason = ReasonAdmittedPortableFacade;
		}

		if (facts.boundary == BoundaryDynamic)
			runtime.push(RuntimeDynamic);

		runtime = canonicalRuntime(runtime);
		var bounds = requiredBounds(facts.boundary, representation);
		var nullEncoding = selectNullEncoding(facts, representation);
		return new RustRepresentationDecision(facts, representation, nullEncoding, ownership, reuse, reason, runtime, bounds);
	}

	/**
		Chooses whether null is forbidden, intrinsic to the carrier, or represented by an outer Option.

		Why / What / How
		- Several Haxe-compatible carriers already own a null sentinel, while ordinary Rust values must
		  use `Option<T>`. Keeping this answer in the planner prevents a second lowering classifier.
	**/
	static function selectNullEncoding(facts:RustRepresentationFacts, representation:RustRepresentationKind):RustNullEncoding {
		if (facts.nullability == NonNullable)
			return NullNotAdmitted;
		if (facts.sourceKind == SourceCoreHandle)
			return NullIntrinsic;
		return switch (representation) {
			case RepresentationSharedIdentity | RepresentationSharedTraitObject | RepresentationDynamicPayload | RepresentationRuntimeString
				| RepresentationRuntimeArray | RepresentationRuntimeAnonymousObject | RepresentationSharedFunction:
				NullIntrinsic;
			case RepresentationCopyValue | RepresentationOwnedValue | RepresentationBorrowedToken | RepresentationNativeHandle
				| RepresentationRuntimeIterator:
				NullOuterOption;
		};
	}

	/**
		Returns only the trait/lifetime bounds introduced by the supplied boundary.

		Why / What / How
		- Local values inherit no crossing bounds. Thread/task ownership needs `Send` plus static lifetime,
		  shared thread/task values also need `Sync`, Dynamic follows its carrier contract, and shared
		  static storage needs only `Sync` plus static lifetime.
	**/
	static function requiredBounds(boundary:RustBoundaryKind, representation:RustRepresentationKind):Array<RustRequiredBound> {
		return switch (boundary) {
			case BoundaryLocal: [];
			case BoundaryThread | BoundaryTask:
				var out = [BoundSend, BoundStatic];
				if (isSharedRepresentation(representation))
					out.insert(1, BoundSync);
				out;
			case BoundaryDynamic: [BoundClone, BoundSend, BoundSync, BoundStatic];
			case BoundaryStaticStorage: [BoundSync, BoundStatic];
		};
	}

	static function isSharedRepresentation(representation:RustRepresentationKind):Bool {
		return representation == RepresentationSharedIdentity || representation == RepresentationSharedTraitObject
			|| representation == RepresentationRuntimeArray || representation == RepresentationRuntimeAnonymousObject
			|| representation == RepresentationSharedFunction || representation == RepresentationRuntimeIterator;
	}

	static function canonicalRuntime(values:Array<RustRuntimeRequirementKind>):Array<RustRuntimeRequirementKind> {
		var seen:Map<String, Bool> = [];
		var out:Array<RustRuntimeRequirementKind> = [];
		for (value in values) {
			if (!seen.exists(value.id())) {
				seen.set(value.id(), true);
				out.push(value);
			}
		}
		out.sort((left, right) -> compareStrings(left.id(), right.id()));
		return out;
	}

	static inline function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}

/**
	A canonical, defensive snapshot suitable for embedding in `runtime_plan.json`.

	Why
	- Report generation must be deterministic even when compiler traversal order changes.
	- Decoders must reject duplicate or non-canonical arrays instead of silently normalizing untrusted
	  artifacts.

	What
	- `of` copies, sorts, and validates compiler-produced decisions.
	- `requireCanonical` validates externally decoded order without changing it.
	- `renderJson` provides the component contract used by focused tests and the later runtime report.

	How
	- A complete source/boundary key establishes total order and duplicate detection.
**/
class RustRepresentationPlanSnapshot {
	public static inline var SCHEMA_VERSION:Int = 1;
	public static inline var GENERATOR:String = "reflaxe.rust";
	final decisions:Array<RustRepresentationDecision>;
	public var decisionCount(get, never):Int;

	private function new(decisions:Array<RustRepresentationDecision>) {
		this.decisions = decisions.copy();
	}

	/**
		Owns and canonicalizes compiler-produced decisions.

		Why / What / How
		- Compiler traversal order is not a report contract. Copy, sort, and reject duplicate stable keys
		  before serialization so repeated builds remain byte-identical.
	**/
	public static function of(values:Array<RustRepresentationDecision>):RustRepresentationPlanSnapshot {
		var owned = requireValues(values);
		owned.sort(compareDecisions);
		requireStrictOrder(owned);
		return new RustRepresentationPlanSnapshot(owned);
	}

	/**
		Validates already-decoded decisions without silently reordering them.

		Why / What / How
		- External artifacts must prove they were canonical when written. Copy the input and reject a
		  duplicate or out-of-order stable key rather than normalizing untrusted data.
	**/
	public static function requireCanonical(values:Array<RustRepresentationDecision>):RustRepresentationPlanSnapshot {
		var owned = requireValues(values);
		requireStrictOrder(owned);
		return new RustRepresentationPlanSnapshot(owned);
	}

	public inline function at(index:Int):RustRepresentationDecision {
		if (index < 0 || index >= decisions.length)
			throw 'Representation decision index is out of bounds: $index';
		return decisions[index];
	}

	inline function get_decisionCount():Int {
		return decisions.length;
	}

	/**
		Renders the versioned decision component as deterministic JSON.

		Why / What / How
		- The current report code avoids a dynamic JSON boundary and writes fields in one reviewed order.
		- Call only on a snapshot created by `of` or `requireCanonical`.
	**/
	public function renderJson():String {
		var rendered = [for (decision in decisions) renderDecision(decision)];
		return '{"schemaVersion":' + SCHEMA_VERSION + ',"generator":"' + GENERATOR + '","decisions":[' + rendered.join(",") + "]}";
	}

	static function requireValues(values:Array<RustRepresentationDecision>):Array<RustRepresentationDecision> {
		if (values == null)
			throw "Representation decision array cannot be null";
		var owned = values.copy();
		for (value in owned)
			if (value == null) throw "Representation decision cannot be null";
		return owned;
	}

	static function requireStrictOrder(values:Array<RustRepresentationDecision>):Void {
		for (index in 1...values.length) {
			var order = compareDecisions(values[index - 1], values[index]);
			if (order == 0)
				throw 'Duplicate representation decision: ${values[index].canonicalKey()}';
			if (order > 0)
				throw "Representation decisions are not in canonical order";
		}
	}

	static function compareDecisions(left:RustRepresentationDecision, right:RustRepresentationDecision):Int {
		return compareStrings(left.canonicalKey(), right.canonicalKey());
	}

	static function renderDecision(decision:RustRepresentationDecision):String {
		var runtime = [for (reason in decision.runtimeRequirements()) '"' + jsonEscape(reason.id()) + '"'];
		var bounds = [for (bound in decision.requiredBounds()) '"' + jsonEscape(bound.id()) + '"'];
		return '{"subjectId":"'
			+ jsonEscape(decision.subjectId)
			+ '","sourceKind":"'
			+ decision.sourceKind.id()
			+ '","identity":"'
			+ decision.identity.id()
			+ '","mutation":"'
			+ decision.mutation.id()
			+ '","escape":"'
			+ decision.escape.id()
			+ '","surface":"'
			+ decision.surface.id()
			+ '","nullability":"'
			+ decision.nullability.id()
			+ '","boundary":"'
			+ decision.boundary.id()
			+ '","representation":"'
			+ decision.representation.id()
			+ '","nullEncoding":"'
			+ decision.nullEncoding.id()
			+ '","ownership":"'
			+ decision.ownership.id()
			+ '","reuse":"'
			+ decision.reuse.id()
			+ '","reason":"'
			+ decision.reason.id()
			+ '","runtimeRequirements":['
			+ runtime.join(",")
			+ '],"requiredBounds":['
			+ bounds.join(",")
			+ '],"noHxrtEligible":'
			+ (decision.noHxrtEligible ? "true" : "false")
			+ ',"origin":{"sourceFile":"'
			+ jsonEscape(decision.origin.sourceFile)
			+ '","modulePath":"'
			+ jsonEscape(decision.origin.modulePath)
			+ '","startByte":'
			+ decision.origin.startByte
			+ ',"byteLength":'
			+ (decision.origin.endByte - decision.origin.startByte)
			+ "}}";
	}

	static function jsonEscape(value:String):String {
		var out = new StringBuf();
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			switch (code) {
				case 34: out.add('\\"');
				case 92: out.add('\\\\');
				case 8: out.add('\\b');
				case 9: out.add('\\t');
				case 10: out.add('\\n');
				case 12: out.add('\\f');
				case 13: out.add('\\r');
				default:
					if (code < 32) {
						out.add("\\u");
						out.add(StringTools.hex(code, 4).toLowerCase());
					} else {
						out.addChar(code);
					}
			}
		}
		return out.toString();
	}

	static inline function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
