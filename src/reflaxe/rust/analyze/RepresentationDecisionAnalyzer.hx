package reflaxe.rust.analyze;

import haxe.ds.ObjectMap;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.helpers.TypeHelper;
import reflaxe.rust.RustSourcePosition;
import reflaxe.rust.analyze.RepresentationPlan.RustDecisionOrigin;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationPlan.RustReusePolicy;
import reflaxe.rust.analyze.RepresentationPlan.RustRuntimeRequirementKind;
import reflaxe.rust.analyze.RepresentationPlan.RustSourceValueKind;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustDynamicValueMaterialization;
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
		RustSourcePosition.reset();
		var out:Array<RustRepresentationDecision> = [];
		var crossings:Array<RustSavedRepresentationCrossing> = [];
		var coverage:Array<RustRuntimeRequirementCoverage> = [];
		var seen:Map<String, Bool> = [];
		var crossingByExpression:ObjectMap<{}, RustSavedRepresentationCrossing> = new ObjectMap();
		var seenAnchoredCrossings:Map<String, Bool> = [];
		var nextCrossingOrdinal:Map<String, Int> = [];
		var seenCoverage:Map<String, Bool> = [];
		if (moduleTypes == null)
			return RustRepresentationAnalysisSnapshot.of(out, crossings, coverage);

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

		function addCrossing(modulePath:String, label:String, actual:TypedExpr, expected:Type, ?relatedModulePath:String):Void {
			if (actual == null || expected == null)
				return;
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
				var siteOrigin = originAt(modulePath, site.pos);
				if (siteOrigin == null)
					continue;
				var decision = groupDecision;
				if (decision == null) {
					decision = RepresentationTypeAnalyzer.tryDecideCrossing(subject + "-branch", site.t, expected, site.pos, origin, nullableStringCompat,
						classHasSubclasses);
				}
				if (decision == null)
					continue;
				var siteKind = RepresentationTypeAnalyzer.classify(site.t, nullableStringCompat, classHasSubclasses);
				var materialization = if (siteKind == RustSourceValueKind.SourceBorrowedRef) {
					decision.reuse == RustReusePolicy.ReuseCopy ? RustDynamicValueMaterialization.DynamicValueBorrowCopy : RustDynamicValueMaterialization.DynamicValueBorrowClone;
				} else {
					RustDynamicValueMaterialization.DynamicValueDirect;
				};
				var existing = crossingByExpression.get(site);
				if (existing != null) {
					if (existing.decision.sourceKind != decision.sourceKind
						|| existing.decision.representation != decision.representation
						|| existing.decision.reuse != decision.reuse
						|| existing.materialization != materialization)
						throw 'Conflicting saved Dynamic crossings at `${existing.baseKey}`';
					continue;
				}
				var baseKey = RustSavedRepresentationCrossing.baseKeyFor(siteOrigin);
				var ordinal = nextCrossingOrdinal.get(baseKey);
				if (ordinal == null)
					ordinal = 0;
				var saved = RustSavedRepresentationCrossing.of(siteOrigin, decision, materialization, ordinal);
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
			var dedupeKey = label + "\u0000" + RustSavedRepresentationCrossing.baseKeyFor(origin);
			if (seenAnchoredCrossings.exists(dedupeKey))
				return;
			var info = Context.getPosInfos(anchor.pos);
			var subject = modulePath + "#" + label + "@" + info.min + ":" + info.max;
			var decision = RepresentationTypeAnalyzer.tryDecideCrossing(subject, actualType, expected, anchor.pos, origin, nullableStringCompat,
				classHasSubclasses);
			if (decision == null)
				return;
			var sourceKind = RepresentationTypeAnalyzer.classify(actualType, nullableStringCompat, classHasSubclasses);
			var materialization = if (sourceKind == RustSourceValueKind.SourceBorrowedRef) {
				decision.reuse == RustReusePolicy.ReuseCopy ? RustDynamicValueMaterialization.DynamicValueBorrowCopy : RustDynamicValueMaterialization.DynamicValueBorrowClone;
			} else {
				RustDynamicValueMaterialization.DynamicValueDirect;
			};
			var baseKey = RustSavedRepresentationCrossing.baseKeyFor(origin);
			var ordinal = nextCrossingOrdinal.get(baseKey);
			if (ordinal == null)
				ordinal = 0;
			crossings.push(RustSavedRepresentationCrossing.of(origin, decision, materialization, ordinal));
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

		/**
			Reports when a typed expression guarantees that the next statement cannot run.

			Why / What / How
			- Haxe can leave statements after an unconditional `return`, `throw`, `break`, or `continue`
			  in the typed tree even though Rust lowering deliberately omits them.
			- Early analysis must skip those omitted statements or it will save Dynamic actions that no
			  generated expression can consume.
			- Follow transparent wrappers and sequential blocks, and accept an `if` only when both branches
			  stop. Uncertain control flow returns `false`, so reachable work is never discarded speculatively.
		**/
		function stopsFollowingStatements(expression:TypedExpr):Bool {
			if (expression == null)
				return false;
			var current = unwrapMetaParen(expression);
			return switch (current.expr) {
				case TReturn(_) | TThrow(_) | TBreak | TContinue:
					true;
				case TCast(inner, _):
					stopsFollowingStatements(inner);
				case TBlock(expressions):
					var stops = false;
					for (child in expressions) {
						if (stopsFollowingStatements(child)) {
							stops = true;
							break;
						}
					}
					stops;
				case TIf(_, thenExpression, elseExpression) if (elseExpression != null):
					stopsFollowingStatements(thenExpression) && stopsFollowingStatements(elseExpression);
				case _:
					false;
			};
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
							if (stopsFollowingStatements(child))
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
						visit(fn.expr, false, false, false, fn.t);
						return;
					case TCall(callTarget, arguments):
						var callableTarget = transparentCallableTarget(callTarget);
						var relatedModulePath = callableOwnerPath(callableTarget);
						var intrinsicOwner:Null<ClassType> = null;
						var intrinsicField:Null<ClassField> = null;
						switch (callableTarget.expr) {
							case TField(_, FStatic(ownerRef, fieldRef)):
								intrinsicOwner = ownerRef.get();
								intrinsicField = fieldRef.get();
							case _:
						}
						var stdStringCall = intrinsicOwner != null && intrinsicField != null && intrinsicOwner.pack.length == 0
							&& intrinsicOwner.name == "Std" && intrinsicField.name == "string";
						var stdIsOfTypeCall = intrinsicOwner != null && intrinsicField != null && intrinsicOwner.pack.length == 0
							&& intrinsicOwner.name == "Std" && intrinsicField.name == "isOfType";
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
						for (index in 0...arguments.length) {
							var argument = arguments[index];
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
						return;
					case TNew(classRef, typeParameters, arguments):
						var expectedArguments = constructorArgumentTypes(classRef, typeParameters);
						for (index in 0...arguments.length) {
							var argument = arguments[index];
							if (index < expectedArguments.length)
								addCrossing(modulePath, "constructor-argument-" + index + "-boundary", argument, expectedArguments[index]);
							visit(argument, false, false, true, expectedReturn);
						}
						return;
					case TVar(variable, initializer):
						if (variable != null) {
							addType(modulePath, "local-" + variable.id, variable.t, current.pos);
							if (initializer != null)
								addCrossing(modulePath, "local-initializer-boundary", initializer, variable.t);
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
						addCrossing(modulePath, "assignment-boundary", right, left.t);
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
					case TObjectDecl(_) if (RepresentationTypeAnalyzer.classify(current.t, nullableStringCompat, classHasSubclasses)
						== RustSourceValueKind.SourceDynamic):
						var origin = originAt(modulePath, current.pos);
						if (origin != null) {
							var info = Context.getPosInfos(current.pos);
							addDecision(RepresentationTypeAnalyzer.decideSourceKind(modulePath + "#anonymous-object@" + info.min + ":" + info.max,
								RustSourceValueKind.SourceAnonymousObject, false, origin));
						}
					case _:
				}
				TypedExprTools.iter(current, child -> visit(child, false, false, false, expectedReturn));
			}
			visit(root, fieldRoot, false);
		}

		function scanFields(modulePath:String, fields:Array<ClassField>):Void {
			if (fields == null)
				return;
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
				if (expression != null)
					scanExpr(modulePath, expression, method);
			}
		}

		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					if (classType != null) {
						var modulePath = moduleName(classType.module, classType.pack, classType.name);
						// Haxe stores constructors outside `fields` / `statics`. They are still executable
						// user code and can contain the same argument, assignment, return, and Dynamic
						// boundaries as ordinary methods.
						var constructorRef = classType.constructor;
						if (constructorRef != null) {
							var constructor = constructorRef.get();
							if (constructor != null)
								scanFields(modulePath, [constructor]);
						}
						scanFields(modulePath, classType.fields.get());
						scanFields(modulePath, classType.statics.get());
					}
				case TAbstract(abstractRef):
					var abstractType = abstractRef.get();
					if (abstractType != null && abstractType.impl != null) {
						var implementation = abstractType.impl.get();
						if (implementation != null) {
							var modulePath = moduleName(abstractType.module, abstractType.pack, abstractType.name);
							scanFields(modulePath, implementation.fields.get());
							scanFields(modulePath, implementation.statics.get());
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
		return switch (transparentCallableTarget(callTarget).expr) {
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

	/**
		Returns the meaningful target of an immediately invoked callable expression.

		Why / What / How
		- Haxe and macros may retain metadata, parentheses, or a same-type `TCast` around a method or enum
		  constructor. Those wrappers do not store the callable, so treating their child as a value invents
		  function and object-identity runtime needs.
		- Peel only wrappers that preserve the target type. Calls, assignments, locals, and type-changing
		  casts remain visible because they can genuinely materialize a function value.
	**/
	private static function transparentCallableTarget(expr:TypedExpr):TypedExpr {
		var current = expr;
		var changed = true;
		while (changed && current != null) {
			changed = false;
			switch (current.expr) {
				case TMeta(_, inner) | TParenthesis(inner):
					current = inner;
					changed = true;
				case TCast(inner, _) if (TypeTools.toString(current.t) == TypeTools.toString(inner.t)):
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
