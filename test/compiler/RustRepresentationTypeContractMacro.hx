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

/**
	Compile-time contract for extracting representation facts from real typed Haxe values.

	Why / What / How
	- Hand-constructed planner facts cannot prove that production Haxe types reach the same decision.
	- This macro loads one field for every supported value family and asks the shared analyzer for its
	  local representation decision.
	- The JavaScript harness compares the deterministic rows and then production lowering consumes the
	  same analyzer, so classifier drift fails before it changes generated Rust.
**/
class RustRepresentationTypeContractMacro {
	public static macro function run():Expr {
		var fixture = switch (Context.getType("RustRepresentationTypeFixture")) {
			case TInst(classRef, _): classRef.get();
			case _: throw "representation type fixture must resolve to a class";
		};
		var expected = [
			"scalar", "enumValue", "nativeOwned", "sharedIdentity", "polymorphic", "borrowed", "nullableBorrowed", "nativeHandle", "dynamicValue", "stringValue",
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
			var collected = RepresentationDecisionAnalyzer.collect(fixtureModule, false);
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
			for (label in ["call-argument", "constructor-argument", "local-initializer", "assignment", "return", "cast"])
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
}
#end
