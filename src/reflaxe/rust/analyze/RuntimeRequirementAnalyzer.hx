package reflaxe.rust.analyze;

/**
	Stable semantic reason kind for requiring the Haxe runtime.

	Why
	- Runtime planning must explain source semantics before codegen happens to mention `hxrt`.
	- Report consumers need enum-like values that remain stable across wording changes.

	What
	- The values cover the first capability-driven facade taxonomy: object identity, shared mutation,
	  dynamic/reflection, anonymous runtime objects, exceptions, nullable compatibility, closure
	  cells, platform abstractions, and Haxe collection/string compatibility.

	How
	- Enum abstract values serialize directly into `runtime_plan.*`.
	- The analyzer emits only reasons it can justify from typed module usage or explicit defines; the
	  enum intentionally contains additional values for later AST-level passes.
**/
enum abstract RuntimeRequirementKind(String) to String {
	var ObjectIdentity = "object_identity";
	var ReferenceMutation = "reference_mutation";
	var Dynamic = "dynamic";
	var Reflection = "reflection";
	var AnonymousObject = "anonymous_object";
	var Exception = "exception";
	var NullableCompat = "nullable_compat";
	var SharedClosureCell = "shared_closure_cell";
	var PlatformAbstraction = "platform_abstraction";
	var HaxeArraySemantics = "haxe_array_semantics";
	var HaxeStringSemantics = "haxe_string_semantics";
}

/**
	One semantic runtime requirement entry.

	Why
	- `HxrtFeatureAnalyzer` explains Cargo feature selection, not why Haxe semantics need runtime
	  support. This record is the separate semantic ledger Oracle requested.

	What
	- `reasonKind`: stable semantic reason enum.
	- `sourceKind`: where the reason came from (`module` or `define` in the first pass).
	- `sourceModule`: Haxe module path when available.
	- `sourceSpan`: reserved for future AST diagnostics; empty when module-level analysis is the
	  best available attribution.
	- `surfaceId`: optional facade/native surface id once surface-aware passes feed the ledger.
	- `requiresHxrt`: whether the reason requires the bundled runtime.
	- `noHxrtBlocked`: whether this reason conflicts with the active `rust_no_hxrt` contract.
	- `message`: deterministic human wording.

	How
	- Entries are sorted and deduplicated by `RuntimeRequirementAnalyzer.collect(...)`.
**/
typedef RuntimeRequirementEntry = {
	var reasonKind:RuntimeRequirementKind;
	var sourceKind:String;
	var sourceModule:String;
	var sourceSpan:String;
	var surfaceId:Null<String>;
	var requiresHxrt:Bool;
	var noHxrtBlocked:Bool;
	var message:String;
};

/**
	Aggregate semantic fallback state for the runtime plan.

	Why
	- CI and no-hxrt eligibility work need a quick deterministic summary without re-parsing every
	  ledger row.

	What
	- `requiresHxrt`: true when at least one runtime requirement needs `hxrt`.
	- `blockedByNoHxrt`: true when such a requirement appears under `rust_no_hxrt`.
	- `reasonKinds`: sorted unique reason kind values present in the ledger.
**/
typedef RuntimeFallbackSummary = {
	var requiresHxrt:Bool;
	var blockedByNoHxrt:Bool;
	var reasonKinds:Array<RuntimeRequirementKind>;
};

/**
	RuntimeRequirementAnalyzer

	Why
	- The runtime plan needs semantic fallback reasons, not just selected Cargo features or emitted
	  `hxrt::` path checks.
	- Keeping this in `analyze/` gives future no-hxrt eligibility and typed surface usage passes a
	  common report vocabulary.

	What
	- Builds a deterministic first-pass ledger from typed module usage plus explicit compatibility
	  defines.
	- Deliberately avoids broad inference that cannot be justified from available compiler data.

	How
	- `collect(...)` accepts sorted/unsorted module paths from `TypeUsageAnalyzer`.
	- `summarize(...)` reduces the ledger to the report-level fallback summary.
**/
class RuntimeRequirementAnalyzer {
	public static function collect(modulePaths:Array<String>, noHxrt:Bool, nullableStrings:Bool, allowUnresolvedMonomorphDynamic:Bool,
			allowUnmappedCoreTypeDynamic:Bool):Array<RuntimeRequirementEntry> {
		var entries:Array<RuntimeRequirementEntry> = [];

		if (modulePaths != null) {
			for (path in modulePaths) {
				if (path == null || path.length == 0)
					continue;

				if (isDynamicPath(path))
					add(entries, Dynamic, "module", path, null, noHxrt, "Dynamic-compatible values require hxrt dynamic representation.");

				if (isReflectionPath(path))
					add(entries, Reflection, "module", path, null, noHxrt, "Reflection/runtime introspection requires hxrt support.");

				if (isAnonymousObjectPath(path))
					add(entries, AnonymousObject, "module", path, null, noHxrt, "Anonymous runtime objects require hxrt object storage.");

				if (isExceptionPath(path))
					add(entries, Exception, "module", path, null, noHxrt, "Haxe exception payload semantics require hxrt exception support.");

				if (isPlatformAbstractionPath(path))
					add(entries, PlatformAbstraction, "module", path, null, noHxrt, "Platform abstraction requires hxrt wrapper support.");

				if (isHaxeArrayPath(path))
					add(entries, HaxeArraySemantics, "module", path, null, noHxrt, "Haxe Array semantics require hxrt array representation.");

				if (isHaxeStringRuntimePath(path))
					add(entries, HaxeStringSemantics, "module", path, null, noHxrt, "Runtime-backed Haxe string semantics require hxrt string support.");
			}
		}

		if (nullableStrings) {
			add(entries, NullableCompat, "define", "rust_string_nullable", null, noHxrt,
				"Nullable compatibility mode requires runtime-backed string/null representation.");
			add(entries, HaxeStringSemantics, "define", "rust_string_nullable", null, noHxrt,
				"Nullable String compatibility requires hxrt string representation.");
		}

		if (allowUnresolvedMonomorphDynamic)
			add(entries, Dynamic, "define", "rust_allow_unresolved_monomorph_dynamic", null, noHxrt,
				"Unresolved monomorph fallback requires Dynamic runtime representation.");

		if (allowUnmappedCoreTypeDynamic)
			add(entries, Dynamic, "define", "rust_allow_unmapped_coretype_dynamic", null, noHxrt,
				"Unmapped core-type fallback requires Dynamic runtime representation.");

		entries.sort(compareEntries);
		return entries;
	}

	public static function summarize(entries:Array<RuntimeRequirementEntry>):RuntimeFallbackSummary {
		var requiresHxrt = false;
		var blockedByNoHxrt = false;
		var reasonKinds:Array<RuntimeRequirementKind> = [];

		if (entries != null) {
			for (entry in entries) {
				if (entry.requiresHxrt)
					requiresHxrt = true;
				if (entry.noHxrtBlocked)
					blockedByNoHxrt = true;
				if (!containsReasonKind(reasonKinds, entry.reasonKind))
					reasonKinds.push(entry.reasonKind);
			}
		}

		reasonKinds.sort((a, b) -> compareStrings(a, b));
		return {
			requiresHxrt: requiresHxrt,
			blockedByNoHxrt: blockedByNoHxrt,
			reasonKinds: reasonKinds
		};
	}

	static function add(entries:Array<RuntimeRequirementEntry>, reasonKind:RuntimeRequirementKind, sourceKind:String, sourceModule:String,
			surfaceId:Null<String>, noHxrt:Bool, message:String):Void {
		var entry:RuntimeRequirementEntry = {
			reasonKind: reasonKind,
			sourceKind: sourceKind,
			sourceModule: sourceModule,
			sourceSpan: "",
			surfaceId: surfaceId,
			requiresHxrt: true,
			noHxrtBlocked: noHxrt,
			message: message
		};

		for (existing in entries) {
			if (sameEntry(existing, entry))
				return;
		}
		entries.push(entry);
	}

	static function sameEntry(a:RuntimeRequirementEntry, b:RuntimeRequirementEntry):Bool {
		return a.reasonKind == b.reasonKind && a.sourceKind == b.sourceKind && a.sourceModule == b.sourceModule && a.sourceSpan == b.sourceSpan
			&& a.surfaceId == b.surfaceId;
	}

	static function containsReasonKind(reasonKinds:Array<RuntimeRequirementKind>, needle:RuntimeRequirementKind):Bool {
		for (reasonKind in reasonKinds) {
			if (reasonKind == needle)
				return true;
		}
		return false;
	}

	static inline function isDynamicPath(path:String):Bool {
		return path == "Dynamic"
			|| path == "haxe.DynamicAccess"
			|| path == "haxe.Json"
			|| StringTools.startsWith(path, "haxe.json.")
			|| StringTools.startsWith(path, "hxrt.dynamic")
			|| StringTools.startsWith(path, "hxrt.json");
	}

	static inline function isReflectionPath(path:String):Bool {
		return path == "Reflect" || path == "Type" || StringTools.startsWith(path, "haxe.rtti.");
	}

	static inline function isAnonymousObjectPath(path:String):Bool {
		return StringTools.startsWith(path, "hxrt.anon");
	}

	static inline function isExceptionPath(path:String):Bool {
		return StringTools.startsWith(path, "hxrt.exception");
	}

	static inline function isPlatformAbstractionPath(path:String):Bool {
		return path == "Sys"
			|| path == "Date"
			|| StringTools.startsWith(path, "DateTools")
			|| StringTools.startsWith(path, "sys.")
			|| StringTools.startsWith(path, "rust.async.")
			|| StringTools.startsWith(path, "rust.concurrent.")
			|| StringTools.startsWith(path, "hxrt.async_")
			|| StringTools.startsWith(path, "hxrt.concurrent")
			|| StringTools.startsWith(path, "hxrt.date")
			|| StringTools.startsWith(path, "hxrt.db")
			|| StringTools.startsWith(path, "hxrt.fs")
			|| StringTools.startsWith(path, "hxrt.io")
			|| StringTools.startsWith(path, "hxrt.net")
			|| StringTools.startsWith(path, "hxrt.process")
			|| StringTools.startsWith(path, "hxrt.ssl")
			|| StringTools.startsWith(path, "hxrt.sys")
			|| StringTools.startsWith(path, "hxrt.thread");
	}

	static inline function isHaxeArrayPath(path:String):Bool {
		return StringTools.startsWith(path, "hxrt.array");
	}

	static inline function isHaxeStringRuntimePath(path:String):Bool {
		return StringTools.startsWith(path, "hxrt.string");
	}

	static function compareEntries(a:RuntimeRequirementEntry, b:RuntimeRequirementEntry):Int {
		var reasonOrder = compareStrings(a.reasonKind, b.reasonKind);
		if (reasonOrder != 0)
			return reasonOrder;
		var sourceKindOrder = compareStrings(a.sourceKind, b.sourceKind);
		if (sourceKindOrder != 0)
			return sourceKindOrder;
		var sourceModuleOrder = compareStrings(a.sourceModule, b.sourceModule);
		if (sourceModuleOrder != 0)
			return sourceModuleOrder;
		var sourceSpanOrder = compareStrings(a.sourceSpan, b.sourceSpan);
		if (sourceSpanOrder != 0)
			return sourceSpanOrder;
		return compareStrings(a.surfaceId == null ? "" : a.surfaceId, b.surfaceId == null ? "" : b.surfaceId);
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}
