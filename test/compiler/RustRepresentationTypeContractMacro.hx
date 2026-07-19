#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustBoundaryKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.NoHxrtEligibilityAnalyzer;
import reflaxe.rust.analyze.RepresentationDecisionAnalyzer;
import reflaxe.rust.analyze.RepresentationTypeAnalyzer;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeRequirementEntry;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustDynamicValueMaterialization;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustSavedCrossingTracker;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustSavedRepresentationCrossing;

/**
	Compile-time contract for extracting representation facts from real typed Haxe values.

	Why / What / How
	- Hand-constructed planner facts cannot prove that production Haxe types reach the same decision.
	- This macro loads one field for every supported value family and asks the shared analyzer for its
	  local representation decision.
	- The JavaScript harness compares the deterministic rows and then production lowering consumes the
	  same analyzer, so classifier drift fails before it changes generated Rust.
**/
@:access(reflaxe.rust.analyze.NoHxrtEligibilityAnalyzer)
@:access(reflaxe.rust.analyze.RepresentationDecisionAnalyzer)
class RustRepresentationTypeContractMacro {
	public static macro function run():Expr {
		var enumTarget = Context.typeExpr(macro RustRepresentationTypeFixture.RustRepresentationFixtureChoice.Payload);
		var castWrappedTarget:TypedExpr = {expr: TCast(enumTarget, null), t: enumTarget.t, pos: enumTarget.pos};
		var unwrappedTarget = RepresentationDecisionAnalyzer.transparentCallableTarget(castWrappedTarget);
		switch (unwrappedTarget.expr) {
			case TField(_, FEnum(_, _)):
			case _:
				throw "a transparent typed cast must retain immediate enum-constructor call-target suppression";
		}
		var fixture = switch (Context.getType("RustRepresentationTypeFixture")) {
			case TInst(classRef, _): classRef.get();
			case _: throw "representation type fixture must resolve to a class";
		};
		var expected = [
			"scalar", "enumValue", "nativeOwned", "sharedIdentity", "polymorphic", "borrowed", "nullableBorrowed", "nativeHandle", "dynamicValue", "classHandle",
			"enumHandle", "stringValue",
			"arrayValue", "anonymousValue", "functionValue", "iteratorValue", "nullableValue", "mapValue"
		];
		var fields:Map<String, ClassField> = [];
		var decisions:Map<String, reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision> = [];
		for (field in fixture.statics.get())
			fields.set(field.name, field);

		var rows:Array<String> = [];
		for (name in expected) {
			var field = fields.get(name);
			if (field == null)
				throw 'missing representation fixture field: $name';
			var info = Context.getPosInfos(field.pos);
			var origin = RustDecisionOrigin.at("test/compiler/RustRepresentationTypeFixture.hx", info.min, info.max,
				"RustRepresentationTypeFixture");
			var decision = RepresentationTypeAnalyzer.decide(name, field.type, field.pos, origin, false);
			decisions.set(name, decision);
			rows.push(row(name, decision));
		}

		var stringField = fields.get("stringValue");
		var stringInfo = Context.getPosInfos(stringField.pos);
		var runtimeString = RepresentationTypeAnalyzer.decide("runtimeString", stringField.type, stringField.pos,
			RustDecisionOrigin.at("test/compiler/RustRepresentationTypeFixture.hx", stringInfo.min, stringInfo.max,
				"RustRepresentationTypeFixture"),
			true);
		rows.push(row("runtimeString", runtimeString));

		var scalarField = fields.get("scalar");
		var scalarInfo = Context.getPosInfos(scalarField.pos);
		var scalarOrigin = RustDecisionOrigin.at("test/compiler/RustRepresentationTypeFixture.hx", scalarInfo.min, scalarInfo.max,
			"RustRepresentationTypeFixture");
		var scalarBoundary = RepresentationTypeAnalyzer.tryDecideCrossing("saved-scalar-boundary", scalarField.type, Context.getType("Dynamic"),
			scalarField.pos, scalarOrigin, false);
		if (scalarBoundary == null)
			throw "the saved-action tracker contract needs a scalar Dynamic boundary";
		var savedScalar = RustSavedRepresentationCrossing.of(scalarOrigin, scalarBoundary, RustDynamicValueMaterialization.DynamicValueDirect);
		var tracker = RustSavedCrossingTracker.of([savedScalar]);
		var missingOrigin = RustDecisionOrigin.at(scalarOrigin.sourceFile, scalarOrigin.startByte + 1, scalarOrigin.endByte + 1, scalarOrigin.modulePath);
		if (tracker.consume(missingOrigin) != null)
			throw "a missing saved action must not be replaced by a lowering-time decision";
		var missingProblems = tracker.countProblems();
		if (missingProblems.length != 1 || missingProblems[0].count != 0)
			throw "a deleted or unused saved action must fail the final consumption check";
		if (tracker.consume(scalarOrigin) != savedScalar || tracker.countProblems().length != 0)
			throw "one exact saved-action use must satisfy the final consumption check";
		if (tracker.consume(scalarOrigin) != null)
			throw "using more actions than early analysis saved must fail immediately";
		var savedScalarSecond = RustSavedRepresentationCrossing.of(scalarOrigin, scalarBoundary,
			RustDynamicValueMaterialization.DynamicValueDirect, 1);
		var sameSpanTracker = RustSavedCrossingTracker.of([savedScalar, savedScalarSecond]);
		if (sameSpanTracker.consume(scalarOrigin) != savedScalar
			|| sameSpanTracker.consume(scalarOrigin) != savedScalarSecond
			|| sameSpanTracker.countProblems().length != 0)
			throw "several macro-generated actions at one source span must be consumed in saved order";

		Sys.println(rows.join("\n"));
		Sys.println("function-runtime-v4|" + runtimeDecisionReasonIds(decisions.get("functionValue")));
		Sys.println("iterator-runtime-v4|" + runtimeDecisionReasonIds(decisions.get("iteratorValue")));
		var fixtureModule:Array<ModuleType> = [];
		switch (Context.getType("RustRepresentationTypeFixture")) {
			case TInst(classRef, _): fixtureModule.push(TClassDecl(classRef));
			case _: throw "representation type fixture must resolve to a module class";
		}
		switch (Context.getType("RustRepresentationTypeFixture.RustRepresentationFixtureChoice")) {
			case TEnum(enumRef, _): fixtureModule.push(TEnumDecl(enumRef));
			case _: throw "representation enum fixture must resolve to an enum";
		}
		var inspectedAfterTyping = false;
		Context.onAfterTyping(_ -> {
			if (inspectedAfterTyping)
				return;
			inspectedAfterTyping = true;
			var snapshot = RepresentationDecisionAnalyzer.collectSnapshot(fixtureModule, false);
			var collected = snapshot.decisions();
			function literalPosition(root:TypedExpr, expectedValue:Int):haxe.macro.Expr.Position {
				var found:Null<haxe.macro.Expr.Position> = null;
				function visit(expression:TypedExpr):Void {
					if (expression == null || found != null)
						return;
					switch (expression.expr) {
						case TConst(TInt(value)) if (value == expectedValue):
							found = expression.pos;
						case _:
							haxe.macro.TypedExprTools.iter(expression, visit);
					}
				}
				visit(root);
				if (found == null)
					throw 'missing typed literal $expectedValue in representation fixture';
				return found;
			}
			function requiresSavedActionAt(pos:haxe.macro.Expr.Position, label:String):Void {
				var info = Context.getPosInfos(pos);
				for (crossing in snapshot.crossings())
					if (crossing.origin.startByte == info.min && crossing.origin.endByte == info.max)
						return;
				throw '$label must contribute a saved Dynamic action before lowering';
			}
			var constructorRef = fixture.constructor;
			var constructorField = constructorRef == null ? null : constructorRef.get();
			var constructorExpr = constructorField == null ? null : constructorField.expr();
			if (constructorExpr == null)
				throw "representation fixture constructor body must be typed";
			requiresSavedActionAt(literalPosition(constructorExpr, 424242), "a constructor-body crossing");
			var methodDynamicDecisions = 0;
			for (decision in collected) {
				if (decision.sourceKind == RustSourceValueKind.SourceDynamic
					&& decision.subjectId.indexOf("consumeDynamic-parameter-0") >= 0)
					methodDynamicDecisions++;
			}
			if (methodDynamicDecisions != 1)
				throw 'method parameter representation must be collected once, got $methodDynamicDecisions';
			var nestedDynamicDecision = false;
			for (decision in collected) {
				if (decision.sourceKind == RustSourceValueKind.SourceDynamic
					&& decision.subjectId.indexOf("field-nativeOwnedDynamic-type-0") >= 0)
					nestedDynamicDecision = true;
			}
			if (!nestedDynamicDecision)
				throw "nested dynamic storage must retain its own representation decision";
			var enumPayloadDecision = false;
			for (decision in collected) {
				if (decision.sourceKind == RustSourceValueKind.SourceDynamic
					&& decision.subjectId.indexOf("enum-Payload-parameter-0") >= 0)
					enumPayloadDecision = true;
			}
			if (!enumPayloadDecision)
				throw "enum payload storage must retain its own representation decision";
			var dynamicBoundaryDecisions = [for (decision in collected) if (decision.boundary == RustBoundaryKind.BoundaryDynamic) decision];
			var dynamicBoundarySubjects = dynamicBoundaryDecisions.map(decision -> decision.subjectId).join("\n");
			for (label in ["call-argument", "constructor-argument", "local-initializer", "assignment", "return"])
				if (dynamicBoundarySubjects.indexOf(label) < 0)
					throw 'runtime-boundary extraction must cover the $label case';
			var boundaryKinds:Map<String, Bool> = [];
			for (decision in dynamicBoundaryDecisions) {
				boundaryKinds.set(decision.sourceKind.id(), true);
				if (decision.runtimeRequirements().map(reason -> reason.id()).indexOf("dynamic") < 0)
					throw "every runtime boundary must carry the planner's matching runtime reason";
			}
			for (kind in ["scalar", "class_reference", "enum_value"])
				if (!boundaryKinds.exists(kind))
					throw 'runtime-boundary extraction must retain the $kind source family';
			var leakedBorrowBoundary = false;
			for (decision in dynamicBoundaryDecisions)
				if (decision.subjectId.indexOf("call-argument") >= 0 && decision.sourceKind == RustSourceValueKind.SourceBorrowedRef)
					leakedBorrowBoundary = true;
			if (leakedBorrowBoundary)
				throw "a runtime crossing must describe the copied value behind rust.Ref, not the borrow token";
			var nestedDecisions = [for (decision in collected) if (decision.subjectId.indexOf("field-nativeOwnedDynamic") >= 0) decision];
			var nestedRequirements = RuntimeRequirementAnalyzer.collect([], true, false, false, false, nestedDecisions, true);
			var nestedSummary = RuntimeRequirementAnalyzer.summarize(nestedRequirements);
			if (!nestedSummary.blockedByNoHxrt || reasonIds(nestedSummary.reasonKinds.map(reason -> reason.id())) != "dynamic")
				throw "nested dynamic storage must fail the no-hxrt semantic gate";
			var runtimeRequirements = RuntimeRequirementAnalyzer.collect([], false, false, false, false, collected, false);
			Sys.println("runtime-v4|" + reasonIds(runtimeRequirements.map(entry -> entry.reasonKind.id())));
			var noHxrt = NoHxrtEligibilityAnalyzer.analyze(fixtureModule, [], false, false, false);
			Sys.println("no-hxrt|" + reasonIds(noHxrt.summary.reasonKinds.map(reason -> reason.id())));

			var exactSys:RuntimeRequirementEntry = {
				reasonKind: RuntimePlatformAbstraction,
				sourceKind: "typed_ast",
				sourceModule: "Main",
				sourceSpan: "Main.hx:10-20",
				surfaceId: null,
				requiresHxrt: true,
				noHxrtBlocked: true,
				message: "exact Sys operation"
			};
			var capturedRequirements = [exactSys];
			var capturedSummary = RuntimeRequirementAnalyzer.summarize(capturedRequirements);
			var merged = NoHxrtEligibilityAnalyzer.mergeCaptured({
				blocked: capturedSummary.blockedByNoHxrt,
				requirements: capturedRequirements,
				summary: capturedSummary
			}, ["DateTools", "rust.concurrent.Mutexes"], false, false, false, [], []);
			if (!hasModuleRequirement(merged.requirements, RuntimePlatformAbstraction, "DateTools"))
				throw "an exact Sys operation must not hide an independent later DateTools dependency";
			if (!hasModuleRequirement(merged.requirements, RuntimePlatformAbstraction, "rust.concurrent.Mutexes"))
				throw "an exact Sys operation must not hide an independent later rust.concurrent dependency";
			var reversed = NoHxrtEligibilityAnalyzer.mergeCaptured({
				blocked: capturedSummary.blockedByNoHxrt,
				requirements: capturedRequirements,
				summary: capturedSummary
			}, ["rust.concurrent.Mutexes", "DateTools"], false, false, false, [], []);
			if (requirementRows(merged.requirements) != requirementRows(reversed.requirements))
				throw "later no-hxrt module input order must not change the merged result";
			var repeated = NoHxrtEligibilityAnalyzer.mergeCaptured(merged, ["DateTools", "rust.concurrent.Mutexes"], false, false, false, [], []);
			if (requirementRows(merged.requirements) != requirementRows(repeated.requirements))
				throw "repeating the no-hxrt merge must not duplicate or remove requirements";
		});
		return macro null;
	}

	static function runtimeDecisionReasonIds(decision:reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision):String {
		var entries = RuntimeRequirementAnalyzer.collect([], false, false, false, false, [decision], false);
		return reasonIds(entries.map(entry -> entry.reasonKind.id()));
	}

	static function row(name:String, decision:reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision):String {
		return [
			name,
			decision.sourceKind.id(),
			decision.representation.id(),
			decision.nullEncoding.id(),
			decision.reuse.id(),
			decision.reason.id(),
			decision.runtimeRequirements().map(reason -> reason.id()).join(",")
		].join("|");
	}

	static function reasonIds(values:Array<String>):String {
		var seen:Map<String, Bool> = [];
		var out:Array<String> = [];
		for (value in values) {
			if (!seen.exists(value)) {
				seen.set(value, true);
				out.push(value);
			}
		}
		out.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		return out.join(",");
	}

	static function hasModuleRequirement(entries:Array<RuntimeRequirementEntry>, reason:reflaxe.rust.analyze.RepresentationPlan.RustRuntimeRequirementKind,
			module:String):Bool {
		for (entry in entries)
			if (entry.reasonKind == reason && entry.sourceKind == "module" && entry.sourceModule == module && entry.sourceSpan.length == 0)
				return true;
		return false;
	}

	static function requirementRows(entries:Array<RuntimeRequirementEntry>):String {
		return [for (entry in entries)
			entry.reasonKind.id() + "|" + entry.sourceKind + "|" + entry.sourceModule + "|" + entry.sourceSpan + "|" + entry.message].join("\n");
	}
}
#end
