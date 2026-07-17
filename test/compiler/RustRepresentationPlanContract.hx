import reflaxe.rust.analyze.RepresentationPlan.RustBoundaryKind;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustEscapeFact;
import reflaxe.rust.analyze.RepresentationPlan.RustIdentityFact;
import reflaxe.rust.analyze.RepresentationPlan.RustMutationFact;
import reflaxe.rust.analyze.RepresentationPlan.RustNullEncoding;
import reflaxe.rust.analyze.RepresentationPlan.RustNullabilityFact;
import reflaxe.rust.analyze.RepresentationPlan.RustOwnershipPolicy;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationFacts;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationKind;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationPlanSnapshot;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationPlanner;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationReason;
import reflaxe.rust.analyze.RepresentationPlan.RustRequiredBound;
import reflaxe.rust.analyze.RepresentationPlan.RustReusePolicy;
import reflaxe.rust.analyze.RepresentationPlan.RustRuntimeRequirementKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSurfaceFact;

class RustRepresentationPlanContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectThrows(action:() -> Void, message:String):Void {
		var threw = false;
		try {
			action();
		} catch (_:String) {
			threw = true;
		}
		expect(threw, message);
	}

	static function origin(subject:String, start:Int):RustDecisionOrigin {
		return RustDecisionOrigin.at("test/compiler/RustRepresentationPlanContract.hx", start, start + subject.length, "RustRepresentationPlanContract");
	}

	static function facts(subject:String, source:RustSourceValueKind, identity:RustIdentityFact, mutation:RustMutationFact, escape:RustEscapeFact,
			surface:RustSurfaceFact, nullability:RustNullabilityFact, boundary:RustBoundaryKind, start:Int):RustRepresentationFacts {
		return RustRepresentationFacts.of(subject, source, identity, mutation, escape, surface, nullability, boundary, origin(subject, start));
	}

	static function runtimeIds(values:Array<RustRuntimeRequirementKind>):String {
		return [for (value in values) value.id()].join(",");
	}

	static function boundIds(values:Array<RustRequiredBound>):String {
		return [for (value in values) value.id()].join(",");
	}

	static function main():Void {
		var classDecision = RustRepresentationPlanner.decide(facts("Main.Node", SourceClassReference, IdentityStable, MutationShared, EscapeMay,
			SurfacePortableHaxe, NonNullable, BoundaryLocal, 10));
		expect(classDecision.representation == RepresentationSharedIdentity, "class references need shared identity representation");
		expect(classDecision.ownership == OwnershipShared, "class references need shared ownership");
		expect(classDecision.reuse == ReuseCloneWhenNeeded, "shared handles clone only when source reuse requires it");
		expect(classDecision.reason == ReasonHaxeClassIdentity, "class identity needs one stable selection reason");
		expect(classDecision.nullEncoding == NullNotAdmitted, "a non-null class value must not silently admit null");
		expect(runtimeIds(classDecision.runtimeRequirements()) == "object_identity,reference_mutation",
			"class runtime reasons must be complete and canonical");
		expect(!classDecision.noHxrtEligible, "portable class identity is not a no-runtime value contract");

		var nativeDecision = RustRepresentationPlanner.decide(facts("Main.Native", SourceNativeOwned, IdentityNone, MutationOwned, EscapeMay,
			SurfaceRustNative, NonNullable, BoundaryLocal, 30));
		expect(nativeDecision.representation == RepresentationOwnedValue, "owned native values stay owned Rust values");
		expect(nativeDecision.ownership == OwnershipMove, "owned native values move by default");
		expect(nativeDecision.reuse == ReuseMoveOnce, "owned native values must not acquire an accidental Clone contract");
		expect(nativeDecision.runtimeRequirements().length == 0 && nativeDecision.requiredBounds().length == 0,
			"single-thread native values need neither hxrt nor global crossing bounds");
		expect(nativeDecision.noHxrtEligible, "owned native values are eligible for no-runtime lowering");

		var mutableBorrow = RustRepresentationPlanner.decide(facts("Main.MutableBorrow", SourceBorrowedMutRef, IdentityNone,
			MutationExclusiveBorrow, EscapeLocal, SurfaceRustNative, NonNullable, BoundaryLocal, 40));
		expect(mutableBorrow.representation == RepresentationBorrowedToken && mutableBorrow.ownership == OwnershipBorrowed,
			"an exclusive rust.MutRef remains one lexical borrowed token");

		var dynamicCrossing = RustRepresentationPlanner.decide(facts("Main.Payload", SourceNativeOwned, IdentityNone, MutationOwned, EscapeMay,
			SurfaceRustNative, NonNullable, BoundaryDynamic, 50));
		expect(boundIds(dynamicCrossing.requiredBounds()) == "clone,send,sync,static",
			"dynamic boxing must carry its exact Clone + Send + Sync + static boundary contract");
		expect(runtimeIds(dynamicCrossing.runtimeRequirements()) == "dynamic" && !dynamicCrossing.noHxrtEligible,
			"a dynamic boundary must record the runtime carrier even for a Rust-native source value");

		var threadCrossing = RustRepresentationPlanner.decide(facts("Main.ThreadValue", SourceNativeOwned, IdentityNone, MutationOwned, EscapeMay,
			SurfaceRustNative, NonNullable, BoundaryThread, 70));
		expect(boundIds(threadCrossing.requiredBounds()) == "send,static",
			"an owned thread value needs Send + static, not a global Sync or Clone bound");

		var staticStorage = RustRepresentationPlanner.decide(facts("Main.StaticValue", SourceNativeOwned, IdentityNone, MutationImmutable, EscapeMay,
			SurfaceRustNative, NonNullable, BoundaryStaticStorage, 80));
		expect(boundIds(staticStorage.requiredBounds()) == "sync,static",
			"shared static storage needs Sync + static without unrelated Clone or Send bounds");

		var nullableString = RustRepresentationPlanner.decide(facts("Main.Label", SourceNullableStringCompat, IdentityNone, MutationImmutable, EscapeMay,
			SurfacePortableHaxe, Nullable, BoundaryLocal, 90));
		expect(nullableString.representation == RepresentationRuntimeString, "nullable portable String needs its runtime carrier");
		expect(nullableString.nullEncoding == NullIntrinsic, "the runtime String carrier owns its null sentinel");
		expect(runtimeIds(nullableString.runtimeRequirements()) == "haxe_string_semantics,nullable_compat",
			"nullable strings need both semantic runtime reasons in canonical order");

		var nullableOwnedString = RustRepresentationPlanner.decide(facts("Main.OwnedLabel", SourceString, IdentityNone, MutationImmutable,
			EscapeMay, SurfacePortableHaxe, Nullable, BoundaryLocal, 100));
		expect(nullableOwnedString.representation == RepresentationOwnedValue && nullableOwnedString.nullEncoding == NullOuterOption,
			"the nullable owned String contract must use Option<String> instead of the Haxe runtime carrier");
		expect(nullableOwnedString.noHxrtEligible, "the nullable owned String contract must remain eligible for no-runtime lowering");

		var dynamicValue = RustRepresentationPlanner.decide(facts("Main.DynamicValue", SourceDynamic, IdentityNone, MutationShared, EscapeMay,
			SurfacePortableHaxe, Nullable, BoundaryLocal, 110));
		expect(dynamicValue.representation == RepresentationDynamicPayload, "dynamic needs its closed payload representation");
		expect(runtimeIds(dynamicValue.runtimeRequirements()) == "dynamic", "dynamic needs one stable runtime reason");

		var nullableScalar = RustRepresentationPlanner.decide(facts("Main.OptionalCount", SourceScalar, IdentityNone, MutationImmutable, EscapeMay,
			SurfacePortableHaxe, Nullable, BoundaryLocal, 125));
		expect(nullableScalar.nullEncoding == NullOuterOption, "nullable scalar values need one explicit outer Option decision");

		expectThrows(() -> facts("Main.BadBorrow", SourceBorrowedRef, IdentityNone, MutationImmutable, EscapeMay, SurfaceRustNative, NonNullable,
			BoundaryLocal, 130), "borrow tokens must not admit an escaping fact state");
		expectThrows(() -> facts("Main.BadImmutableBorrow", SourceBorrowedRef, IdentityNone, MutationExclusiveBorrow, EscapeLocal, SurfaceRustNative,
			NonNullable, BoundaryLocal, 140), "immutable borrow tokens must reject exclusive mutation facts");
		expectThrows(() -> facts("Main.BadMutableBorrow", SourceBorrowedMutRef, IdentityNone, MutationImmutable, EscapeLocal, SurfaceRustNative,
			NonNullable, BoundaryLocal, 145), "mutable borrow tokens must require exclusive mutation facts");
		expectThrows(() -> facts("Main.BadClass", SourceClassReference, IdentityNone, MutationShared, EscapeMay, SurfacePortableHaxe, NonNullable,
			BoundaryLocal, 150), "class references must require stable identity facts");
		expectThrows(() -> facts("Main.BadFacade", SourcePortableFacade, IdentityStable, MutationShared, EscapeMay, SurfacePortableFacade,
			NonNullable, BoundaryLocal, 155), "portable native facades must not claim Haxe reference identity");
		expectThrows(() -> facts("Main.BadNativeHandle", SourceNativeHandle, IdentityStable, MutationOwned, EscapeMay, SurfaceRustNative,
			NonNullable, BoundaryLocal, 160), "owned native handles must not claim alias-visible stable identity");
		expectThrows(() -> facts("Main.BadThreadLocal", SourceNativeOwned, IdentityNone, MutationOwned, EscapeLocal, SurfaceRustNative,
			NonNullable, BoundaryThread, 165), "thread crossings must reject a contradictory lexical-only escape fact");
		expectThrows(() -> RustDecisionOrigin.at("../private/Main.hx", 0, 1, "Main"), "source origins must reject traversal");
		expectThrows(() -> RustDecisionOrigin.at("C:private/Main.hx", 0, 1, "Main"), "source origins must reject drive-relative paths");
		expectThrows(() -> RustDecisionOrigin.at("test/compiler/Bad\tName.hx", 0, 1, "Main"),
			"source origins must reject control characters");
		expectThrows(() -> RustDecisionOrigin.at("test/compiler/Main.hx", 0, 1, "Main..Node"),
			"source origins must reject invalid Haxe module-path segments");
		expectThrows(() -> facts("Main.Bad\tSubject", SourceScalar, IdentityNone, MutationImmutable, EscapeLocal, SurfacePortableHaxe,
			NonNullable, BoundaryLocal, 170), "subject ids must reject control characters");
		expectThrows(() -> RustRepresentationReason.fromId("invented"), "reason decoding must fail closed");
		expectThrows(() -> RustRequiredBound.fromId("owned"), "bound decoding must fail closed");
		expect(RuntimeObjectIdentity.isRuntimePlanV4Reason(),
			"the generated policy adapter must admit v4-owned runtime reasons");
		expect(!RuntimeFunctionValue.isRuntimePlanV4Reason() && !RuntimeIteratorSemantics.isRuntimePlanV4Reason(),
			"the generated policy adapter must keep decision-v1-only reasons out of runtime-plan v4");

		var decisions = [nullableString, nullableOwnedString, nullableScalar, nativeDecision, mutableBorrow, classDecision, staticStorage, threadCrossing,
			dynamicCrossing, dynamicValue];
		var snapshot = RustRepresentationPlanSnapshot.of(decisions);
		decisions.reverse();
		expect(snapshot.at(0).subjectId == "Main.DynamicValue", "snapshot ordering must use a stable total key");
		expect(snapshot.decisionCount == 10, "snapshot must own a defensive decision-array copy");
		expectThrows(() -> RustRepresentationPlanSnapshot.of([classDecision, classDecision]), "duplicate decisions must fail closed");
		expectThrows(() -> RustRepresentationPlanSnapshot.requireCanonical([classDecision, nativeDecision]),
			"externally decoded decisions must already use canonical order");

		var leakedBounds = dynamicCrossing.requiredBounds();
		leakedBounds.pop();
		expect(dynamicCrossing.requiredBounds().length == 4, "decision bound arrays must be defensive copies");
		var leakedRuntime = classDecision.runtimeRequirements();
		leakedRuntime.pop();
		expect(classDecision.runtimeRequirements().length == 2, "decision runtime arrays must be defensive copies");

		Sys.println([
			classDecision.representation.id() + "|" + classDecision.ownership.id() + "|" + classDecision.reuse.id() + "|"
				+ runtimeIds(classDecision.runtimeRequirements()),
			nativeDecision.representation.id() + "|" + nativeDecision.ownership.id() + "|" + nativeDecision.reuse.id(),
			boundIds(dynamicCrossing.requiredBounds()),
			boundIds(threadCrossing.requiredBounds()),
			runtimeIds(nullableString.runtimeRequirements()),
			snapshot.renderJson()
		].join("\n"));
	}
}
