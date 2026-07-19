package reflaxe.rust.analyze;

import reflaxe.rust.analyze.RepresentationPlan.RustRuntimeRequirementKind;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustRuntimeRequirementCoverage;

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
	- Typed policy values serialize directly into `runtime_plan.*`.
	- The analyzer emits only reasons it can justify from typed module usage or explicit defines; the
	  shared policy vocabulary intentionally contains additional values for later AST-level passes.
**/
typedef RuntimeRequirementKind = RustRuntimeRequirementKind;

/**
	One semantic runtime requirement entry.

	Why
	- `HxrtFeatureAnalyzer` explains Cargo feature selection, not why Haxe semantics need runtime
	  support. This record is the separate semantic ledger Oracle requested.

	What
	- `reasonKind`: stable semantic reason enum.
	- `sourceKind`: `module`/`define` in report v4; internal no-hxrt rows may use `typed_ast`.
	- `sourceModule`: Haxe module path when available.
	- `sourceSpan`: exact source-private bytes for typed decisions; empty when only a module or define
	  can be attributed.
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
	- Builds a deterministic ledger from typed representation decisions, operation-level module usage,
	  and explicit compatibility defines.
	- Deliberately avoids broad inference that cannot be justified from available compiler data.

	How
	- `collect(...)` combines sorted/unsorted module paths with optional canonical typed decisions.
	- `summarize(...)` reduces the ledger to the report-level fallback summary.
**/
class RuntimeRequirementAnalyzer {
	public static function collect(modulePaths:Array<String>, noHxrt:Bool, nullableStrings:Bool, allowUnresolvedMonomorphDynamic:Bool,
			allowUnmappedCoreTypeDynamic:Bool, ?representationDecisions:Array<RustRepresentationDecision>,
			?includeExtendedDecisionReasons:Bool = false, ?coverage:Array<RustRuntimeRequirementCoverage>):Array<RuntimeRequirementEntry> {
		var entries:Array<RuntimeRequirementEntry> = [];
		if (representationDecisions != null) {
			for (decision in representationDecisions)
				addDecisionRequirements(entries, decision, noHxrt, includeExtendedDecisionReasons);
		}
		function coveredByProof(reason:RuntimeRequirementKind, path:String):Bool {
			if (coverage == null)
				return false;
			for (proof in coverage)
				if (proof != null && proof.covers(reason, path))
					return true;
			return false;
		}

		if (modulePaths != null) {
			for (path in modulePaths) {
				if (path == null || path.length == 0)
					continue;

				if (isDynamicPath(path) && !coveredByProof(RuntimeDynamic, path))
					add(entries, RuntimeDynamic, "module", path, null, noHxrt, "Dynamic-compatible values require hxrt dynamic representation.");

				if (isReflectionPath(path))
					add(entries, RuntimeReflection, "module", path, null, noHxrt, "Reflection/runtime introspection requires hxrt support.");

				if (isAnonymousObjectPath(path) && !coveredByProof(RuntimeAnonymousObject, path))
					add(entries, RuntimeAnonymousObject, "module", path, null, noHxrt, "Anonymous runtime objects require hxrt object storage.");

				if (isExceptionPath(path))
					add(entries, RuntimeException, "module", path, null, noHxrt, "Haxe exception payload semantics require hxrt exception support.");

				if (isPlatformAbstractionPath(path))
					add(entries, RuntimePlatformAbstraction, "module", path, null, noHxrt, "Platform abstraction requires hxrt wrapper support.");

				if (isHaxeArrayPath(path) && !coveredByProof(RuntimeHaxeArraySemantics, path))
					add(entries, RuntimeHaxeArraySemantics, "module", path, null, noHxrt, "Haxe Array semantics require hxrt array representation.");

				if (isHaxeStringRuntimePath(path) && !coveredByProof(RuntimeHaxeStringSemantics, path))
					add(entries, RuntimeHaxeStringSemantics, "module", path, null, noHxrt, "Runtime-backed Haxe string semantics require hxrt string support.");
			}
		}

		if (nullableStrings) {
			add(entries, RuntimeNullableCompat, "define", "rust_string_nullable", null, noHxrt,
				"Nullable compatibility mode requires runtime-backed string/null representation.");
			add(entries, RuntimeHaxeStringSemantics, "define", "rust_string_nullable", null, noHxrt,
				"Nullable String compatibility requires hxrt string representation.");
		}

		if (allowUnresolvedMonomorphDynamic)
			add(entries, RuntimeDynamic, "define", "rust_allow_unresolved_monomorph_dynamic", null, noHxrt,
				"Unresolved monomorph fallback requires Dynamic runtime representation.");

		if (allowUnmappedCoreTypeDynamic)
			add(entries, RuntimeDynamic, "define", "rust_allow_unmapped_coretype_dynamic", null, noHxrt,
				"Unmapped core-type fallback requires Dynamic runtime representation.");

		entries.sort(compareEntries);
		return entries;
	}

	/**
		Adds semantic runtime requirements owned by one representation decision.

		Why / What / How
		- Runtime and no-hxrt consumers must use the planner's reasons rather than classify the Haxe type
		  again. The source span is carried forward in a path-private deterministic spelling.
		- Runtime-plan schema v4 cannot admit the newer function/iterator reason IDs, so ordinary report
		  collection filters those two values. No-hxrt analysis opts into the complete decision-v1 set.
	**/
	public static function addDecisionRequirements(entries:Array<RuntimeRequirementEntry>, decision:RustRepresentationDecision, noHxrt:Bool,
			includeExtendedDecisionReasons:Bool):Void {
		if (entries == null || decision == null)
			return;
		for (reason in decision.runtimeRequirements()) {
			if (!includeExtendedDecisionReasons && !reason.isRuntimePlanV4Reason())
				continue;
			var entry:RuntimeRequirementEntry = {
				reasonKind: reason,
				// Runtime-plan v4 has an immutable module/define source-kind vocabulary. Its module row may
				// now carry the exact planner span; the no-hxrt-only extended path keeps the typed-AST label.
				sourceKind: includeExtendedDecisionReasons ? "typed_ast" : "module",
				sourceModule: decision.origin.modulePath,
				sourceSpan: decision.origin.sourceFile + ":" + decision.origin.startByte + "-" + decision.origin.endByte,
				surfaceId: null,
				requiresHxrt: true,
				noHxrtBlocked: noHxrt,
				message: messageForDecisionReason(reason)
			};
			var duplicate = false;
			for (existing in entries) {
				if (sameEntry(existing, entry)) {
					duplicate = true;
					break;
				}
			}
			if (!duplicate)
				entries.push(entry);
		}
	}

	static function messageForDecisionReason(reason:RuntimeRequirementKind):String {
		return switch (reason) {
			case RuntimeObjectIdentity: "Haxe object identity requires runtime-managed reference semantics.";
			case RuntimeReferenceMutation: "Alias-visible mutation requires runtime-managed shared storage.";
			case RuntimeDynamic: "Dynamic-compatible values require hxrt dynamic representation.";
			case RuntimeReflection: "Reflection/runtime introspection requires hxrt support.";
			case RuntimeAnonymousObject: "Anonymous runtime objects require hxrt object storage.";
			case RuntimeException: "Haxe exception payload semantics require hxrt exception support.";
			case RuntimeNullableCompat: "Nullable compatibility mode requires runtime-backed null representation.";
			case RuntimeSharedClosureCell: "Shared closure mutation requires a runtime-managed cell.";
			case RuntimePlatformAbstraction: "Platform abstraction requires hxrt wrapper support.";
			case RuntimeHaxeArraySemantics: "Haxe Array semantics require hxrt array representation.";
			case RuntimeHaxeStringSemantics: "Runtime-backed Haxe string semantics require hxrt string support.";
			case RuntimeFunctionValue: "Reusable Haxe function values require a shared runtime carrier.";
			case RuntimeIteratorSemantics: "Haxe iterator values require runtime-managed cursor state.";
		};
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

	public static function sameEntry(a:RuntimeRequirementEntry, b:RuntimeRequirementEntry):Bool {
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

	@:allow(reflaxe.rust.analyze.NoHxrtEligibilityAnalyzer)
	static inline function isReflectionPath(path:String):Bool {
		return path == "Reflect" || path == "Type" || StringTools.startsWith(path, "haxe.rtti.");
	}

	static inline function isAnonymousObjectPath(path:String):Bool {
		return StringTools.startsWith(path, "hxrt.anon");
	}

	static inline function isExceptionPath(path:String):Bool {
		return StringTools.startsWith(path, "hxrt.exception");
	}

	@:allow(reflaxe.rust.analyze.NoHxrtEligibilityAnalyzer)
	@:allow(reflaxe.rust.RustCompiler)
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

	public static function compareEntries(a:RuntimeRequirementEntry, b:RuntimeRequirementEntry):Int {
		var reasonOrder = compareStrings(a.reasonKind, b.reasonKind);
		if (reasonOrder != 0)
			return reasonOrder;
		var sourceKindOrder = compareStrings(a.sourceKind, b.sourceKind);
		if (sourceKindOrder != 0)
			return sourceKindOrder;
		var sourceModuleOrder = compareStrings(a.sourceModule, b.sourceModule);
		if (sourceModuleOrder != 0)
			return sourceModuleOrder;
		var sourceSpanOrder = compareSourceSpans(a.sourceSpan, b.sourceSpan);
		if (sourceSpanOrder != 0)
			return sourceSpanOrder;
		return compareStrings(a.surfaceId == null ? "" : a.surfaceId, b.surfaceId == null ? "" : b.surfaceId);
	}

	static function compareSourceSpans(left:String, right:String):Int {
		function parse(value:String):Null<{file:String, start:Int, end:Int}> {
			if (value == null || value.length == 0)
				return null;
			var colon = value.lastIndexOf(":");
			var dash = colon < 0 ? -1 : value.indexOf("-", colon + 1);
			if (colon <= 0 || dash <= colon + 1 || dash >= value.length - 1)
				return null;
			var start = Std.parseInt(value.substring(colon + 1, dash));
			var end = Std.parseInt(value.substr(dash + 1));
			if (start == null || end == null)
				return null;
			return {file: value.substr(0, colon), start: start, end: end};
		}
		var leftPoint = parse(left);
		var rightPoint = parse(right);
		if (leftPoint == null || rightPoint == null)
			return compareStrings(left == null ? "" : left, right == null ? "" : right);
		var fileOrder = compareStrings(leftPoint.file, rightPoint.file);
		if (fileOrder != 0)
			return fileOrder;
		if (leftPoint.start != rightPoint.start)
			return leftPoint.start < rightPoint.start ? -1 : 1;
		return leftPoint.end < rightPoint.end ? -1 : (leftPoint.end > rightPoint.end ? 1 : 0);
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}
