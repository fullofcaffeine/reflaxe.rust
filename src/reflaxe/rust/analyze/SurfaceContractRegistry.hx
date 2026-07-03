package reflaxe.rust.analyze;

/**
	Serialized source contract kind for a compiler-recognized surface.

	Why
	- Capability-driven lowering must not infer semantics from broad namespace names.
	- Reports need stable string values, while compiler code should avoid loose string literals.

	What
	- `portable_facade` means a cross-target source API with an admitted Rust representation.
	- Future registry entries can use additional values when the compiler reports ordinary Haxe,
	  Rust-native, or metal-island surfaces through the same schema.

	How
	- Enum abstract values serialize directly into `contract_report.*`.
**/
enum abstract SurfaceSourceContract(String) to String {
	var PortableFacade = "portable_facade";
}

/**
	Serialized fallback policy for an admitted surface.

	Why
	- A facade contract must state what happens when native lowering is not enough.
	- Stable string values keep report diffs deterministic and make policy changes reviewable.

	What
	- `error_or_reasoned_runtime_requirement` means the compiler may not silently fall back to a
	  broad runtime path. It must either reject the usage under the active policy or emit a semantic
	  runtime requirement reason.

	How
	- Stored on every `SurfaceContract` entry and emitted in `contract_report.*`.
**/
enum abstract SurfaceFallbackPolicy(String) to String {
	var ErrorOrReasonedRuntimeRequirement = "error_or_reasoned_runtime_requirement";
}

/**
	Serialized reason for a selected native representation.

	Why
	- Native representation choices should be auditable in CI.
	- A stable reason string distinguishes intentional facade lowering from accidental target-shape
	  inference.

	What
	- `admitted_portable_facade` means the representation came from a registry entry, not from a
	  heuristic over arbitrary portable code.
**/
enum abstract NativeRepresentationReason(String) to String {
	var AdmittedPortableFacade = "admitted_portable_facade";
}

/**
	Compiler-owned contract for a surface that can affect lowering semantics.

	Why
	- Oracle review for M42 rejected namespace-wide `reflaxe.std.*` inference. Admission has to be
	  per symbol/module/version.
	- The compiler and reports need one typed record that says what source semantics are being
	  preserved and which Rust representation is allowed.

	What
	- `surfaceId`: stable report ID.
	- `modulePath`: Haxe module path that admits the surface.
	- `sourceContract`: serialized contract family.
	- `facadeVersion`: version of this facade contract, independent from package versioning.
	- `portableSemantics`: short stable description of the portable API promise.
	- `rustRepresentation`: canonical Rust representation selected by this backend.
	- `backendSpecializationAllowed`: whether the Rust backend may specialize this API.
	- `requiresRustImport`: false for portable facades; true would indicate explicit native source.
	- `noHxrtEligible`: whether the surface itself can participate in a future no-runtime subset.
	- `fallbackPolicy`: how unsupported semantics must be handled.

	How
	- `SurfaceContractRegistry.collectConsumed(...)` filters this catalog using typed module usage.
	- Report rendering serializes the exact records returned by the registry.
**/
typedef SurfaceContract = {
	var surfaceId:String;
	var modulePath:String;
	var sourceContract:SurfaceSourceContract;
	var facadeVersion:Int;
	var portableSemantics:String;
	var rustRepresentation:String;
	var backendSpecializationAllowed:Bool;
	var requiresRustImport:Bool;
	var noHxrtEligible:Bool;
	var fallbackPolicy:SurfaceFallbackPolicy;
};

/**
	Native representation selected for one consumed surface.

	Why
	- Consuming a facade is separate from choosing its Rust representation.
	- Keeping this as a distinct report section lets future planner work explain non-native or
	  runtime-backed choices without changing the admitted surface record.

	What
	- `surfaceId` links back to `consumedSurfaces`.
	- `selectedRepresentation` names the emitted Rust shape.
	- `reason` explains why that shape was selected.
**/
typedef NativeRepresentationDecision = {
	var surfaceId:String;
	var selectedRepresentation:String;
	var reason:NativeRepresentationReason;
};

/**
	SurfaceContractRegistry

	Why
	- Capability-driven facades need a compiler-readable admission point.
	- Broad namespace matching would reintroduce hidden semantic inference, so the first registry is
	  intentionally tiny and explicit.

	What
	- Admits only the current Rust-local `reflaxe.std.Option` and `reflaxe.std.Result` portable
	  facade contracts.
	- Builds deterministic report snapshots from typed module usage.

	How
	- `collectConsumed` accepts module paths from `TypeUsageAnalyzer`.
	- Unknown `reflaxe.std.*` modules are deliberately ignored here; adding one requires a new
	  registry entry, docs, and fixture evidence.
**/
class SurfaceContractRegistry {
	static final ADMITTED:Array<SurfaceContract> = [
		{
			surfaceId: "reflaxe.std.Option",
			modulePath: "reflaxe.std.Option",
			sourceContract: PortableFacade,
			facadeVersion: 1,
			portableSemantics: "haxe-compatible-option",
			rustRepresentation: "core::option::Option<T>",
			backendSpecializationAllowed: true,
			requiresRustImport: false,
			noHxrtEligible: true,
			fallbackPolicy: ErrorOrReasonedRuntimeRequirement
		},
		{
			surfaceId: "reflaxe.std.Result",
			modulePath: "reflaxe.std.Result",
			sourceContract: PortableFacade,
			facadeVersion: 1,
			portableSemantics: "haxe-compatible-result",
			rustRepresentation: "core::result::Result<T,E>",
			backendSpecializationAllowed: true,
			requiresRustImport: false,
			noHxrtEligible: true,
			fallbackPolicy: ErrorOrReasonedRuntimeRequirement
		}
	];

	public static function collectConsumed(modulePaths:Array<String>):Array<SurfaceContract> {
		var used:Map<String, Bool> = [];
		if (modulePaths != null) {
			for (path in modulePaths) {
				if (path != null && path.length > 0)
					used.set(path, true);
			}
		}

		var out:Array<SurfaceContract> = [];
		for (contract in ADMITTED) {
			if (used.exists(contract.modulePath))
				out.push(copyContract(contract));
		}
		out.sort((a, b) -> compareStrings(a.surfaceId, b.surfaceId));
		return out;
	}

	public static function buildNativeRepresentationPlan(consumed:Array<SurfaceContract>):Array<NativeRepresentationDecision> {
		var out:Array<NativeRepresentationDecision> = [];
		if (consumed == null)
			return out;
		for (contract in consumed) {
			if (!contract.backendSpecializationAllowed)
				continue;
			out.push({
				surfaceId: contract.surfaceId,
				selectedRepresentation: contract.rustRepresentation,
				reason: AdmittedPortableFacade
			});
		}
		out.sort((a, b) -> compareStrings(a.surfaceId, b.surfaceId));
		return out;
	}

	static function copyContract(contract:SurfaceContract):SurfaceContract {
		return {
			surfaceId: contract.surfaceId,
			modulePath: contract.modulePath,
			sourceContract: contract.sourceContract,
			facadeVersion: contract.facadeVersion,
			portableSemantics: contract.portableSemantics,
			rustRepresentation: contract.rustRepresentation,
			backendSpecializationAllowed: contract.backendSpecializationAllowed,
			requiresRustImport: contract.requiresRustImport,
			noHxrtEligible: contract.noHxrtEligible,
			fallbackPolicy: contract.fallbackPolicy
		};
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}
