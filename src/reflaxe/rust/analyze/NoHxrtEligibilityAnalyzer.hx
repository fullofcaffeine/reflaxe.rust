package reflaxe.rust.analyze;

import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.helpers.TypeHelper;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeFallbackSummary;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeRequirementEntry;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeRequirementKind;

using reflaxe.helpers.ModuleTypeHelper;

/**
	NoHxrtEligibilityAnalyzer

	Why
	- `NoHxrtPass` proves the generated Rust AST does not reference `hxrt`, but that is a final
	  emitted-code guard.
	- `rust_no_hxrt` also needs a source/typed-AST semantic gate so users see stable reasons such as
	  `dynamic`, `reflection`, or `platform_abstraction` before a late generated-path failure.

	What
	- Builds a no-runtime eligibility result from two inputs:
	  - module-level runtime requirements from `RuntimeRequirementAnalyzer`,
	  - user-authored typed-AST constructs that are known to require runtime semantics.
	- The current AST slice is intentionally narrow and reportable:
	  - dynamic field access and Dynamic/DynamicAccess locals,
	  - anonymous object declarations when they cross a Dynamic/DynamicAccess boundary,
	  - exceptions,
	  - Haxe `Array` literals.
	  - direct reflection/runtime-introspection and platform-abstraction calls.
	- Broader type expansion is intentionally deferred because Haxe function/class internals can
	  expose compiler structural types that are not user-authored runtime objects.

	How
	- `analyze(...)` is only meant to run when `rust_no_hxrt` is active.
	- It marks every requirement as `noHxrtBlocked: true`.
	- The final generated-code `NoHxrtPass` still runs afterwards for lowering paths this semantic
	  pass cannot yet prove.
**/
class NoHxrtEligibilityAnalyzer {
	public static function analyze(userModuleTypes:Array<ModuleType>, modulePaths:Array<String>, nullableStrings:Bool, allowUnresolvedMonomorphDynamic:Bool,
			allowUnmappedCoreTypeDynamic:Bool):NoHxrtEligibilityResult {
		var requirements = RuntimeRequirementAnalyzer.collect(modulePaths, true, nullableStrings, allowUnresolvedMonomorphDynamic,
			allowUnmappedCoreTypeDynamic);

		if (userModuleTypes != null) {
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
				scanClassFieldExprs(module, classType.fields.get(), requirements);
				scanClassFieldExprs(module, classType.statics.get(), requirements);
			case TAbstract(absRef):
				var abstractType = absRef.get();
				if (abstractType.impl == null)
					return;
				var impl = abstractType.impl.get();
				if (impl == null)
					return;
				var module = moduleNameForAbstract(abstractType);
				scanClassFieldExprs(module, impl.fields.get(), requirements);
				scanClassFieldExprs(module, impl.statics.get(), requirements);
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
				case TObjectDecl(_) if (isDynamicBoundaryType(current.t)):
					add(requirements, AnonymousObject, "typed_ast", module, "Anonymous object expressions require hxrt object storage.");
				case TVar(v, init):
					{
						if (v != null && isDynamicBoundaryType(v.t))
							add(requirements, Dynamic, "typed_ast", module, "Dynamic-compatible locals require hxrt dynamic representation.");
						if (v != null && isDynamicBoundaryType(v.t) && init != null && isObjectDecl(init))
							add(requirements, AnonymousObject, "typed_ast", module,
								"Anonymous object expressions crossing Dynamic-compatible boundaries require hxrt object storage.");
					}
				case TThrow(_):
					add(requirements, Exception, "typed_ast", module, "Haxe throw semantics require hxrt exception support.");
				case TTry(_, _):
					add(requirements, Exception, "typed_ast", module, "Haxe try/catch semantics require hxrt exception support.");
				case TArrayDecl(_):
					add(requirements, HaxeArraySemantics, "typed_ast", module, "Haxe Array literals require runtime-backed Array semantics.");
				case TField(_, FDynamic(_)):
					add(requirements, Dynamic, "typed_ast", module, "Dynamic field access requires hxrt dynamic representation.");
				case TCall(callTarget, _):
					{
						var ownerPath = callOwnerPath(callTarget);
						if (ownerPath == "Reflect" || ownerPath == "Type" || StringTools.startsWith(ownerPath, "haxe.rtti."))
							add(requirements, Reflection, "typed_ast", module, "Reflection/runtime introspection requires hxrt support.");
						if (ownerPath == "Sys" || StringTools.startsWith(ownerPath, "sys."))
							add(requirements, PlatformAbstraction, "typed_ast", module, "Platform abstraction requires hxrt wrapper support.");
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(root);
	}

	static function isObjectDecl(expr:TypedExpr):Bool {
		if (expr == null)
			return false;
		return switch (unwrapMetaParen(expr).expr) {
			case TObjectDecl(_): true;
			case _:
				false;
		}
	}

	static function isDynamicBoundaryType(t:Type):Bool {
		if (t == null)
			return false;
		return switch (t) {
			case TDynamic(_):
				true;
			case TMono(monoRef):
				isDynamicBoundaryType(monoRef.get());
			case TLazy(lazyRef):
				isDynamicBoundaryType(lazyRef());
			case _: var mt = TypeHelper.toModuleType(t); var path = mt != null ? mt.getPath() : null; path == "Dynamic" || path == "haxe.DynamicAccess";
		}
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
			message:String):Void {
		var entry:RuntimeRequirementEntry = {
			reasonKind: reasonKind,
			sourceKind: sourceKind,
			sourceModule: sourceModule,
			sourceSpan: "",
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
