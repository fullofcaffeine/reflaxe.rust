package reflaxe.rust.analyze;

import reflaxe.rust.analyze.RepresentationPlan.RustBoundaryKind;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationPlan.RustRuntimeRequirementKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.TypedExprReplayFamily;

/**
	Describes how Rust lowering obtains the owned value that will enter `Dynamic`.

	Why / What / How
	- Early Haxe analysis can see that a source value crosses into `Dynamic`, but an immutable
	  `rust.Ref<T>` is emitted as `&T` and cannot itself be stored after its borrow scope ends.
	- The closed choices below distinguish an already-ready value from copying or cloning the owned
	  value behind that borrow.
	- The saved crossing carries one choice to the later Rust builder. Adding a choice requires both a
	  producer case and a focused lowering/runtime contract.
**/
enum abstract RustDynamicValueMaterialization(String) from String to String {
	/** The compiled expression already is the value that enters Dynamic. */
	var DynamicValueDirect = "direct";

	/** Dereference an immutable `rust.Ref<T>` because `T` is a Copy value. */
	var DynamicValueBorrowCopy = "borrow-copy";

	/** Clone the owned `T` behind an immutable `rust.Ref<T>` before the borrow scope ends. */
	var DynamicValueBorrowClone = "borrow-clone";
}

/**
	An opaque description of the real typed Haxe value entering a saved `Dynamic` action.

	Why
	- A caller could previously combine the text `rust.Ref<String>` with a scalar/Copy classification,
	  creating a record whose fields contradicted one another.

	What
	- Keeps the exact source type spelling, outer carrier family, owned value family, and required
	  copy/clone step as one indivisible value.

	How
	- Only `RepresentationTypeAnalyzer` may create this value, while it has the real Haxe `Type` and has
	  derived every field from that same type.
	- Later snapshot and lowering code may inspect the immutable fields but cannot forge a new combination.
**/
@:allow(reflaxe.rust.analyze.RepresentationTypeAnalyzer)
class RustDynamicCrossingSourceFingerprint {
	public final sourceTypeKey:String;
	public final carrierKind:RustSourceValueKind;
	public final valueKind:RustSourceValueKind;
	public final materialization:RustDynamicValueMaterialization;

	private function new(sourceTypeKey:String, carrierKind:RustSourceValueKind, valueKind:RustSourceValueKind,
			materialization:RustDynamicValueMaterialization) {
		this.sourceTypeKey = sourceTypeKey;
		this.carrierKind = carrierKind;
		this.valueKind = valueKind;
		this.materialization = materialization;
	}

	/**
		Constructs only source combinations that lowering can safely check.

		Why / What / How
		- A caller must not pair “use directly” with a borrow or claim copy/clone behavior for the wrong
		  carrier family.
		- Validate the allowed carrier, owned-value, and preparation combinations before the immutable
		  fingerprint enters a snapshot.
		- The one permitted caller supplies these fields together while inspecting the actual Haxe `Type`.
	**/
	private static function validated(sourceTypeKey:String, carrierKind:RustSourceValueKind,
			valueKind:RustSourceValueKind, materialization:RustDynamicValueMaterialization):RustDynamicCrossingSourceFingerprint {
		if (sourceTypeKey == null || sourceTypeKey.length == 0 || sourceTypeKey.indexOf("\u0000") >= 0
			|| carrierKind == null || valueKind == null || materialization == null)
			throw "Dynamic crossing source fingerprints require a safe source type, source families, and a materialization";
		switch (materialization) {
			case DynamicValueDirect:
				if (isBorrowed(carrierKind) || carrierKind != valueKind)
					throw "A direct Dynamic action must consume the same non-borrowed source family it describes";
			case DynamicValueBorrowCopy:
				if (carrierKind != RustSourceValueKind.SourceBorrowedRef
					|| valueKind != RustSourceValueKind.SourceScalar && valueKind != RustSourceValueKind.SourceCoreHandle)
					throw "A borrow-copy Dynamic action requires rust.Ref<T> with a proven Copy inner value";
			case DynamicValueBorrowClone:
				if (carrierKind != RustSourceValueKind.SourceBorrowedRef || isBorrowed(valueKind)
					|| valueKind == RustSourceValueKind.SourceScalar || valueKind == RustSourceValueKind.SourceCoreHandle
					|| valueKind == RustSourceValueKind.SourceDynamic || valueKind == RustSourceValueKind.SourceNativeHandle)
					throw "A borrow-clone Dynamic action requires rust.Ref<T> with a proven concrete Clone inner value";
		}
		return new RustDynamicCrossingSourceFingerprint(sourceTypeKey, carrierKind, valueKind, materialization);
	}

	public function canonicalKey():String {
		return sourceTypeKey + "\u0000" + carrierKind.id() + "\u0000" + valueKind.id() + "\u0000" + materialization;
	}

	static function isBorrowed(kind:RustSourceValueKind):Bool {
		return kind == RustSourceValueKind.SourceBorrowedRef || kind == RustSourceValueKind.SourceBorrowedMutRef
			|| kind == RustSourceValueKind.SourceBorrowedStr || kind == RustSourceValueKind.SourceBorrowedSlice
			|| kind == RustSourceValueKind.SourceBorrowedMutSlice;
	}
}

/**
	Describes the exact source and destination shape that one saved `Dynamic` action may consume.

	Why / What / How
	- A source byte range alone cannot prove that lowering is boxing the same typed value inspected early.
	- The opaque source fingerprint prevents contradictory type facts, while the destination remains the
	  one currently admitted `Dynamic` boundary.
	- Lowering rebuilds this small description from its real typed value and must match it exactly.
**/
@:allow(reflaxe.rust.analyze.RepresentationTypeAnalyzer)
class RustDynamicCrossingTypeCheck {
	public final sourceFingerprint:RustDynamicCrossingSourceFingerprint;
	public final boundaryTypeKey:String;
	public var sourceTypeKey(get, never):String;
	public var carrierKind(get, never):RustSourceValueKind;
	public var valueKind(get, never):RustSourceValueKind;
	public var materialization(get, never):RustDynamicValueMaterialization;

	private function new(sourceFingerprint:RustDynamicCrossingSourceFingerprint, boundaryTypeKey:String) {
		this.sourceFingerprint = sourceFingerprint;
		this.boundaryTypeKey = boundaryTypeKey;
	}

	private static function validated(sourceFingerprint:RustDynamicCrossingSourceFingerprint,
			boundaryTypeKey:String):RustDynamicCrossingTypeCheck {
		if (sourceFingerprint == null || boundaryTypeKey != "Dynamic")
			throw "Dynamic crossing type checks require one analyzed source fingerprint and the exact Dynamic boundary";
		return new RustDynamicCrossingTypeCheck(sourceFingerprint, boundaryTypeKey);
	}

	public function canonicalKey():String {
		return sourceFingerprint.canonicalKey() + "\u0000" + boundaryTypeKey;
	}

	inline function get_sourceTypeKey():String
		return sourceFingerprint.sourceTypeKey;

	inline function get_carrierKind():RustSourceValueKind
		return sourceFingerprint.carrierKind;

	inline function get_valueKind():RustSourceValueKind
		return sourceFingerprint.valueKind;

	inline function get_materialization():RustDynamicValueMaterialization
		return sourceFingerprint.materialization;
}

/**
	Identifies one intentional re-emission of a source expression.

	Why / What / How
	- Haxe default arguments, read-only static initializers, and base constructor bodies can be compiled
	  at more than one generated Rust site even though early analysis sees one source expression.
	- `family` names the source definition being replayed; `emissionId` names the concrete generated call,
	  read, or derived-constructor site.
	- The first emission consumes the saved action. Later distinct emissions may reuse that immutable
	  action only through this explicit context; an ordinary second lookup still fails.
**/
class RustSavedCrossingReplayContext {
	public final family:TypedExprReplayFamily;
	public final emissionId:String;
	public final key:String;

	private function new(family:TypedExprReplayFamily, emissionId:String) {
		this.family = family;
		this.emissionId = emissionId;
		this.key = family.id + "\u0000" + emissionId;
	}

	public static function of(family:TypedExprReplayFamily, emissionId:String):RustSavedCrossingReplayContext {
		if (family == null || emissionId == null || emissionId.length == 0 || emissionId.indexOf("\u0000") >= 0)
			throw "Saved Dynamic replay contexts require safe family and emission identities";
		return new RustSavedCrossingReplayContext(family, emissionId);
	}
}

/**
	One saved Dynamic-boxing action consumed later by Rust lowering.

	Why / What / How
	- Recording a runtime requirement is not enough to show that the later Rust box used the same saved
	  compiler decision.
	- This record joins the decision to the exact expression bytes that emit one box and records the
	  required borrowed-value conversion. Contextual `if`/`switch` results may have one report decision
	  but several branch-level actions, all pointing back to that decision.
	- The stable key contains only private source identity, byte range, module, boundary kind, the compact
	  source/destination type check, and a zero-based action number for macros that create several boxes
	  at one span. It survives the gap
	  between Haxe's after-typing callback and Rust AST construction without retaining the complete
	  typed module graph.
**/
class RustSavedRepresentationCrossing {
	public final key:String;
	public final baseKey:String;
	public final ordinal:Int;
	/** Complete source boundary that caused this action; control-expression branches sit inside it. */
	public final boundaryOrigin:RustDecisionOrigin;
	public final origin:RustDecisionOrigin;
	public final decision:RustRepresentationDecision;
	public final typeCheck:RustDynamicCrossingTypeCheck;
	/** The source definition that permits this action to be emitted at several generated sites. */
	public final replayFamily:Null<TypedExprReplayFamily>;
	public var materialization(get, never):RustDynamicValueMaterialization;

	private function new(origin:RustDecisionOrigin, decision:RustRepresentationDecision, typeCheck:RustDynamicCrossingTypeCheck, ordinal:Int,
			boundaryOrigin:RustDecisionOrigin, replayFamily:Null<TypedExprReplayFamily>) {
		this.origin = origin;
		this.boundaryOrigin = boundaryOrigin;
		this.decision = decision;
		this.typeCheck = typeCheck;
		this.replayFamily = replayFamily;
		this.ordinal = ordinal;
		this.baseKey = baseKeyFor(origin, typeCheck);
		this.key = baseKey + "\u0000" + ordinal;
	}

	public static function of(origin:RustDecisionOrigin, decision:RustRepresentationDecision,
			typeCheck:RustDynamicCrossingTypeCheck, ?ordinal:Int = 0,
			?boundaryOrigin:RustDecisionOrigin, ?replayFamily:TypedExprReplayFamily):RustSavedRepresentationCrossing {
		if (boundaryOrigin == null)
			boundaryOrigin = origin;
		if (origin == null || boundaryOrigin == null || decision == null || typeCheck == null)
			throw "Saved representation crossings require an action location, boundary location, decision, and source type check";
		if (boundaryOrigin.modulePath != origin.modulePath || boundaryOrigin.sourceFile != origin.sourceFile
			|| boundaryOrigin.startByte > origin.startByte || boundaryOrigin.endByte < origin.endByte)
			throw "A saved Dynamic action must sit inside its complete source boundary";
		if (decision.boundary != RustBoundaryKind.BoundaryDynamic)
			throw "Saved representation crossings currently admit only Dynamic boundaries";
		if (!sameOrigin(origin, decision.origin))
			throw "A saved Dynamic action and its representation decision must name the same exact source location";
		if (decision.sourceKind != typeCheck.valueKind)
			throw "A saved Dynamic decision must describe the owned value family in its source type check";
		if (ordinal < 0)
			throw "Saved representation crossing action numbers cannot be negative";
		return new RustSavedRepresentationCrossing(origin, decision, typeCheck, ordinal, boundaryOrigin, replayFamily);
	}

	public static function baseKeyFor(origin:RustDecisionOrigin, typeCheck:RustDynamicCrossingTypeCheck):String {
		if (origin == null || typeCheck == null)
			throw "Saved representation crossing keys require an origin and source type check";
		return origin.modulePath + "\u0000" + origin.sourceFile + "\u0000" + origin.startByte + "\u0000" + origin.endByte + "\u0000dynamic\u0000"
			+ typeCheck.canonicalKey();
	}

	inline function get_materialization():RustDynamicValueMaterialization
		return typeCheck.materialization;

	static function sameOrigin(left:RustDecisionOrigin, right:RustDecisionOrigin):Bool {
		return left != null && right != null && left.modulePath == right.modulePath && left.sourceFile == right.sourceFile
			&& left.startByte == right.startByte && left.endByte == right.endByte;
	}
}

/** One saved action whose lowering count is not exactly one. */
typedef RustSavedCrossingCountProblem = {
	var crossing:RustSavedRepresentationCrossing;
	var count:Int;
}

/**
	Tracks which saved Dynamic actions Rust lowering has used.

	Why / What / How
	- Looking up a saved action and checking its final use count are one contract. Keeping separate maps
	  in the compiler would let those two views drift.
	- The tracker owns a defensive copy, returns the next action only for an exact saved source key, and
	  counts every successful lookup. Missing or extra requests never create a lowering-time decision.
	- `countProblems` reports every saved action that was not used exactly once, in stable key order.
**/
class RustSavedCrossingTracker {
	final saved:Array<RustSavedRepresentationCrossing>;
	final savedByBaseKey:Map<String, Array<RustSavedRepresentationCrossing>>;
	final nextByBaseKey:Map<String, Int>;
	final consumedByKey:Map<String, Int>;
	final primaryReplayEmission:Map<String, String>;
	final nextByReplayEmission:Map<String, Int>;
	final replayUsesByKey:Map<String, Int>;

	private function new(crossings:Array<RustSavedRepresentationCrossing>) {
		saved = crossings.copy();
		saved.sort(compareCrossings);
		savedByBaseKey = [];
		nextByBaseKey = [];
		consumedByKey = [];
		primaryReplayEmission = [];
		nextByReplayEmission = [];
		replayUsesByKey = [];
		var seenKeys:Map<String, Bool> = [];
		for (crossing in saved) {
			if (crossing == null)
				throw "Saved Dynamic crossing trackers cannot contain null actions";
			if (seenKeys.exists(crossing.key))
				throw 'Duplicate saved Dynamic crossing key `${crossing.key}`';
			seenKeys.set(crossing.key, true);
			var bucket = savedByBaseKey.get(crossing.baseKey);
			if (bucket == null) {
				bucket = [];
				savedByBaseKey.set(crossing.baseKey, bucket);
			}
			if (bucket.length > 0) {
				var expectedFamily = bucket[0].replayFamily == null ? null : bucket[0].replayFamily.id;
				var actualFamily = crossing.replayFamily == null ? null : crossing.replayFamily.id;
				if (expectedFamily != actualFamily)
					throw 'Saved Dynamic actions at `${crossing.baseKey}` cannot mix ordinary and repeated source definitions';
			}
			if (crossing.ordinal != bucket.length)
				throw 'Saved Dynamic crossing action numbers for `${crossing.baseKey}` must be contiguous from zero';
			bucket.push(crossing);
		}
	}

	public static function of(crossings:Array<RustSavedRepresentationCrossing>):RustSavedCrossingTracker {
		if (crossings == null)
			throw "Saved Dynamic crossing tracker input cannot be null";
		return new RustSavedCrossingTracker(crossings);
	}

	public static function empty():RustSavedCrossingTracker
		return new RustSavedCrossingTracker([]);

	/** Returns and counts the exact saved action, or `null` when early analysis did not save one. */
	public function consume(origin:RustDecisionOrigin, typeCheck:RustDynamicCrossingTypeCheck,
			?replay:RustSavedCrossingReplayContext):Null<RustSavedRepresentationCrossing> {
		var baseKey = RustSavedRepresentationCrossing.baseKeyFor(origin, typeCheck);
		var bucket = savedByBaseKey.get(baseKey);
		if (bucket == null)
			return null;
		if (replay != null) {
			var replayCursorKey = replay.key + "\u0000" + baseKey;
			var replayNext = nextByReplayEmission.get(replayCursorKey);
			if (replayNext == null)
				replayNext = 0;
			if (replayNext >= bucket.length)
				return null;
			var replayed = bucket[replayNext];
			if (replayed.replayFamily == null || replayed.replayFamily.id != replay.family.id)
				return null;

			var familyKey = replay.family.id + "\u0000" + baseKey;
			var primaryEmission = primaryReplayEmission.get(familyKey);
			if (primaryEmission == null) {
				primaryEmission = replay.emissionId;
				primaryReplayEmission.set(familyKey, primaryEmission);
			}
			nextByReplayEmission.set(replayCursorKey, replayNext + 1);
			if (replay.emissionId == primaryEmission) {
				var globalNext = nextByBaseKey.get(baseKey);
				if (globalNext == null)
					globalNext = 0;
				if (globalNext != replayNext)
					return null;
				nextByBaseKey.set(baseKey, globalNext + 1);
				var primaryCount = consumedByKey.get(replayed.key);
				consumedByKey.set(replayed.key, primaryCount == null ? 1 : primaryCount + 1);
			} else {
				var replayCount = replayUsesByKey.get(replayed.key);
				replayUsesByKey.set(replayed.key, replayCount == null ? 1 : replayCount + 1);
			}
			return replayed;
		}
		var next = nextByBaseKey.get(baseKey);
		if (next == null)
			next = 0;
		if (next >= bucket.length)
			return null;
		var crossing = bucket[next];
		if (crossing.replayFamily != null)
			return null;
		nextByBaseKey.set(baseKey, next + 1);
		var count = consumedByKey.get(crossing.key);
		consumedByKey.set(crossing.key, count == null ? 1 : count + 1);
		return crossing;
	}

	public function countFor(crossing:RustSavedRepresentationCrossing):Int {
		if (crossing == null)
			throw "A saved Dynamic crossing is required to read its use count";
		var count = consumedByKey.get(crossing.key);
		return count == null ? 0 : count;
	}

	public function replayCountFor(crossing:RustSavedRepresentationCrossing):Int {
		if (crossing == null)
			throw "A saved Dynamic crossing is required to read its replay count";
		var count = replayUsesByKey.get(crossing.key);
		return count == null ? 0 : count;
	}

	public function countProblems():Array<RustSavedCrossingCountProblem> {
		var problems:Array<RustSavedCrossingCountProblem> = [];
		for (crossing in saved) {
			var count = countFor(crossing);
			if (count != 1)
				problems.push({crossing: crossing, count: count});
		}
		return problems;
	}

	static inline function compare(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);

	static function compareCrossings(left:RustSavedRepresentationCrossing, right:RustSavedRepresentationCrossing):Int {
		var byBase = compare(left.baseKey, right.baseKey);
		return byBase != 0 ? byBase : left.ordinal - right.ordinal;
	}
}

/**
	A narrow record that the complete typed scan covered one runtime-related module family.

	Why / What / How
	- A decision about one value must not hide every unrelated module that happens to use the same
	  runtime reason. At the same time, a complete typed scan should not report duplicate broad rows for
	  compiler-generated carrier modules that belong to that exact value or call.
	- Each record pairs one reason with either one exact module or a reviewed descendant prefix. There is
	  no reason-only "everything is covered" state.
	- `RuntimeRequirementAnalyzer` accepts these records only from the complete compiler snapshot. Direct
	  callers that provide a partial decision array but no matching coverage record keep all broad
	  fallbacks.
**/
@:allow(reflaxe.rust.analyze.RepresentationDecisionAnalyzer)
class RustRuntimeRequirementCoverage {
	public final reasonKind:RustRuntimeRequirementKind;
	public final modulePath:String;
	public final includeDescendants:Bool;

	private function new(reasonKind:RustRuntimeRequirementKind, modulePath:String, includeDescendants:Bool) {
		this.reasonKind = reasonKind;
		this.modulePath = modulePath;
		this.includeDescendants = includeDescendants;
	}

	private static function exact(reasonKind:RustRuntimeRequirementKind, modulePath:String):RustRuntimeRequirementCoverage {
		return validated(reasonKind, modulePath, false);
	}

	private static function family(reasonKind:RustRuntimeRequirementKind, modulePath:String):RustRuntimeRequirementCoverage {
		return validated(reasonKind, modulePath, true);
	}

	static function validated(reasonKind:RustRuntimeRequirementKind, modulePath:String, includeDescendants:Bool):RustRuntimeRequirementCoverage {
		if (reasonKind == null || modulePath == null || modulePath.length == 0 || ~/[^A-Za-z0-9_.]/.match(modulePath))
			throw "Runtime requirement coverage needs a typed reason and safe module path";
		return new RustRuntimeRequirementCoverage(reasonKind, modulePath, includeDescendants);
	}

	public function covers(reasonKind:RustRuntimeRequirementKind, candidate:String):Bool {
		if (this.reasonKind != reasonKind || candidate == null)
			return false;
		return candidate == modulePath || includeDescendants && StringTools.startsWith(candidate, modulePath + ".");
	}

	public function canonicalKey():String {
		return reasonKind.id() + "\u0000" + modulePath + "\u0000" + (includeDescendants ? "family" : "exact");
	}
}

/**
	Owns the complete, immutable result of the early representation scan.

	Why / What / How
	- Haxe's after-typing callback still has complete method bodies, while later Rust construction may
	  no longer have the source expression needed to make an exact boundary decision.
	- This snapshot keeps only three small outputs: value decisions for reports, exact Dynamic actions
	  for lowering, and exact module coverage records for broad runtime fallbacks. It does not retain or
	  copy the complete typed Haxe tree.
	- Construction defensively copies and sorts every array, rejects duplicate keys, and validates the
	  saved-action sequence. Consumers receive copies so no later phase can rewrite the saved answer.
**/
class RustRepresentationAnalysisSnapshot {
	final savedDecisions:Array<RustRepresentationDecision>;
	final savedCrossings:Array<RustSavedRepresentationCrossing>;
	final savedCoverage:Array<RustRuntimeRequirementCoverage>;

	private function new(decisions:Array<RustRepresentationDecision>, crossings:Array<RustSavedRepresentationCrossing>,
			coverage:Array<RustRuntimeRequirementCoverage>) {
		this.savedDecisions = decisions;
		this.savedCrossings = crossings;
		this.savedCoverage = coverage;
	}

	public static function of(decisions:Array<RustRepresentationDecision>, crossings:Array<RustSavedRepresentationCrossing>,
			coverage:Array<RustRuntimeRequirementCoverage>):RustRepresentationAnalysisSnapshot {
		if (decisions == null || crossings == null || coverage == null)
			throw "Representation analysis snapshot arrays cannot be null";
		var decisionCopy = decisions.copy();
		var crossingCopy = crossings.copy();
		var coverageCopy = coverage.copy();
		decisionCopy.sort((left, right) -> compare(left.canonicalKey(), right.canonicalKey()));
		crossingCopy.sort(compareCrossings);
		coverageCopy.sort((left, right) -> compare(left.canonicalKey(), right.canonicalKey()));
		requireUnique([for (value in crossingCopy) value.key], "saved Dynamic crossing");
		requireUnique([for (value in coverageCopy) value.canonicalKey()], "runtime module coverage");
		RustSavedCrossingTracker.of(crossingCopy);
		return new RustRepresentationAnalysisSnapshot(decisionCopy, crossingCopy, coverageCopy);
	}

	public inline function decisions():Array<RustRepresentationDecision>
		return savedDecisions.copy();

	public inline function crossings():Array<RustSavedRepresentationCrossing>
		return savedCrossings.copy();

	public inline function coverage():Array<RustRuntimeRequirementCoverage>
		return savedCoverage.copy();

	static function requireUnique(keys:Array<String>, label:String):Void {
		for (index in 1...keys.length)
			if (keys[index] == keys[index - 1])
				throw 'Duplicate $label key `${keys[index]}`';
	}

	static inline function compare(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);

	static function compareCrossings(left:RustSavedRepresentationCrossing, right:RustSavedRepresentationCrossing):Int {
		var byBase = compare(left.baseKey, right.baseKey);
		return byBase != 0 ? byBase : left.ordinal - right.ordinal;
	}
}
