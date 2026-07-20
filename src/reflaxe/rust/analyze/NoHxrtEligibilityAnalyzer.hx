package reflaxe.rust.analyze;

import haxe.macro.Context;
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeFallbackSummary;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeRequirementEntry;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeRequirementKind;
import reflaxe.rust.analyze.RepresentationDecisionAnalyzer;
import reflaxe.rust.analyze.RepresentationPlan.RustRepresentationDecision;
import reflaxe.rust.analyze.RepresentationAnalysisSnapshot.RustRuntimeRequirementCoverage;

/**
	NoHxrtEligibilityAnalyzer

	Why
	- `NoHxrtPass` proves the generated Rust AST does not reference `hxrt`, but that is a final
	  emitted-code guard.
	- `rust_no_hxrt` also needs a source/typed-AST semantic gate so users see stable reasons such as
	  `dynamic`, `reflection`, or `platform_abstraction` before a late generated-path failure.

	What
	- Builds a no-runtime eligibility result from the shared typed representation decisions plus
	  non-value operations such as exceptions, reflection, and platform abstractions.
	- Typed collection ignores compiler scaffolding that does not materialize a value; this analyzer's
	  remaining AST scan owns only non-value operations that need their own semantic reason.

	How
	- `analyze(...)` is only meant to run when `rust_no_hxrt` is active.
	- Production lowering captures both typed decisions and non-value operation evidence before Reflaxe
	  extracts method bodies, then reuses that immutable result during later enforcement hooks.
	- It marks every requirement as `noHxrtBlocked: true`.
	- The final generated-code `NoHxrtPass` still runs afterwards for lowering paths this semantic
	  pass cannot yet prove.
**/
class NoHxrtEligibilityAnalyzer {
	public static function analyze(userModuleTypes:Array<ModuleType>, modulePaths:Array<String>, nullableStrings:Bool, allowUnresolvedMonomorphDynamic:Bool,
			allowUnmappedCoreTypeDynamic:Bool, ?classHasSubclasses:ClassType->Bool):NoHxrtEligibilityResult {
		var snapshot = RepresentationDecisionAnalyzer.collectSnapshot(userModuleTypes, nullableStrings, classHasSubclasses);
		return analyzeWithDecisions(userModuleTypes, modulePaths, nullableStrings, allowUnresolvedMonomorphDynamic, allowUnmappedCoreTypeDynamic,
			snapshot.decisions(), snapshot.coverage());
	}

	/**
		Consumes representation decisions captured while typed method bodies were still complete.

		Why / What / How
		- Reflaxe can extract method expressions before its later no-hxrt enforcement hooks run.
		- `RustCompiler` therefore captures the decisions at Haxe's after-typing boundary and passes a
		  defensive copy through this friend-only entry point.
		- Keeping the method private preserves the existing analyzer API for standalone compiler tests and
		  prevents callers from accidentally mixing decisions from another typed compilation.
	**/
	@:allow(reflaxe.rust.RustCompiler)
	private static function analyzeCaptured(userModuleTypes:Array<ModuleType>, modulePaths:Array<String>, nullableStrings:Bool,
			allowUnresolvedMonomorphDynamic:Bool, allowUnmappedCoreTypeDynamic:Bool,
			capturedRepresentationDecisions:Array<RustRepresentationDecision>, ?capturedCoverage:Array<RustRuntimeRequirementCoverage>,
			?capturedOperations:Array<RuntimeRequirementEntry>):NoHxrtEligibilityResult {
		if (capturedRepresentationDecisions == null || capturedCoverage == null || capturedOperations == null)
			throw "captured representation decisions, coverage, and operations cannot be null";
		return analyzeWithDecisions(userModuleTypes, modulePaths, nullableStrings, allowUnresolvedMonomorphDynamic, allowUnmappedCoreTypeDynamic,
			capturedRepresentationDecisions.copy(), capturedCoverage.copy(), capturedOperations.copy());
	}

	/**
		Saves exact operation rows while Haxe still owns complete typed method bodies.

		Why / What / How
		- Reflaxe and Haxe can remove or inline calls before `onCompileStart`. A broad module name then
		  survives, but the exact call position does not.
		- Scan each after-typing delivery immediately and retain only small validated report rows, never the
		  executable typed expression graph.
		- The compiler stores rows by collision-safe declaration identity, filters them to user modules at
		  compile start, and passes them back through `analyzeCaptured`.
	**/
	@:allow(reflaxe.rust.RustCompiler)
	private static function captureOperationEntries(moduleTypes:Array<ModuleType>):Array<RuntimeRequirementEntry> {
		var requirements:Array<RuntimeRequirementEntry> = [];
		if (moduleTypes != null)
			for (moduleType in moduleTypes)
				scanModuleType(moduleType, requirements);
		requirements.sort(RuntimeRequirementAnalyzer.compareEntries);
		return requirements;
	}

	/**
		Merges later module-path evidence into the exact typed snapshot unconditionally.

		Why / What / How
		- Module usage is complete only after lowering starts, while executable expression positions are
		  complete only in the earlier after-typing snapshot.
		- A pre-existing blocker does not mean collection is complete. Combine both lists and remove only
		  exact duplicates. An exact `Sys` expression, for example, says nothing about an independent
		  `DateTools` or `rust.concurrent` dependency discovered later.
		- Sorting and summary generation happen after the union, so declaration order cannot change the
		  diagnostic or hide an independent blocker.
	**/
	@:allow(reflaxe.rust.RustCompiler)
	private static function mergeCaptured(captured:NoHxrtEligibilityResult, modulePaths:Array<String>, nullableStrings:Bool,
			allowUnresolvedMonomorphDynamic:Bool, allowUnmappedCoreTypeDynamic:Bool,
			capturedRepresentationDecisions:Array<RustRepresentationDecision>, ?capturedCoverage:Array<RustRuntimeRequirementCoverage>):NoHxrtEligibilityResult {
		if (captured == null || captured.requirements == null || capturedRepresentationDecisions == null || capturedCoverage == null)
			throw "captured no-hxrt information, representation decisions, and coverage cannot be null";
		var requirements = captured.requirements.copy();
		var later = RuntimeRequirementAnalyzer.collect(modulePaths, true, nullableStrings, allowUnresolvedMonomorphDynamic,
			allowUnmappedCoreTypeDynamic, capturedRepresentationDecisions.copy(), true, capturedCoverage.copy());
		for (entry in later) {
			var duplicate = false;
			for (existing in requirements) {
				if (RuntimeRequirementAnalyzer.sameEntry(existing, entry)) {
					duplicate = true;
					break;
				}
			}
			if (!duplicate)
				requirements.push(entry);
		}
		requirements.sort(RuntimeRequirementAnalyzer.compareEntries);
		var summary = RuntimeRequirementAnalyzer.summarize(requirements);
		return {blocked: summary.blockedByNoHxrt, requirements: requirements, summary: summary};
	}

	static function analyzeWithDecisions(userModuleTypes:Array<ModuleType>, modulePaths:Array<String>, nullableStrings:Bool,
			allowUnresolvedMonomorphDynamic:Bool, allowUnmappedCoreTypeDynamic:Bool,
			representationDecisions:Array<RustRepresentationDecision>, coverage:Array<RustRuntimeRequirementCoverage>,
			?capturedOperations:Array<RuntimeRequirementEntry>):NoHxrtEligibilityResult {
		var requirements = RuntimeRequirementAnalyzer.collect(modulePaths, true, nullableStrings, allowUnresolvedMonomorphDynamic,
			allowUnmappedCoreTypeDynamic, representationDecisions, true, coverage);

		if (capturedOperations != null) {
			for (entry in capturedOperations) {
				var duplicate = false;
				for (existing in requirements)
					if (RuntimeRequirementAnalyzer.sameEntry(existing, entry)) {
						duplicate = true;
						break;
					}
				if (!duplicate)
					requirements.push(entry);
			}
		} else if (userModuleTypes != null) {
			for (moduleType in userModuleTypes)
				scanModuleType(moduleType, requirements);
		}

		requirements.sort(RuntimeRequirementAnalyzer.compareEntries);
		var summary = RuntimeRequirementAnalyzer.summarize(requirements);
		return {
			blocked: summary.blockedByNoHxrt,
			requirements: requirements,
			summary: summary
		};
	}

	static function scanModuleType(moduleType:ModuleType, requirements:Array<RuntimeRequirementEntry>):Void {
		switch (moduleType) {
			case TClassDecl(classRef):
				var classType = classRef.get();
				var module = moduleNameForClass(classType);
				scanClassFieldExprs(module, TypedClassExecutableFields.collect(classType), requirements);
			case TAbstract(absRef):
				var abstractType = absRef.get();
				if (abstractType.impl == null)
					return;
				var impl = abstractType.impl.get();
				if (impl == null)
					return;
				var module = moduleNameForAbstract(abstractType);
				scanClassFieldExprs(module, TypedClassExecutableFields.collect(impl), requirements);
			case TEnumDecl(_):
			case TTypeDecl(_):
		}
	}

	static function scanClassFieldExprs(module:String, fields:Array<ClassField>, requirements:Array<RuntimeRequirementEntry>):Void {
		if (fields == null)
			return;
		for (field in fields) {
			if (field == null)
				continue;
			var expr = field.expr();
			if (expr != null)
				scanExpr(module, expr, requirements);
		}
	}

	static function scanExpr(module:String, root:TypedExpr, requirements:Array<RuntimeRequirementEntry>):Void {
		function visit(expr:TypedExpr):Void {
			var current = unwrapMetaParen(expr);
			switch (current.expr) {
				case TThrow(value):
					add(requirements, RuntimeException, "typed_ast", module, coveringPosition([current.pos, value.pos]),
						"Haxe throw semantics require hxrt exception support.");
				case TTry(tryExpression, catches):
					var positions:Array<Position> = [current.pos, tryExpression.pos];
					if (catches != null)
						for (entry in catches)
							if (entry != null && entry.expr != null)
								positions.push(entry.expr.pos);
					add(requirements, RuntimeException, "typed_ast", module, coveringPosition(positions),
						"Haxe try/catch semantics require hxrt exception support.");
				case TCall(callTarget, _):
					{
						var ownerPath = callOwnerPath(callTarget);
						if (RuntimeRequirementAnalyzer.isReflectionPath(ownerPath))
							add(requirements, RuntimeReflection, "typed_ast", module, current.pos,
								"Reflection/runtime introspection requires hxrt support.");
						if (RuntimeRequirementAnalyzer.isPlatformAbstractionPath(ownerPath))
							add(requirements, RuntimePlatformAbstraction, "typed_ast", module, current.pos,
								"Platform abstraction requires hxrt wrapper support.");
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(root);
	}

	static function callOwnerPath(callTarget:TypedExpr):String {
		if (callTarget == null)
			return "";
		return switch (unwrapMetaParen(callTarget).expr) {
			case TField(_, FStatic(ownerRef, _)):
				classPath(ownerRef.get());
			case TField(_, FInstance(ownerRef, _, _)):
				classPath(ownerRef.get());
			case _:
				"";
		}
	}

	static function add(requirements:Array<RuntimeRequirementEntry>, reasonKind:RuntimeRequirementKind, sourceKind:String, sourceModule:String,
			pos:haxe.macro.Expr.Position, message:String):Void {
		var origin = RepresentationDecisionAnalyzer.originAt(sourceModule, pos);
		var entry:RuntimeRequirementEntry = {
			reasonKind: reasonKind,
			sourceKind: sourceKind,
			sourceModule: sourceModule,
			sourceSpan: origin == null ? "" : origin.sourceFile + ":" + origin.startByte + "-" + origin.endByte,
			surfaceId: null,
			requiresHxrt: true,
			noHxrtBlocked: true,
			message: message
		};
		for (existing in requirements) {
			if (RuntimeRequirementAnalyzer.sameEntry(existing, entry))
				return;
		}
		requirements.push(entry);
	}

	/**
		Builds one exact Haxe range covering all syntax that belongs to a compound operation.

		Why / What / How
		- Haxe may attach a `throw`/`try` node position to only part of its printed syntax, which loses the
		  keyword or a catch body when diagnostics are reconstructed later.
		- Take the smallest start and largest end from the wrapper and its required children.
		- Require one source file and return a real Haxe `Position`; UTF-8 byte conversion and private path
		  handling remain owned by `RustSourcePosition`.
	**/
	static function coveringPosition(positions:Array<Position>):Position {
		if (positions == null || positions.length == 0)
			throw "An exact no-hxrt operation range requires at least one Haxe position";
		var first = Context.getPosInfos(positions[0]);
		var min = first.min;
		var max = first.max;
		for (index in 1...positions.length) {
			var info = Context.getPosInfos(positions[index]);
			if (info.file != first.file)
				throw "One no-hxrt operation cannot span several Haxe source files";
			if (info.min < min)
				min = info.min;
			if (info.max > max)
				max = info.max;
		}
		return Context.makePosition({file: first.file, min: min, max: max});
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

	static inline function moduleNameForClass(classType:ClassType):String {
		return classType.module != null && classType.module.length > 0 ? classType.module : pathFromPack(classType.pack, classType.name);
	}

	static inline function moduleNameForAbstract(abstractType:AbstractType):String {
		return abstractType.module != null
			&& abstractType.module.length > 0 ? abstractType.module : pathFromPack(abstractType.pack, abstractType.name);
	}

	static inline function pathFromPack(pack:Array<String>, name:String):String {
		return pack == null || pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	static inline function classPath(classType:ClassType):String {
		return pathFromPack(classType.pack, classType.name);
	}
}

typedef NoHxrtEligibilityResult = {
	var blocked:Bool;
	var requirements:Array<RuntimeRequirementEntry>;
	var summary:RuntimeFallbackSummary;
}
