#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustBoundaryKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.NoHxrtEligibilityAnalyzer;
import reflaxe.rust.analyze.BorrowRegionAnalyzer;
import reflaxe.rust.analyze.RepresentationDecisionAnalyzer;
import reflaxe.rust.analyze.RepresentationTypeAnalyzer;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeRequirementEntry;
import reflaxe.rust.analyze.TypedExprReplayFamily;
import reflaxe.rust.analyze.TypedCallableTarget;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustDynamicValueMaterialization;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustSavedCrossingTracker;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustSavedRepresentationCrossing;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustSavedCrossingReplayContext;

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
@:access(reflaxe.rust.analyze.RepresentationTypeAnalyzer)
class RustRepresentationTypeContractMacro {
	public static macro function run():Expr {
		var borrowedHolder = Context.getType("RustRepresentationTypeFixture.RustRepresentationBorrowedHolder");
		var inventoryIdentity = RepresentationTypeAnalyzer.traversalIdentityFactory();
		var holderMono = Context.makeMonomorph();
		if (!Context.unify(holderMono, borrowedHolder))
			throw "borrowed-holder monomorph fixture must unify";
		if (RepresentationTypeAnalyzer.anonymousBorrowedField(holderMono) == null)
			throw "a bound TMono must not hide the complete anonymous borrowed-field shape";
		if (inventoryIdentity(holderMono) == inventoryIdentity(borrowedHolder))
			throw "inventory traversal must visit a bound TMono and its resolved child separately";
		var lazyHolder:Type = TLazy(() -> borrowedHolder);
		if (RepresentationTypeAnalyzer.anonymousBorrowedField(lazyHolder) == null)
			throw "a TLazy node must not hide the complete anonymous borrowed-field shape";
		if (inventoryIdentity(lazyHolder) == inventoryIdentity(borrowedHolder))
			throw "inventory traversal must visit a TLazy node and its resolved child separately";
		var classNamespace = Context.typeExpr(macro RustRepresentationTypeFixture).t;
		if (RepresentationTypeAnalyzer.anonymousBorrowedField(classNamespace) != null)
			throw "a class static namespace must not be treated as runtime anonymous-record storage";
		if (RepresentationTypeAnalyzer.classify(classNamespace, false) != RustSourceValueKind.SourceCoreHandle)
			throw "a class static namespace must retain the core type-handle representation";
		var growingType = switch (Context.getType("RustRepresentationTypeFixture.RustRepresentationParameterGrowing")) {
			case TType(typeRef, _): TType(typeRef, [Context.getType("Int")]);
			case _: throw "parameter-growing representation fixture must resolve to a typedef";
		};
		if (!RepresentationTypeAnalyzer.containsBorrowOnlyType(growingType))
			throw "parameter-growing recursive types must terminate conservatively instead of being treated as owned";
		var enumTarget = Context.typeExpr(macro RustRepresentationTypeFixture.RustRepresentationFixtureChoice.Payload);
		var castWrappedTarget:TypedExpr = {expr: TCast(enumTarget, null), t: enumTarget.t, pos: enumTarget.pos};
		var unwrappedTarget = TypedCallableTarget.transparent(castWrappedTarget);
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
		for (name in ["borrowed", "borrowedArrayShape"]) {
			var field = fields.get(name);
			if (field == null)
				throw 'missing transparent-node fixture field: $name';
			var mono = Context.makeMonomorph();
			if (!Context.unify(mono, field.type))
				throw '$name monomorph fixture must unify';
			if (RepresentationTypeAnalyzer.anonymousBorrowedFieldRejectionReason(mono) == null)
				throw 'a bound TMono must not hide the scoped borrow in $name';
			var lazyType:Type = TLazy(() -> field.type);
			if (RepresentationTypeAnalyzer.anonymousBorrowedFieldRejectionReason(lazyType) == null)
				throw 'a TLazy node must not hide the scoped borrow in $name';
		}

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
		var scalarTypeCheck = RepresentationTypeAnalyzer.tryDynamicCrossingTypeCheck(scalarField.type, Context.getType("Dynamic"), false);
		if (scalarTypeCheck == null)
			throw "the saved-action tracker contract needs a scalar source type check";
		for (name in ["borrowedNativeOwned", "borrowedPath"]) {
			var field = fields.get(name);
			var typeCheck = field == null ? null : RepresentationTypeAnalyzer.tryDynamicCrossingTypeCheck(field.type, Context.getType("Dynamic"), false);
			if (typeCheck == null || typeCheck.materialization != RustDynamicValueMaterialization.DynamicValueBorrowClone)
				throw '$name must materialize a known concrete Clone value behind rust.Ref before Dynamic storage';
		}
		var borrowedNativeHandle = fields.get("borrowedNativeHandle");
		if (borrowedNativeHandle == null
			|| RepresentationTypeAnalyzer.tryDynamicCrossingTypeCheck(borrowedNativeHandle.type, Context.getType("Dynamic"), false) != null)
			throw "rust.Ref<TcpStream> must stay unsupported because the native handle has no admitted Clone conversion";
		function rejects(label:String, operation:() -> Void):Void {
			var rejected = false;
			try operation() catch (_:Dynamic) rejected = true;
			if (!rejected)
				throw label;
		}
		var stringTypeCheck = RepresentationTypeAnalyzer.tryDynamicCrossingTypeCheck(stringField.type, Context.getType("Dynamic"), false);
		if (stringTypeCheck == null)
			throw "the saved-action mismatch contract needs a String source type check";
		rejects("a saved decision and source type check must describe the same owned value family",
			() -> RustSavedRepresentationCrossing.of(scalarOrigin, scalarBoundary, stringTypeCheck));
		var outsideBoundary = RustDecisionOrigin.at(scalarOrigin.sourceFile, scalarOrigin.startByte + 1, scalarOrigin.endByte - 1,
			scalarOrigin.modulePath);
		rejects("a saved action location must sit inside the complete source boundary",
			() -> RustSavedRepresentationCrossing.of(scalarOrigin, scalarBoundary, scalarTypeCheck, 0, outsideBoundary));
		var differentDecisionOrigin = RustDecisionOrigin.at(scalarOrigin.sourceFile, scalarOrigin.startByte + 1, scalarOrigin.endByte + 1,
			scalarOrigin.modulePath);
		var differentOriginDecision = RepresentationTypeAnalyzer.tryDecideCrossing("different-origin-boundary", scalarField.type,
			Context.getType("Dynamic"), scalarField.pos, differentDecisionOrigin, false);
		if (differentOriginDecision == null)
			throw "the saved-action origin contract needs a second valid scalar decision";
		rejects("a saved action and its representation decision must name the same exact source location",
			() -> RustSavedRepresentationCrossing.of(scalarOrigin, differentOriginDecision, scalarTypeCheck));
		var savedScalar = RustSavedRepresentationCrossing.of(scalarOrigin, scalarBoundary, scalarTypeCheck);
		var tracker = RustSavedCrossingTracker.of([savedScalar]);
		if (tracker.consume(scalarOrigin, stringTypeCheck) != null || tracker.countProblems()[0].count != 0)
			throw "lowering must reject a saved action whose source type check differs from the actual typed value";
		var missingOrigin = RustDecisionOrigin.at(scalarOrigin.sourceFile, scalarOrigin.startByte + 1, scalarOrigin.endByte + 1, scalarOrigin.modulePath);
		if (tracker.consume(missingOrigin, scalarTypeCheck) != null)
			throw "a missing saved action must not be replaced by a lowering-time decision";
		var missingProblems = tracker.countProblems();
		if (missingProblems.length != 1 || missingProblems[0].count != 0)
			throw "a deleted or unused saved action must fail the final consumption check";
		if (tracker.consume(scalarOrigin, scalarTypeCheck) != savedScalar || tracker.countProblems().length != 0)
			throw "one exact saved-action use must satisfy the final consumption check";
		if (tracker.consume(scalarOrigin, scalarTypeCheck) != null)
			throw "using more actions than early analysis saved must fail immediately";
		var savedScalarSecond = RustSavedRepresentationCrossing.of(scalarOrigin, scalarBoundary, scalarTypeCheck, 1);
		var sameSpanTracker = RustSavedCrossingTracker.of([savedScalar, savedScalarSecond]);
		if (sameSpanTracker.consume(scalarOrigin, scalarTypeCheck) != savedScalar
			|| sameSpanTracker.consume(scalarOrigin, scalarTypeCheck) != savedScalarSecond
			|| sameSpanTracker.countProblems().length != 0)
			throw "several macro-generated actions at one source span must be consumed in saved order";
		var replayFamily = TypedExprReplayFamily.constructorBody(fixture);
		var wrongReplayFamily = TypedExprReplayFamily.constructorDefault(fixture, 0);
		var savedReplay = RustSavedRepresentationCrossing.of(scalarOrigin, scalarBoundary, scalarTypeCheck, 0, scalarOrigin, replayFamily);
		rejects("a saved replay family must reject a missing declaration owner", () -> TypedExprReplayFamily.constructorBody(null));
		var replayTracker = RustSavedCrossingTracker.of([savedReplay]);
		var firstReplay = RustSavedCrossingReplayContext.of(replayFamily, "call:a");
		var secondReplay = RustSavedCrossingReplayContext.of(replayFamily, "call:b");
		var wrongReplay = RustSavedCrossingReplayContext.of(wrongReplayFamily, "call:a");
		if (replayTracker.consume(scalarOrigin, scalarTypeCheck) != null
			|| replayTracker.consume(scalarOrigin, scalarTypeCheck, wrongReplay) != null)
			throw "a replayable action must reject ordinary use and the wrong source definition family";
		if (replayTracker.consume(scalarOrigin, scalarTypeCheck, firstReplay) != savedReplay
			|| replayTracker.consume(scalarOrigin, scalarTypeCheck, secondReplay) != savedReplay
			|| replayTracker.countProblems().length != 0 || replayTracker.replayCountFor(savedReplay) != 1)
			throw "one saved default action must support explicit distinct generated callsite replays without becoming multiply consumed";
		if (replayTracker.consume(scalarOrigin, scalarTypeCheck, secondReplay) != null)
			throw "one generated replay site must not consume the same saved action twice";
		var ordinaryReplayTracker = RustSavedCrossingTracker.of([savedScalar]);
		if (ordinaryReplayTracker.consume(scalarOrigin, scalarTypeCheck, firstReplay) != null)
			throw "an ordinary saved action must reject an invented replay context";

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
			var constructorAnalysisModule:Array<ModuleType> = switch (Context.getType("RustRepresentationTypeFixture.RustConstructorAnalysisFixture")) {
				case TInst(classRef, _): [TClassDecl(classRef)];
				case _: throw "constructor analysis fixture must resolve to a class";
			};
			var constructorBorrowErrors = BorrowRegionAnalyzer.analyze(constructorAnalysisModule, _ -> true).errors;
			var constructorBorrowMessages = [for (error in constructorBorrowErrors) error.message];
			if (!Lambda.exists(constructorBorrowMessages, message -> message.indexOf("stored borrow-only alias") >= 0)
				|| !Lambda.exists(constructorBorrowMessages, message -> message.indexOf("stored closure captures borrow-only alias") >= 0))
				throw "constructor bodies must retain direct-storage and captured-closure borrow escapes in the complete early scan";
			var constructorField = switch (constructorAnalysisModule[0]) {
				case TClassDecl(classRef): classRef.get().constructor.get();
				case _: null;
			};
			if (constructorField == null)
				throw "constructor analysis fixture must retain its constructor field";
			var constructorExpression = constructorField.expr();
			if (constructorExpression == null)
				throw "constructor analysis fixture must retain its typed constructor body";
			var constructorPos = Context.getPosInfos(constructorExpression.pos);
			for (error in constructorBorrowErrors) {
				var errorPos = Context.getPosInfos(error.pos);
				if (errorPos.file != constructorPos.file || errorPos.min < constructorPos.min || errorPos.max > constructorPos.max
					|| errorPos.min == constructorPos.min && errorPos.max == constructorPos.max)
					throw "constructor-only borrow errors must point inside the exact failing expression rather than at the declaration";
			}
			var constructorOperations = NoHxrtEligibilityAnalyzer.captureOperationEntries(constructorAnalysisModule);
			var constructorOperationKinds:Map<String, Bool> = [];
			var constructorOperationSpans:Map<String, Bool> = [];
			for (entry in constructorOperations)
				if (entry.sourceKind == "typed_ast" && entry.sourceSpan != null && entry.sourceSpan.length > 0) {
					constructorOperationKinds.set(entry.reasonKind.id(), true);
					constructorOperationSpans.set(entry.sourceSpan, true);
				}
			if (!constructorOperationKinds.exists("platform_abstraction") || !constructorOperationKinds.exists("exception")
				|| !constructorOperationKinds.exists("reflection"))
				throw "constructor bodies must retain exact platform, exception, and reflection operation facts";
			var constructorSpanCount = 0;
			for (_ in constructorOperationSpans.keys())
				constructorSpanCount++;
			if (constructorSpanCount < 4)
				throw "constructor operations must retain distinct exact call, throw, and try/catch source ranges";
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
			var rightAnonymousSiblingDecision = false;
			for (decision in collected)
				if (decision.sourceKind == RustSourceValueKind.SourceDynamic
					&& decision.subjectId.indexOf("field-anonymousSiblings-type-1-type-0") >= 0)
					rightAnonymousSiblingDecision = true;
			if (!rightAnonymousSiblingDecision)
				throw "an owned anonymous sibling must not hide a later sibling's Dynamic field";
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
