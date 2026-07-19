package reflaxe.rust.analyze;

import reflaxe.rust.analyze.RepresentationPlan.RustBoundaryKind;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationPlan.RustRuntimeRequirementKind;

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
	One saved Dynamic-boxing action consumed later by Rust lowering.

	Why / What / How
	- Recording a runtime requirement is not enough to show that the later Rust box used the same saved
	  compiler decision.
	- This record joins the decision to the exact expression bytes that emit one box and records the
	  required borrowed-value conversion. Contextual `if`/`switch` results may have one report decision
	  but several branch-level actions, all pointing back to that decision.
	- The stable key contains only private source identity, byte range, module, boundary kind, and a
	  zero-based action number for macros that create several boxes at one span. It survives the gap
	  between Haxe's after-typing callback and Rust AST construction without retaining the complete
	  typed module graph.
**/
class RustSavedRepresentationCrossing {
	public final key:String;
	public final baseKey:String;
	public final ordinal:Int;
	public final origin:RustDecisionOrigin;
	public final decision:RustRepresentationDecision;
	public final materialization:RustDynamicValueMaterialization;

	private function new(origin:RustDecisionOrigin, decision:RustRepresentationDecision, materialization:RustDynamicValueMaterialization, ordinal:Int) {
		this.origin = origin;
		this.decision = decision;
		this.materialization = materialization;
		this.ordinal = ordinal;
		this.baseKey = baseKeyFor(origin);
		this.key = baseKey + "\u0000" + ordinal;
	}

	public static function of(origin:RustDecisionOrigin, decision:RustRepresentationDecision,
			materialization:RustDynamicValueMaterialization, ?ordinal:Int = 0):RustSavedRepresentationCrossing {
		if (origin == null || decision == null || materialization == null)
			throw "Saved representation crossings require an origin, decision, and materialization";
		if (decision.boundary != RustBoundaryKind.BoundaryDynamic)
			throw "Saved representation crossings currently admit only Dynamic boundaries";
		if (ordinal < 0)
			throw "Saved representation crossing action numbers cannot be negative";
		return new RustSavedRepresentationCrossing(origin, decision, materialization, ordinal);
	}

	public static function baseKeyFor(origin:RustDecisionOrigin):String {
		if (origin == null)
			throw "Saved representation crossing keys require an origin";
		return origin.modulePath + "\u0000" + origin.sourceFile + "\u0000" + origin.startByte + "\u0000" + origin.endByte + "\u0000dynamic";
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

	private function new(crossings:Array<RustSavedRepresentationCrossing>) {
		saved = crossings.copy();
		saved.sort(compareCrossings);
		savedByBaseKey = [];
		nextByBaseKey = [];
		consumedByKey = [];
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
	public function consume(origin:RustDecisionOrigin):Null<RustSavedRepresentationCrossing> {
		var baseKey = RustSavedRepresentationCrossing.baseKeyFor(origin);
		var bucket = savedByBaseKey.get(baseKey);
		if (bucket == null)
			return null;
		var next = nextByBaseKey.get(baseKey);
		if (next == null)
			next = 0;
		if (next >= bucket.length)
			return null;
		var crossing = bucket[next];
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
