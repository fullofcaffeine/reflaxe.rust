package reflaxe.rust;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Position;

/**
	Stable machine identifier for an admitted compiler diagnostic.

	Why
	- Tooling and SemVer policy need an identifier that survives improvements to English wording.
	- Encoding diagnostics as arbitrary string prefixes at callsites would permit typos and drift.

	What
	- Each value identifies one documented failure family and severity in
	  `docs/diagnostic-contract.json`.
	- The identifier does not freeze the complete message or source-position formatting.

	How
	- Callers pass a typed value to `RustDiagnostic.error`, `warning`, or `message`.
	- CI cross-checks this enum against the machine-readable contract and rejects unowned values.
**/
enum abstract RustDiagnosticId(String) to String {
	var ProfileValueRequired = "HXRS-PROFILE-VALUE-REQUIRED";
	var ProfileUnknown = "HXRS-PROFILE-UNKNOWN";
	var ProfileContractWarning = "HXRS-PROFILE-CONTRACT-WARNING";
	var ProfileContractError = "HXRS-PROFILE-CONTRACT-ERROR";
	var NativeImportWarning = "HXRS-NATIVE-IMPORT-WARNING";
	var NativeImportError = "HXRS-NATIVE-IMPORT-ERROR";
	var NoHxrtRequiresMetal = "HXRS-NO-HXRT-REQUIRES-METAL";
	var NoHxrtFeatureConflict = "HXRS-NO-HXRT-FEATURE-CONFLICT";
	var NoHxrtNullableString = "HXRS-NO-HXRT-NULLABLE-STRING";
	var NoHxrtEligibility = "HXRS-NO-HXRT-ELIGIBILITY";
	var NoHxrtEmittedRuntime = "HXRS-NO-HXRT-EMITTED-RUNTIME";
	var AsyncRequiresMetal = "HXRS-ASYNC-REQUIRES-METAL";
	var AsyncNoHxrt = "HXRS-ASYNC-NO-HXRT";
	var AsyncNotEnabled = "HXRS-ASYNC-NOT-ENABLED";
	var AsyncMainSync = "HXRS-ASYNC-MAIN-SYNC";
	var AsyncConstructor = "HXRS-ASYNC-CONSTRUCTOR";
	var AsyncReturnFuture = "HXRS-ASYNC-RETURN-FUTURE";
	var AsyncFutureShape = "HXRS-ASYNC-FUTURE-SHAPE";
	var AsyncAwaitContext = "HXRS-ASYNC-AWAIT-CONTEXT";
	var AsyncBlockOnContext = "HXRS-ASYNC-BLOCK-ON-CONTEXT";
	var BorrowRegion = "HXRS-BORROW-REGION";
	var MetadataArity = "HXRS-METADATA-ARITY";
	var MetadataValue = "HXRS-METADATA-VALUE";
	var MetadataPlacement = "HXRS-METADATA-PLACEMENT";
	var CargoDependencyConflict = "HXRS-CARGO-DEPENDENCY-CONFLICT";
	var CargoInvocation = "HXRS-CARGO-INVOCATION";
}

/**
	Typed emission boundary for stable Rust-target diagnostics.

	Why
	- Haxe's macro API accepts only message text and a source position; it has no separate code field.
	- One formatter guarantees a parseable `[HXRS-...]` prefix without coupling consumers to prose.

	What
	- `message` formats without emitting, for analyzers that return deterministic report text.
	- `error` and `warning` preserve Haxe's native severity and position behavior.

	How
	- Keep the stable identifier first, followed by ordinary human guidance.
	- Do not parse the human guidance to recover an identifier downstream.
**/
class RustDiagnostic {
	public static inline function message(id:RustDiagnosticId, detail:String):String {
		return "[" + id + "] " + detail;
	}

	public static inline function error(id:RustDiagnosticId, detail:String, pos:Position):Void {
		Context.error(message(id, detail), pos);
	}

	public static inline function warning(id:RustDiagnosticId, detail:String, pos:Position):Void {
		Context.warning(message(id, detail), pos);
	}
}
#end
