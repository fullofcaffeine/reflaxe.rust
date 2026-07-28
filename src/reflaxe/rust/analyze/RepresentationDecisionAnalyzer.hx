package reflaxe.rust.analyze;

import haxe.ds.ObjectMap;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.helpers.TypeHelper;
import reflaxe.rust.RustDiagnostic;
import reflaxe.rust.RustDiagnostic.RustDiagnosticId;
import reflaxe.rust.RustSourcePosition;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationPlan.RustRuntimeRequirementKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustRepresentationAnalysisSnapshot;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustRuntimeRequirementCoverage;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustSavedRepresentationCrossing;

using reflaxe.helpers.ClassFieldHelper;

/**
	Collects representation decisions from user-authored typed AST.

	Why
	- Runtime and no-hxrt analysis used to recognize arrays, dynamic values, and anonymous objects with
	  their own switches, independently from type lowering.
	- A module-path list cannot explain value-level identity, reuse, nullability, or the source span that
	  caused a runtime requirement.

	What
	- Visits executable field bodies plus declared value/parameter/return and enum-payload types, then asks
	  `RepresentationTypeAnalyzer` for every modeled family.
	- Adds one syntax-refined anonymous-object decision when Haxe has already coerced the literal's
	  result type to `Dynamic`.

	How
	- Field-root `TFunction` nodes describe methods, not first-class function values, so only their
	  parameters, result, and body are visited. Nested `TFunction` nodes remain real function values.
	- Origins retain exact byte offsets while absolute classpath filenames become stable logical paths.
	- Results are de-duplicated and sorted by the planner's canonical key.
**/
class RepresentationDecisionAnalyzer {
	public static function collect(moduleTypes:Array<ModuleType>, nullableStringCompat:Bool,
			?classHasSubclasses:ClassType->Bool):Array<RustRepresentationDecision> {
		return collectSnapshot(moduleTypes, nullableStringCompat, classHasSubclasses).decisions();
	}

	/**
		Collects the complete early representation snapshot consumed by later compiler phases.

		Why / What / How
		- Haxe still has complete method bodies at the after-typing callback, while Reflaxe may consume or
		  rewrite those bodies before Rust lowering and no-runtime checks run.
		- Save three small immutable views: user-facing representation decisions, exact Dynamic-boxing
		  actions, and narrowly scoped module-coverage facts.
		- Sort and defensively copy the result so reports, lowering, and no-runtime checks all start from the
		  same deterministic answer without retaining the full typed expression graph.
	**/
	public static function collectSnapshot(moduleTypes:Array<ModuleType>, nullableStringCompat:Bool,
			?classHasSubclasses:ClassType->Bool):RustRepresentationAnalysisSnapshot {
		var out:Array<RustRepresentationDecision> = [];
		var crossings:Array<RustSavedRepresentationCrossing> = [];
		var coverage:Array<RustRuntimeRequirementCoverage> = [];
		var seen:Map<String, Bool> = [];
		var crossingByExpression:ObjectMap<{}, RustSavedRepresentationCrossing> = new ObjectMap();
		var seenReplayDefinitions:Map<String, Bool> = [];
		var contextualFunctionReturnByExpression:ObjectMap<{}, Type> = new ObjectMap();
		var seenAnchoredCrossings:Map<String, Bool> = [];
		var nextCrossingOrdinal:Map<String, Int> = [];
		var seenCoverage:Map<String, Bool> = [];
		var currentReplayFamily:Null<TypedExprReplayFamily> = null;
		if (moduleTypes == null)
			return RustRepresentationAnalysisSnapshot.of(out, crossings, coverage);

		function replayFamilyId(family:Null<TypedExprReplayFamily>):String {
			return family == null ? "" : family.id;
		}

		function withReplayFamily(family:TypedExprReplayFamily, build:() -> Void):Void {
			if (family == null)
				throw "Repeated source analysis requires a typed source definition identity";
			var previous = currentReplayFamily;
			currentReplayFamily = family;
			build();
			currentReplayFamily = previous;
		}

		function addCoverage(value:RustRuntimeRequirementCoverage):Void {
			var key = value.canonicalKey();
			if (seenCoverage.exists(key))
				return;
			seenCoverage.set(key, true);
			coverage.push(value);
		}

		function addDecision(decision:Null<RustRepresentationDecision>):Void {
			if (decision == null)
				return;
			var key = decision.canonicalKey();
			if (seen.exists(key))
				return;
			seen.set(key, true);
			out.push(decision);
			for (reason in decision.runtimeRequirements()) {
				switch (reason) {
					case RustRuntimeRequirementKind.RuntimeDynamic:
						addCoverage(RustRuntimeRequirementCoverage.family(reason, "hxrt.dynamic"));
						if (decision.sourceKind == RustSourceValueKind.SourceDynamic)
							addCoverage(RustRuntimeRequirementCoverage.exact(reason, "Dynamic"));
					case RustRuntimeRequirementKind.RuntimeAnonymousObject:
						addCoverage(RustRuntimeRequirementCoverage.family(reason, "hxrt.anon"));
					case RustRuntimeRequirementKind.RuntimeHaxeArraySemantics:
						addCoverage(RustRuntimeRequirementCoverage.family(reason, "hxrt.array"));
					case RustRuntimeRequirementKind.RuntimeHaxeStringSemantics:
						addCoverage(RustRuntimeRequirementCoverage.family(reason, "hxrt.string"));
					case _:
				}
			}
		}

		function addType(modulePath:String, label:String, type:Type, pos:haxe.macro.Expr.Position):Void {
			if (type == null || pos == null)
				return;
			var origin = originAt(modulePath, pos);
			if (origin == null)
				return;
			var info = Context.getPosInfos(pos);
			var seenTypes:Map<String, Bool> = [];
			function visitType(current:Type, currentLabel:String):Void {
				if (current == null)
					return;
				var typeKey = TypeTools.toString(current);
				if (seenTypes.exists(typeKey))
					return;
				seenTypes.set(typeKey, true);
				var subject = modulePath + "#" + currentLabel + "@" + info.min + ":" + info.max;
				addDecision(RepresentationTypeAnalyzer.tryDecide(subject, current, pos, origin, nullableStringCompat, null, classHasSubclasses));
				var children = directTypeChildren(current);
				for (index in 0...children.length)
					visitType(children[index], currentLabel + "-type-" + index);
			}
			visitType(type, label);
		}

		function rejectAnonymousBorrowedShape(type:Type, value:TypedExpr):Bool {
			var field = RepresentationTypeAnalyzer.anonymousBorrowedField(type);
			if (field == null)
				return false;
			var reason = RepresentationTypeAnalyzer.anonymousBorrowedFieldRejectionReason(field.type);
			if (reason == null)
				return false;
			RustDiagnostic.error(RustDiagnosticId.BorrowRegion,
				'Rust borrow region violation: anonymous field `${field.name}` makes this runtime record shape unsafe. $reason', value.pos);
			return true;
		}

		function addCrossing(modulePath:String, label:String, actual:TypedExpr, expected:Type, ?relatedModulePath:String):Void {
			if (actual == null || expected == null)
				return;
			var actualCore = unwrapMetaParen(actual);
			switch (actualCore.expr) {
				case TFunction(_):
					switch (TypeTools.follow(expected)) {
						case TFun(_, expectedResult):
							contextualFunctionReturnByExpression.set(actualCore, expectedResult);
						case _:
					}
				case _:
			}
			var origin = originAt(modulePath, actual.pos);
			if (origin == null)
				return;
			var info = Context.getPosInfos(actual.pos);
			var subject = modulePath + "#" + label + "@" + info.min + ":" + info.max;
			var groupDecision = RepresentationTypeAnalyzer.tryDecideExprCrossing(subject, actual, expected, origin, nullableStringCompat, classHasSubclasses);

			function emissionSites(expression:TypedExpr):Array<TypedExpr> {
				var current = unwrapMetaParen(expression);
				if (RepresentationTypeAnalyzer.classify(current.t, nullableStringCompat, classHasSubclasses) == RustSourceValueKind.SourceDynamic) {
					return switch (current.expr) {
						case TIf(_, thenExpr, elseExpr) if (elseExpr != null):
							emissionSites(thenExpr).concat(emissionSites(elseExpr));
						case TSwitch(_, cases, defaultExpr):
							var sites:Array<TypedExpr> = [];
							for (entry in cases)
								sites = sites.concat(emissionSites(entry.expr));
							if (defaultExpr != null)
								sites = sites.concat(emissionSites(defaultExpr));
							sites;
						case TBlock(expressions) if (expressions.length > 0):
							emissionSites(expressions[expressions.length - 1]);
						case TCast(inner, _):
							emissionSites(inner);
						case _:
							[current];
					};
				}
				// Keep a concrete crossing anchored to its complete source expression. Haxe's later
				// optimizer can replace a parenthesized compound update with an `@:mergeBlock` whose
				// source range matches the wrapper, not the inner update. Dynamic control results remain
				// branch-specific above because lowering creates one runtime value per reachable branch.
				return [expression];
			}

			var addedAction = false;
			for (site in emissionSites(actual)) {
				if (RepresentationTypeAnalyzer.classify(expected, nullableStringCompat, classHasSubclasses) == RustSourceValueKind.SourceDynamic
					&& rejectAnonymousBorrowedShape(site.t, site))
					return;
				var siteOrigin = originAt(modulePath, site.pos);
				if (siteOrigin == null)
					continue;
				var rejection = RepresentationTypeAnalyzer.dynamicCrossingRejectionReason(site.t, expected, nullableStringCompat,
					classHasSubclasses);
				if (rejection != null) {
					RustDiagnostic.error(RustDiagnosticId.BorrowRegion, "Rust borrow region violation: " + rejection, site.pos);
					return;
				}
				var typeCheck = RepresentationTypeAnalyzer.tryDynamicCrossingTypeCheck(site.t, expected, nullableStringCompat, classHasSubclasses);
				var decision = RepresentationTypeAnalyzer.tryDecideCrossing(subject + "-action", site.t, expected, site.pos, siteOrigin,
					nullableStringCompat, classHasSubclasses);
				if (decision == null || typeCheck == null)
					continue;
				var existing = crossingByExpression.get(site);
				if (existing != null) {
					if (existing.decision.sourceKind != decision.sourceKind
						|| existing.decision.representation != decision.representation
						|| existing.decision.reuse != decision.reuse
						|| existing.typeCheck.canonicalKey() != typeCheck.canonicalKey()
						|| replayFamilyId(existing.replayFamily) != replayFamilyId(currentReplayFamily))
						throw 'Conflicting saved Dynamic crossings at `${existing.baseKey}`';
					continue;
				}
				var baseKey = RustSavedRepresentationCrossing.baseKeyFor(siteOrigin, typeCheck);
				var ordinal = nextCrossingOrdinal.get(baseKey);
				if (ordinal == null)
					ordinal = 0;
				var saved = RustSavedRepresentationCrossing.of(siteOrigin, decision, typeCheck, ordinal, origin, currentReplayFamily);
				nextCrossingOrdinal.set(baseKey, ordinal + 1);
				crossingByExpression.set(site, saved);
				crossings.push(saved);
				addedAction = true;
			}
			if (addedAction) {
				if (groupDecision != null) {
					addDecision(groupDecision);
				} else {
					// Mixed concrete branches cannot share one source representation, but the complete control
					// expression is still one Haxe Dynamic value and should produce one user-facing report row.
					addDecision(RepresentationTypeAnalyzer.tryDecide(subject + "-result", actual.t, actual.pos, origin, nullableStringCompat, null,
						classHasSubclasses));
				}
				addCoverage(RustRuntimeRequirementCoverage.family(RustRuntimeRequirementKind.RuntimeDynamic, "hxrt.dynamic"));
				if (relatedModulePath != null && (relatedModulePath == "haxe.Json" || StringTools.startsWith(relatedModulePath, "haxe.json."))) {
					addCoverage(RustRuntimeRequirementCoverage.exact(RustRuntimeRequirementKind.RuntimeDynamic, "haxe.Json"));
					addCoverage(RustRuntimeRequirementCoverage.family(RustRuntimeRequirementKind.RuntimeDynamic, "haxe.json"));
					addCoverage(RustRuntimeRequirementCoverage.family(RustRuntimeRequirementKind.RuntimeDynamic, "hxrt.json"));
				}
			}
		}

		/**
			Registers a declaration expression only after lowering has a real use that will emit it.

			Why / What / How
			- Defaults and read-only static constants live on their declaration but may be emitted at several
			  call or read sites. An unused declaration must create no saved Dynamic action.
			- Use the private module plus exact source bytes as the definition identity, and analyze the
			  declaration expression once after its first real use is found.
			- Later emitted uses reuse that saved action through the compiler's explicit replay context.
		**/
		function beginReplayedDefinition(modulePath:String, family:TypedExprReplayFamily, expression:TypedExpr):Bool {
			var origin = originAt(modulePath, expression.pos);
			if (origin == null)
				return false;
			var key = family.id + "\u0000" + origin.modulePath + "\u0000" + origin.sourceFile + "\u0000" + origin.startByte + "\u0000"
				+ origin.endByte;
			if (seenReplayDefinitions.exists(key))
				return false;
			seenReplayDefinitions.set(key, true);
			return true;
		}

		/**
			Saves a compiler-intrinsic result conversion whose concrete type is known from typed metadata.

			Why / What / How
			- A call such as constant-name `Reflect.field` is typed Dynamic as a whole, but lowering can read
			  the selected field using its concrete declaration before it creates the Dynamic result.
			- The ordinary expression crossing helper cannot recover that hidden concrete result type.
			- Anchor one explicit action to the call bytes, assign the next stable action number, and feed the
			  same decision into reports, runtime checks, and later lowering consumption.
		**/
		function addAnchoredCrossing(modulePath:String, label:String, anchor:TypedExpr, actualType:Type, expected:Type):Void {
			if (anchor == null || actualType == null || expected == null)
				return;
			var origin = originAt(modulePath, anchor.pos);
			if (origin == null)
				return;
			var info = Context.getPosInfos(anchor.pos);
			var subject = modulePath + "#" + label + "@" + info.min + ":" + info.max;
			var decision = RepresentationTypeAnalyzer.tryDecideCrossing(subject, actualType, expected, anchor.pos, origin, nullableStringCompat,
				classHasSubclasses);
			var typeCheck = RepresentationTypeAnalyzer.tryDynamicCrossingTypeCheck(actualType, expected, nullableStringCompat, classHasSubclasses);
			if (decision == null || typeCheck == null)
				return;
			var dedupeKey = label + "\u0000" + RustSavedRepresentationCrossing.baseKeyFor(origin, typeCheck);
			if (seenAnchoredCrossings.exists(dedupeKey))
				return;
			var baseKey = RustSavedRepresentationCrossing.baseKeyFor(origin, typeCheck);
			var ordinal = nextCrossingOrdinal.get(baseKey);
			if (ordinal == null)
				ordinal = 0;
			crossings.push(RustSavedRepresentationCrossing.of(origin, decision, typeCheck, ordinal, origin, currentReplayFamily));
			nextCrossingOrdinal.set(baseKey, ordinal + 1);
			seenAnchoredCrossings.set(dedupeKey, true);
			addDecision(decision);
			addCoverage(RustRuntimeRequirementCoverage.family(RustRuntimeRequirementKind.RuntimeDynamic, "hxrt.dynamic"));
		}

		function isStringFamily(type:Type):Bool {
			return switch (RepresentationTypeAnalyzer.classify(type, nullableStringCompat, classHasSubclasses)) {
				case RustSourceValueKind.SourceString | RustSourceValueKind.SourceNullableStringCompat: true;
				case _: false;
			};
		}

		function rejectAnonymousBorrowedField(fieldName:String, declaredType:Type, value:TypedExpr):Bool {
			var reason = RepresentationTypeAnalyzer.anonymousBorrowedFieldRejectionReason(declaredType);
			if (reason == null)
				return false;
			RustDiagnostic.error(RustDiagnosticId.BorrowRegion,
				'Rust borrow region violation: anonymous field `$fieldName` cannot be stored safely. $reason', value.pos);
			return true;
		}

		function arrayElementType(type:Type):Null<Type> {
			return switch (TypeTools.follow(type)) {
				case TInst(classRef, parameters) if (parameters.length == 1):
					var classType = classRef.get();
					classType != null && classType.pack.length == 0 && classType.name == "Array" ? parameters[0] : null;
				case _:
					null;
			};
		}

		function addImplicitResultCrossing(modulePath:String, body:TypedExpr, expectedReturn:Type):Void {
			if (body == null || expectedReturn == null || TypeHelper.isVoid(TypeTools.follow(expectedReturn)))
				return;
			var result = unwrapMetaParen(body);
			switch (result.expr) {
				case TBlock(expressions) if (expressions.length > 0):
					var index = 0;
					while (index < expressions.length - 1) {
						if (TypedExprControlFlow.stopsFollowingStatements(expressions[index]))
							return;
						index++;
					}
					result = unwrapMetaParen(expressions[expressions.length - 1]);
				case _:
			}
			switch (result.expr) {
				case TReturn(_) | TThrow(_) | TBreak | TContinue:
				case _:
					addCrossing(modulePath, "implicit-result-boundary", result, expectedReturn);
			}
		}

		function scanExpr(modulePath:String, root:TypedExpr, fieldRoot:Bool):Void {
			function visit(expr:TypedExpr, rootFunction:Bool, suppressCurrent:Bool, forceValuePosition:Bool = false,
					expectedReturn:Null<Type> = null):Void {
				if (expr == null)
					return;
				var current = unwrapMetaParen(expr);
				var functionNode = switch (current.expr) {
					case TFunction(_): true;
					case _: false;
				};
				var valueBearing = switch (current.expr) {
					case TConst(_) | TLocal(_) | TArray(_, _) | TBinop(_, _, _) | TField(_, _) | TArrayDecl(_) | TCall(_, _) | TNew(_, _, _)
						| TUnop(_, _, _) | TFunction(_) | TCast(_, _) | TObjectDecl(_):
						true;
					case _:
						false;
				};
				if (!suppressCurrent && (valueBearing || forceValuePosition) && !(rootFunction && functionNode))
					addType(modulePath, "expr", current.t, current.pos);

				switch (current.expr) {
					case TBlock(expressions):
						for (child in expressions) {
							visit(child, false, false, false, expectedReturn);
							if (TypedExprControlFlow.stopsFollowingStatements(child))
								break;
						}
						return;
					case TFunction(fn):
						// Method declarations were recorded from their ClassField signature above. Re-adding
						// the root TFunction arguments/result creates duplicate semantic rows at a second,
						// broader position. Nested TFunction nodes remain real first-class function values.
						if (!rootFunction) {
							for (index in 0...fn.args.length)
								addType(modulePath, "function-arg-" + index, fn.args[index].v.t, current.pos);
							addType(modulePath, "function-result", fn.t, current.pos);
						}
						var expectedFunctionResult = contextualFunctionReturnByExpression.get(current);
						if (expectedFunctionResult == null)
							expectedFunctionResult = fn.t;
						addImplicitResultCrossing(modulePath, fn.expr, expectedFunctionResult);
						visit(fn.expr, false, false, false, expectedFunctionResult);
						return;
					case TCall(callTarget, arguments):
						var callableTarget = TypedCallableTarget.transparent(callTarget);
						var relatedModulePath = callableOwnerPath(callableTarget);
						var intrinsicOwner:Null<ClassType> = null;
						var intrinsicField:Null<ClassField> = null;
						var declaredCallOwner:Null<ClassType> = null;
						var declaredCallField:Null<ClassField> = null;
						var declaredCallIsStatic = false;
						switch (callableTarget.expr) {
							case TField(_, FStatic(ownerRef, fieldRef)):
								intrinsicOwner = ownerRef.get();
								intrinsicField = fieldRef.get();
								declaredCallOwner = intrinsicOwner;
								declaredCallField = intrinsicField;
								declaredCallIsStatic = true;
							case TField(_, FInstance(ownerRef, _, fieldRef)):
								declaredCallOwner = ownerRef.get();
								declaredCallField = fieldRef.get();
							case _:
						}
						var stdStringCall = intrinsicOwner != null && intrinsicField != null && intrinsicOwner.pack.length == 0
							&& intrinsicOwner.name == "Std" && intrinsicField.name == "string";
						var stdIsOfTypeCall = intrinsicOwner != null && intrinsicField != null && intrinsicOwner.pack.length == 0
							&& intrinsicOwner.name == "Std" && intrinsicField.name == "isOfType";
						var traceCall = intrinsicOwner != null && intrinsicField != null && intrinsicOwner.pack.join(".") == "haxe"
							&& intrinsicOwner.name == "Log" && intrinsicField.name == "trace";
						var directReflectField:Null<ClassField> = null;
						var reflectOperation = intrinsicOwner != null && intrinsicField != null && intrinsicOwner.pack.length == 0
							&& intrinsicOwner.name == "Reflect" ? intrinsicField.name : "";
						var constantReflectName = false;
						if ((reflectOperation == "field" || reflectOperation == "setField") && arguments.length >= 2) {
							var fieldName:Null<String> = switch (unwrapMetaParen(arguments[1]).expr) {
								case TConst(TString(value)): value;
								case _: null;
							};
							constantReflectName = fieldName != null;
							if (constantReflectName)
								directReflectField = reflectedVariableField(arguments[0], fieldName);
						}
						if (reflectOperation == "hasField" && arguments.length >= 2)
							constantReflectName = switch (unwrapMetaParen(arguments[1]).expr) {
								case TConst(TString(_)): true;
								case _: false;
							};
						if (reflectOperation == "field" && directReflectField != null)
							addAnchoredCrossing(modulePath, "reflect-field-result-boundary", current, directReflectField.type, Context.getType("Dynamic"));
						if (reflectOperation == "setField" && directReflectField != null && arguments.length >= 3) {
							var anonymousWrite = RepresentationTypeAnalyzer.classify(arguments[0].t, nullableStringCompat, classHasSubclasses)
								== RustSourceValueKind.SourceAnonymousObject;
							if (anonymousWrite && rejectAnonymousBorrowedField(directReflectField.name, directReflectField.type, arguments[2]))
								return;
							if (anonymousWrite)
								addCrossing(modulePath, "reflect-field-write-shape-boundary", arguments[2], directReflectField.type);
							var writeBoundary = anonymousWrite ? Context.getType("Dynamic") : directReflectField.type;
							addCrossing(modulePath, "reflect-field-write-boundary", arguments[2], writeBoundary);
						}
						var directCallableTarget = switch (callableTarget.expr) {
							case TField(_, FStatic(_, fieldRef)) | TField(_, FInstance(_, _, fieldRef)):
								var field = fieldRef.get();
								field != null && switch (field.kind) {
									case FMethod(_): true;
									case _: false;
								};
							case TField(_, FEnum(_, _)): true;
							case _: false;
						};
						// When the target is immediately invoked, transparent metadata/parenthesis/cast wrappers
						// remain call syntax rather than stored function values. Visit the structural target itself
						// with suppression so recursive traversal cannot re-materialize the wrapped constructor.
						visit(directCallableTarget ? callableTarget : callTarget, false, directCallableTarget, false, expectedReturn);
						var expectedArguments = functionArgumentTypes(callTarget.t);
						var defaultExpressions:Array<Null<TypedExpr>> = [];
						if (declaredCallOwner != null && declaredCallField != null) {
							switch (declaredCallField.kind) {
								case FMethod(_):
									var functionData = declaredCallField.findFuncData(declaredCallOwner, declaredCallIsStatic);
									if (functionData != null && functionData.args != null)
										defaultExpressions = [for (argument in functionData.args) argument.expr];
								case _:
							}
						}
						for (index in 0...arguments.length) {
							var argument = arguments[index];
							// Haxe adds a compiler-created `{fileName, lineNumber, ...}` argument to `haxe.Log.trace`.
							// Rust trace lowering consumes the source position directly and never constructs that record.
							if (traceCall && index > 0)
								continue;
							var directReflectReceiver = index == 0 && (directReflectField != null
								&& (reflectOperation == "field" || reflectOperation == "setField")
								|| reflectOperation == "hasField" && constantReflectName && hasStaticReflectFields(arguments[0]));
							var directReflectValue = index == 2 && directReflectField != null && reflectOperation == "setField";
							var compareType = TypeTools.follow(argument.t);
							var directReflectCompare = reflectOperation == "compare" && (isStringFamily(argument.t)
								|| TypeHelper.isInt(compareType) || TypeHelper.isFloat(compareType));
							// `Std.isOfType` is a typed compiler intrinsic: its value and type-token arguments are
							// inspected directly and never boxed merely because the Haxe signature says Dynamic.
							var needsSavedCrossing = !stdIsOfTypeCall && !directReflectReceiver && !directReflectValue && (!stdStringCall
								|| RepresentationTypeAnalyzer.stringFormattingNeedsDynamic(argument.t, nullableStringCompat, classHasSubclasses))
								&& !directReflectCompare;
							if (index < expectedArguments.length && needsSavedCrossing)
								addCrossing(modulePath, "call-argument-" + index + "-boundary", argument, expectedArguments[index], relatedModulePath);
							// A direct argument is a materialized value even when its syntax is a control
							// expression such as `if` or `switch`. Its resulting type may be Dynamic even
							// though every branch has a more concrete type.
							visit(argument, false, false, true, expectedReturn);
						}
						for (index in arguments.length...expectedArguments.length) {
							var defaultExpression = index < defaultExpressions.length ? defaultExpressions[index] : null;
							if (defaultExpression == null || !TypedExprEmissionPolicy.defaultArgumentIsCallsiteSafe(defaultExpression))
								continue;
							if (declaredCallOwner == null || declaredCallField == null)
								continue;
							var family = TypedExprReplayFamily.methodDefault(declaredCallOwner, declaredCallField, index);
							var definitionModulePath = moduleName(declaredCallOwner.module, declaredCallOwner.pack, declaredCallOwner.name);
							if (beginReplayedDefinition(definitionModulePath, family, defaultExpression)) {
								withReplayFamily(family, () -> {
									addCrossing(definitionModulePath, "function-default-" + index + "-boundary", defaultExpression,
										expectedArguments[index]);
									scanExpr(definitionModulePath, defaultExpression, false);
								});
							}
						}
						return;
					case TNew(classRef, typeParameters, arguments):
						var expectedArguments = constructorArgumentTypes(classRef, typeParameters);
						var defaultExpressions:Array<Null<TypedExpr>> = [];
						var constructedClass = classRef == null ? null : classRef.get();
						if (constructedClass != null && constructedClass.constructor != null) {
							var constructor = constructedClass.constructor.get();
							var functionData = constructor == null ? null : constructor.findFuncData(constructedClass, false);
							if (functionData != null && functionData.args != null)
								defaultExpressions = [for (argument in functionData.args) argument.expr];
						}
						for (index in 0...arguments.length) {
							var argument = arguments[index];
							if (index < expectedArguments.length)
								addCrossing(modulePath, "constructor-argument-" + index + "-boundary", argument, expectedArguments[index]);
							visit(argument, false, false, true, expectedReturn);
						}
						for (index in arguments.length...expectedArguments.length) {
							var defaultExpression = index < defaultExpressions.length ? defaultExpressions[index] : null;
							if (defaultExpression == null || !TypedExprEmissionPolicy.defaultArgumentIsCallsiteSafe(defaultExpression))
								continue;
							if (constructedClass == null)
								continue;
							var family = TypedExprReplayFamily.constructorDefault(constructedClass, index);
							var definitionModulePath = moduleName(constructedClass.module, constructedClass.pack, constructedClass.name);
							if (beginReplayedDefinition(definitionModulePath, family, defaultExpression)) {
								withReplayFamily(family, () -> {
									addCrossing(definitionModulePath, "constructor-default-" + index + "-boundary", defaultExpression,
										expectedArguments[index]);
									scanExpr(definitionModulePath, defaultExpression, false);
								});
							}
						}
						return;
					case TVar(variable, initializer):
						if (variable != null) {
							addType(modulePath, "local-" + variable.id, variable.t, current.pos);
							if (initializer != null)
								addCrossing(modulePath, "local-initializer-boundary", initializer, variable.t);
						}
					case TField(_, FStatic(ownerRef, fieldRef)):
						var owner = ownerRef.get();
						var field = fieldRef.get();
						var inlineInitializer = TypedExprEmissionPolicy.staticReadOnlyConstantExpr(field);
						if (owner != null && field != null && inlineInitializer != null) {
							var family = TypedExprReplayFamily.staticReadOnly(owner, field);
							var definitionModulePath = moduleName(owner.module, owner.pack, owner.name);
							if (beginReplayedDefinition(definitionModulePath, family, inlineInitializer)) {
								withReplayFamily(family, () -> {
									addCrossing(definitionModulePath, "static-readonly-boundary", inlineInitializer, field.type);
									scanExpr(definitionModulePath, inlineInitializer, false);
								});
							}
						}
					case TArray(array, index)
						if (RepresentationTypeAnalyzer.classify(array.t, nullableStringCompat, classHasSubclasses) == RustSourceValueKind.SourceDynamic):
						var uncastIndex = index;
						var keepPeeling = true;
						while (keepPeeling) {
							var unwrapped = unwrapMetaParen(uncastIndex);
							switch (unwrapped.expr) {
								case TCast(inner, _): uncastIndex = inner;
								case _: keepPeeling = false;
							}
						}
						var directStringIndex = isStringFamily(uncastIndex.t) || isStringFamily(index.t);
						if (!directStringIndex && !TypeHelper.isInt(TypeTools.follow(index.t)))
							addCrossing(modulePath, "dynamic-index-boundary", index, Context.getType("Dynamic"));
					case TBinop(OpAssign, left, right):
						var expected = left.t;
						switch (unwrapMetaParen(left).expr) {
							case TField(receiver, FAnon(fieldRef))
								if (RepresentationTypeAnalyzer.classify(receiver.t, nullableStringCompat, classHasSubclasses)
									== RustSourceValueKind.SourceAnonymousObject):
								var field = fieldRef.get();
								if (field != null && rejectAnonymousBorrowedField(field.name, field.type, right))
									return;
								if (field != null)
									addCrossing(modulePath, "anonymous-assignment-shape-boundary", right, field.type);
								expected = Context.getType("Dynamic");
							case _:
						}
						addCrossing(modulePath, "assignment-boundary", right, expected);
						var writeTarget = unwrapMetaParen(left);
						switch (writeTarget.expr) {
							case TField(receiver, _):
								visit(receiver, false, false, false, expectedReturn);
							case TArray(array, index):
								visit(array, false, false, false, expectedReturn);
								visit(index, false, false, true, expectedReturn);
							case TLocal(_):
							case _:
								visit(left, false, false, false, expectedReturn);
						}
						visit(right, false, false, true, expectedReturn);
						return;
					case TBinop(OpEq, left, right) | TBinop(OpNotEq, left, right):
						var leftDynamic = RepresentationTypeAnalyzer.classify(left.t, nullableStringCompat, classHasSubclasses)
							== RustSourceValueKind.SourceDynamic;
						var rightDynamic = RepresentationTypeAnalyzer.classify(right.t, nullableStringCompat, classHasSubclasses)
							== RustSourceValueKind.SourceDynamic;
						if (leftDynamic && !rightDynamic)
							addCrossing(modulePath, "dynamic-equality-right-boundary", right, Context.getType("Dynamic"));
						if (rightDynamic && !leftDynamic)
							addCrossing(modulePath, "dynamic-equality-left-boundary", left, Context.getType("Dynamic"));
					case TArrayDecl(values):
						var elementType = arrayElementType(current.t);
						if (elementType != null)
							for (value in values)
								addCrossing(modulePath, "array-element-boundary", value, elementType);
					case TBinop(OpAdd, left, right) if (isStringFamily(current.t) || isStringFamily(left.t) || isStringFamily(right.t)):
						if (!isStringFamily(left.t))
							addCrossing(modulePath, "string-concat-left-boundary", left, Context.getType("Dynamic"));
						if (!isStringFamily(right.t))
							addCrossing(modulePath, "string-concat-right-boundary", right, Context.getType("Dynamic"));
					case TBinop(OpAssignOp(OpAdd), left, right)
						if (isStringFamily(current.t) || isStringFamily(left.t) || isStringFamily(right.t)):
						if (!isStringFamily(right.t))
							addCrossing(modulePath, "string-append-boundary", right, Context.getType("Dynamic"));
					case TReturn(value) if (value != null && expectedReturn != null):
						addCrossing(modulePath, "return-boundary", value, expectedReturn);
					case TThrow(value) if (value != null):
						addCrossing(modulePath, "throw-boundary", value, Context.getType("Dynamic"));
					case TCast(value, _):
						addCrossing(modulePath, "cast-boundary", value, current.t);
					case TObjectDecl(fields):
						var declaredFields:Map<String, Type> = [];
						switch (TypeTools.follow(current.t)) {
							case TAnonymous(anonymousRef):
								var anonymous = anonymousRef.get();
								if (anonymous != null && anonymous.fields != null)
									for (declared in anonymous.fields)
										declaredFields.set(declared.name, declared.type);
							case _:
						}
						for (field in fields) {
							var declaredType = declaredFields.get(field.name);
							if (declaredType != null && rejectAnonymousBorrowedField(field.name, declaredType, field.expr))
								return;
							if (declaredType != null)
								addCrossing(modulePath, "anonymous-field-" + field.name + "-shape-boundary", field.expr, declaredType);
							addCrossing(modulePath, "anonymous-field-" + field.name + "-boundary", field.expr, Context.getType("Dynamic"));
						}
						if (rejectAnonymousBorrowedShape(current.t, current))
							return;
						if (RepresentationTypeAnalyzer.classify(current.t, nullableStringCompat, classHasSubclasses)
							== RustSourceValueKind.SourceDynamic) {
							var origin = originAt(modulePath, current.pos);
							if (origin != null) {
								var info = Context.getPosInfos(current.pos);
								addDecision(RepresentationTypeAnalyzer.decideSourceKind(modulePath + "#anonymous-object@" + info.min + ":" + info.max,
									RustSourceValueKind.SourceAnonymousObject, false, origin));
							}
						}
					case _:
				}
				TypedExprTools.iter(current, child -> visit(child, false, false, false, expectedReturn));
			}
			visit(root, fieldRoot, false);
		}

		function scanFields(modulePath:String, owner:ClassType, fields:Array<ClassField>, staticFields:Array<ClassField>):Void {
			if (fields == null)
				return;
			function fieldKey(field:ClassField):String {
				var position = Context.getPosInfos(field.pos);
				return field.name + "\u0000" + position.file + "\u0000" + position.min + "\u0000" + position.max;
			}
			var staticFieldKeys:Map<String, Bool> = [];
			if (staticFields != null)
				for (field in staticFields)
					if (field != null)
						staticFieldKeys.set(fieldKey(field), true);
			var constructorKey:Null<String> = null;
			if (owner != null && owner.constructor != null) {
				var constructor = owner.constructor.get();
				if (constructor != null)
					constructorKey = fieldKey(constructor);
			}
			for (field in fields) {
				if (field == null)
					continue;
				var method = switch (field.kind) {
					case FMethod(_): true;
					case _: false;
				};
				switch (field.type) {
					case TFun(parameters, result) if (method):
						for (index in 0...parameters.length)
							addType(modulePath, field.name + "-parameter-" + index, parameters[index].t, field.pos);
						addType(modulePath, field.name + "-result", result, field.pos);
					case _:
						addType(modulePath, "field-" + field.name, field.type, field.pos);
				}
				var expression = field.expr();
				if (expression != null) {
					var inlineStatic = staticFieldKeys.exists(fieldKey(field)) && TypedExprEmissionPolicy.staticReadOnlyConstantExpr(field) != null;
					if (!inlineStatic) {
						if (!method)
							addCrossing(modulePath, "field-initializer-" + field.name + "-boundary", expression, field.type);
						if (constructorKey != null && fieldKey(field) == constructorKey) {
							var family = TypedExprReplayFamily.constructorBody(owner);
							withReplayFamily(family, () -> scanExpr(modulePath, expression, method));
						} else {
							scanExpr(modulePath, expression, method);
						}
					}
				}
			}
		}

		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					if (classType != null) {
						var modulePath = moduleName(classType.module, classType.pack, classType.name);
						scanFields(modulePath, classType, TypedClassExecutableFields.collect(classType), classType.statics.get());
					}
				case TAbstract(abstractRef):
					var abstractType = abstractRef.get();
					if (abstractType != null && abstractType.impl != null) {
						var implementation = abstractType.impl.get();
						if (implementation != null) {
							var modulePath = moduleName(abstractType.module, abstractType.pack, abstractType.name);
							scanFields(modulePath, implementation, TypedClassExecutableFields.collect(implementation), implementation.statics.get());
						}
					}
				case TEnumDecl(enumRef):
					var enumType = enumRef.get();
					if (enumType != null) {
						var modulePath = moduleName(enumType.module, enumType.pack, enumType.name);
						var constructorNames = [for (name in enumType.constructs.keys()) name];
						constructorNames.sort(compareStrings);
						for (constructorName in constructorNames) {
							var constructor = enumType.constructs.get(constructorName);
							if (constructor == null)
								continue;
							switch (constructor.type) {
								case TFun(parameters, _):
									for (index in 0...parameters.length)
										addType(modulePath, "enum-" + constructorName + "-parameter-" + index, parameters[index].t, constructor.pos);
								case _:
							}
						}
					}
				case TTypeDecl(_):
			}
		}

		out.sort((left, right) -> compareStrings(left.canonicalKey(), right.canonicalKey()));
		return RustRepresentationAnalysisSnapshot.of(out, crossings, coverage);
	}

	static function callableOwnerPath(callTarget:TypedExpr):String {
		if (callTarget == null)
			return "";
		return switch (TypedCallableTarget.transparent(callTarget).expr) {
			case TField(_, FStatic(ownerRef, _)) | TField(_, FInstance(ownerRef, _, _)):
				var owner = ownerRef.get();
				owner == null ? "" : typePath(owner.pack, owner.name);
			case TField(_, FEnum(ownerRef, _)):
				var owner = ownerRef.get();
				owner == null ? "" : typePath(owner.pack, owner.name);
			case _:
				"";
		};
	}

	/**
		Returns a directly readable variable field selected by a constant reflection name.

		Why / What / How
		- The backend replaces constant-name class and anonymous-object reflection with a normal typed field
		  read, so the receiver never crosses into Dynamic while the result may still do so.
		- Inspect only typed instance/anonymous declarations and admit only stored variables; method and
		  computed shapes keep their ordinary reflection behavior.
		- Match both the declared and Haxe-facing field names so early analysis mirrors lowering.
	**/
	static function reflectedVariableField(receiver:TypedExpr, fieldName:String):Null<ClassField> {
		if (receiver == null || fieldName == null)
			return null;
		var fields:Array<ClassField> = switch (TypeTools.follow(receiver.t)) {
			case TInst(classRef, _):
				var classType = classRef.get();
				classType == null || classType.fields == null ? [] : classType.fields.get();
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				anonymous == null || anonymous.fields == null ? [] : anonymous.fields;
			case _:
				[];
		};
		for (field in fields) {
			if (field == null || field.name != fieldName && field.getHaxeName() != fieldName)
				continue;
			return switch (field.kind) {
				case FVar(_, _): field;
				case _: null;
			};
		}
		return null;
	}

	/**
		Reports whether constant-name `Reflect.hasField` can be answered without a Dynamic receiver.

		Why / What / How
		- Class and anonymous declarations already contain the complete field-name set used by this lowering.
		- Mark only those two typed families as static; Dynamic and unresolved shapes still use runtime checks.
		- Early analysis uses the answer to avoid saving a box that emitted Rust never performs.
	**/
	static function hasStaticReflectFields(receiver:TypedExpr):Bool {
		if (receiver == null)
			return false;
		return switch (TypeTools.follow(receiver.t)) {
			case TInst(classRef, _): classRef.get() != null;
			case TAnonymous(anonymousRef): anonymousRef.get() != null;
			case _: false;
		};
	}

	static function functionArgumentTypes(type:Type):Array<Type> {
		if (type == null)
			return [];
		return switch (TypeTools.follow(type)) {
			case TFun(arguments, _): [for (argument in arguments) argument.t];
			case _: [];
		};
	}

	static function constructorArgumentTypes(classRef:Ref<ClassType>, typeParameters:Array<Type>):Array<Type> {
		if (classRef == null)
			return [];
		var classType = classRef.get();
		if (classType == null || classType.constructor == null)
			return [];
		var constructor = classType.constructor.get();
		if (constructor == null)
			return [];
		var constructorType = constructor.type;
		if (classType.params != null && typeParameters != null && classType.params.length == typeParameters.length && classType.params.length > 0)
			constructorType = TypeTools.applyTypeParameters(constructorType, classType.params, typeParameters);
		return functionArgumentTypes(constructorType);
	}

	/**
		Returns the direct representation-bearing children of one typed value.

		Why / What / How
		- Rust lowering recursively maps container arguments, function signatures, anonymous fields, and
		  typedef targets. Ignoring those children can call `rust.Vec<Dynamic>` no-runtime even though its
		  element still emits the hxrt Dynamic carrier.
		- This helper follows only structural storage edges, not class fields or method declarations, so it
		  does not turn compiler type scaffolding into invented runtime values.
		- The caller owns cycle suppression and canonical decision sorting.
	**/
	static function directTypeChildren(type:Type):Array<Type> {
		var out:Array<Type> = [];
		switch (type) {
			case TMono(monomorphRef):
				var resolved = monomorphRef.get();
				if (resolved != null)
					out.push(resolved);
			case TEnum(_, parameters) | TInst(_, parameters) | TAbstract(_, parameters):
				if (parameters != null)
					for (parameter in parameters)
						out.push(parameter);
			case TType(typeRef, parameters):
				var typedefType = typeRef.get();
				if (typedefType != null) {
					var underlying = typedefType.type;
					if (typedefType.params != null && typedefType.params.length > 0 && parameters.length == typedefType.params.length)
						underlying = TypeTools.applyTypeParameters(underlying, typedefType.params, parameters);
					out.push(underlying);
				}
			case TFun(arguments, result):
				for (argument in arguments)
					out.push(argument.t);
				out.push(result);
			case TAnonymous(anonymousRef):
				var anonymous = anonymousRef.get();
				if (anonymous != null && anonymous.fields != null) {
					var fields = anonymous.fields.copy();
					fields.sort((left, right) -> compareStrings(left.name, right.name));
					for (field in fields)
						out.push(field.type);
				}
			case TDynamic(inner):
				if (inner != null)
					out.push(inner);
			case TLazy(resolve):
				var resolved = resolve();
				if (resolved != null)
					out.push(resolved);
		}
		return out;
	}

	/**
		Builds the exact source location shared by typed representation and no-hxrt operation checks.

		Why / What / How
		- Both analyzers must attribute the same Haxe expression identically, including multibyte source text.
		- Preserve an already-safe relative path or replace an absolute/classpath spelling with a logical
		  module path, then convert Haxe source-string coordinates to exact UTF-8 bytes.
		- Return `null` when either path privacy or exact source resolution cannot be proven.
	**/
	public static function originAt(modulePath:String, pos:haxe.macro.Expr.Position):Null<RustDecisionOrigin> {
		var info = Context.getPosInfos(pos);
		if (info == null || info.file == null || info.file.length == 0 || info.min < 0 || info.max < info.min)
			return null;
		var stableFile = RustSourcePosition.stableSourcePath(info.file, modulePath);
		if (stableFile == null)
			return null;
		var byteRange = RustSourcePosition.utf8ByteRange(info.file, info.min, info.max);
		if (byteRange == null)
			return null;
		RustSourcePosition.rememberHaxePosition(stableFile, byteRange.startByte, byteRange.endByte);
		return RustDecisionOrigin.at(stableFile, byteRange.startByte, byteRange.endByte, modulePath);
	}

	static function unwrapMetaParen(expr:TypedExpr):TypedExpr {
		var current = expr;
		var changed = true;
		while (changed && current != null) {
			changed = false;
			switch (current.expr) {
				case TMeta(_, inner) | TParenthesis(inner):
					current = inner;
					changed = true;
				case _:
			}
		}
		return current;
	}

	static inline function moduleName(module:String, pack:Array<String>, name:String):String {
		return module != null && module.length > 0 ? module : (pack == null || pack.length == 0 ? name : pack.join(".") + "." + name);
	}

	static inline function typePath(pack:Array<String>, name:String):String {
		return pack == null || pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	static inline function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
