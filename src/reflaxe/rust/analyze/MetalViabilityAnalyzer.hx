package reflaxe.rust.analyze;

import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;

/**
	MetalViabilityAnalyzer

	Why
	- Metal performance work needs a deterministic, typed signal that explains why code is or is not
	  "metal-clean" beyond binary pass/fail checks.
	- A viability snapshot lets the compiler report actionable blockers now and later emit stable
	  `metal_report.*` artifacts without duplicating analysis logic.

	What
	- Produces a `MetalViabilitySnapshot` with:
	  - per-module scores and blocker lists,
	  - global blockers from compile-time defines/policy toggles,
	  - deterministic aggregate summary fields (`overallScore`, module counts, blocker totals).
	- Tracks known blocker categories aligned with current metal contracts:
	  - reflection/runtime-introspection usage,
	  - `Dynamic` / `haxe.DynamicAccess` boundaries,
	  - dynamic field access on runtime receivers,
	  - raw Rust fallback (`ERaw`) counts from pass output,
	  - global fallback toggles that weaken metal-clean guarantees.

	How
	- Walks typed module AST (`Context.getAllModuleTypes()` caller input) and field signatures.
	- Aggregates module blockers in typed maps (deduplicated, counted).
	- Merges pass-level fallback counts (`CompilationContext.recordMetalRawExpr(...)` data).
	- Applies deterministic scoring penalties and stable sorting for repeatable outputs in CI.
**/
class MetalViabilityAnalyzer {
	static inline final MAX_TYPE_SCAN_DEPTH:Int = 24;

	public static function analyze(moduleTypes:Array<ModuleType>, rawExprByModule:Array<{module:String, count:Int}>,
			options:MetalViabilityOptions):MetalViabilitySnapshot {
		var modules = new Map<String, ModuleAccumulator>();
		var globalBlockers = new Map<String, MetalViabilityBlocker>();

		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					analyzeClass(classRef.get(), modules);
				case TEnumDecl(enumRef):
					analyzeEnum(enumRef.get(), modules);
				case TTypeDecl(typeRef):
					analyzeTypedef(typeRef.get(), modules);
				case TAbstract(absRef):
					analyzeAbstract(absRef.get(), modules);
				case _:
			}
		}

		for (entry in rawExprByModule) {
			var module = normalizeModuleLabel(entry.module);
			var acc = ensureModule(modules, module);
			addModuleBlocker(acc, {
				id: "raw_expr_fallback",
				category: "raw_fallback",
				summary: "Generated Rust still contains raw fallback expression nodes (`ERaw`).",
				fix: "Add typed lowering for this boundary to move toward metal-clean output.",
				occurrences: entry.count,
				weight: rawExprPenalty(entry.count)
			});
		}

		if (options.allowFallback) {
			addGlobalBlocker(globalBlockers, {
				id: "metal_allow_fallback",
				category: "policy_toggle",
				summary: "Fallback mode is enabled (`-D rust_metal_allow_fallback`).",
				fix: "Remove `-D rust_metal_allow_fallback` after blockers are resolved to enforce metal-clean output.",
				occurrences: 1,
				weight: 12
			});
		}
		if (options.allowUnresolvedMonomorphDynamic) {
			addGlobalBlocker(globalBlockers, {
				id: "allow_unresolved_monomorph_dynamic",
				category: "policy_toggle",
				summary: "Dynamic monomorph fallback define is enabled.",
				fix: "Remove `-D rust_allow_unresolved_monomorph_dynamic` and keep monomorph boundaries typed.",
				occurrences: 1,
				weight: 20
			});
		}
		if (options.allowUnmappedCoreTypeDynamic) {
			addGlobalBlocker(globalBlockers, {
				id: "allow_unmapped_coretype_dynamic",
				category: "policy_toggle",
				summary: "Unmapped core-type dynamic fallback define is enabled.",
				fix: "Remove `-D rust_allow_unmapped_coretype_dynamic` and map core types explicitly.",
				occurrences: 1,
				weight: 20
			});
		}
		if (options.nullableStrings) {
			addGlobalBlocker(globalBlockers, {
				id: "metal_nullable_strings",
				category: "policy_toggle",
				summary: "Nullable string override is enabled (`-D rust_string_nullable`).",
				fix: "Use Rust-owned non-null string mode for metal-clean builds.",
				occurrences: 1,
				weight: 14
			});
		}

		var outModules:Array<MetalModuleViability> = [];
		for (module => acc in modules) {
			var blockers = blockersFromMap(acc.blockers);
			var penalty = totalPenalty(blockers);
			var score = clampScore(100 - penalty);
			var ready = blockers.length == 0;
			outModules.push({
				module: module,
				score: score,
				metalReady: ready,
				blockers: blockers
			});
		}
		outModules.sort(compareModules);

		var sortedGlobal = blockersFromMap(globalBlockers);
		var moduleCount = outModules.length;
		var readyCount = 0;
		var moduleScoreTotal = 0;
		var moduleBlockerTotal = 0;
		for (module in outModules) {
			if (module.metalReady)
				readyCount++;
			moduleScoreTotal += module.score;
			moduleBlockerTotal += module.blockers.length;
		}
		var moduleAverage = moduleCount == 0 ? 100 : Std.int(Math.round(moduleScoreTotal / moduleCount));
		var globalPenalty = totalPenalty(sortedGlobal);
		var overall = clampScore(moduleAverage - globalPenalty);
		var blockerCount = sortedGlobal.length + moduleBlockerTotal;

		return {
			overallScore: overall,
			moduleCount: moduleCount,
			moduleReadyCount: readyCount,
			blockerCount: blockerCount,
			modules: outModules,
			globalBlockers: sortedGlobal
		};
	}

	static function analyzeClass(classType:ClassType, modules:Map<String, ModuleAccumulator>):Void {
		var module = normalizeModuleLabel(moduleNameForClass(classType));
		var acc = ensureModule(modules, module);

		for (field in classType.fields.get()) {
			scanType(field.type, acc, 0);
			scanFieldExpr(field, acc);
		}
		for (field in classType.statics.get()) {
			scanType(field.type, acc, 0);
			scanFieldExpr(field, acc);
		}
	}

	static function analyzeAbstract(abstractType:AbstractType, modules:Map<String, ModuleAccumulator>):Void {
		var module = normalizeModuleLabel(moduleNameForAbstract(abstractType));
		var acc = ensureModule(modules, module);
		scanType(abstractType.type, acc, 0);

		if (abstractType.impl == null)
			return;
		var implClass = abstractType.impl.get();
		if (implClass == null)
			return;

		for (field in implClass.fields.get()) {
			scanType(field.type, acc, 0);
			scanFieldExpr(field, acc);
		}
		for (field in implClass.statics.get()) {
			scanType(field.type, acc, 0);
			scanFieldExpr(field, acc);
		}
	}

	static function analyzeEnum(enumType:EnumType, modules:Map<String, ModuleAccumulator>):Void {
		var module = normalizeModuleLabel(moduleNameForEnum(enumType));
		var acc = ensureModule(modules, module);
		for (field in enumType.constructs) {
			if (field != null)
				scanType(field.type, acc, 0);
		}
	}

	static function analyzeTypedef(typedefType:DefType, modules:Map<String, ModuleAccumulator>):Void {
		var module = normalizeModuleLabel(moduleNameForTypedef(typedefType));
		var acc = ensureModule(modules, module);
		scanType(typedefType.type, acc, 0);
	}

	static function scanFieldExpr(field:ClassField, acc:ModuleAccumulator):Void {
		var expr = field.expr();
		if (expr == null)
			return;
		scanExpr(expr, acc);
	}

	static function scanExpr(root:TypedExpr, acc:ModuleAccumulator):Void {
		function visit(expr:TypedExpr):Void {
			var current = unwrapMetaParen(expr);
			scanType(current.t, acc, 0);

			switch (current.expr) {
				case TTypeExpr(mt):
					registerModulePath(moduleTypePath(mt), acc);
				case TField(_, FStatic(ownerRef, _)):
					registerModulePath(classPath(ownerRef.get()), acc);
				case TField(_, FDynamic(_)):
					addModuleBlocker(acc, dynamicFieldAccessBlocker());
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(root);
	}

	static function scanType(t:Type, acc:ModuleAccumulator, depth:Int):Void {
		if (t == null || depth > MAX_TYPE_SCAN_DEPTH)
			return;

		switch (t) {
			case TDynamic(_):
				addModuleBlocker(acc, dynamicTypeBlocker());
			case TMono(monoRef):
				var resolved = monoRef.get();
				if (resolved != null)
					scanType(resolved, acc, depth + 1);
			case TLazy(loader):
				scanType(loader(), acc, depth + 1);
			case TType(typeRef, params):
				registerModulePath(typedefPath(typeRef.get()), acc);
				if (params != null) {
					for (param in params)
						scanType(param, acc, depth + 1);
				}
				scanType(TypeTools.follow(t), acc, depth + 1);
			case TAbstract(absRef, params):
				var path = abstractPath(absRef.get());
				registerModulePath(path, acc);
				if (params != null) {
					for (param in params)
						scanType(param, acc, depth + 1);
				}
			case TInst(classRef, params):
				registerModulePath(classPath(classRef.get()), acc);
				if (params != null) {
					for (param in params)
						scanType(param, acc, depth + 1);
				}
			case TEnum(enumRef, params):
				registerModulePath(enumPath(enumRef.get()), acc);
				if (params != null) {
					for (param in params)
						scanType(param, acc, depth + 1);
				}
			case TFun(args, ret):
				for (arg in args)
					scanType(arg.t, acc, depth + 1);
				scanType(ret, acc, depth + 1);
			case TAnonymous(anonRef):
				var anon = anonRef.get();
				if (anon != null) {
					for (field in anon.fields)
						scanType(field.type, acc, depth + 1);
				}
		}
	}

	static function registerModulePath(path:String, acc:ModuleAccumulator):Void {
		if (path == null || path.length == 0)
			return;
		if (isReflectionPath(path)) {
			addModuleBlocker(acc, reflectionBlocker(path));
			return;
		}
		if (path == "haxe.DynamicAccess") {
			addModuleBlocker(acc, dynamicAccessBlocker());
			return;
		}
		if (path == "Dynamic") {
			addModuleBlocker(acc, dynamicTypeBlocker());
		}
	}

	static function reflectionBlocker(path:String):MetalViabilityBlocker {
		return {
			id: "reflection_runtime_api:" + path,
			category: "reflection",
			summary: "Uses reflection/runtime-introspection API `" + path + "`.",
			fix: "Replace reflection lookups with typed fields/enums/interfaces in metal paths.",
			occurrences: 1,
			weight: 30
		};
	}

	static function dynamicAccessBlocker():MetalViabilityBlocker {
		return {
			id: "dynamic_access",
			category: "dynamic_boundary",
			summary: "Uses `haxe.DynamicAccess` runtime map semantics.",
			fix: "Prefer typed containers (`rust.HashMap<K,V>` or typed object schemas) at metal boundaries.",
			occurrences: 1,
			weight: 24
		};
	}

	static function dynamicTypeBlocker():MetalViabilityBlocker {
		return {
			id: "dynamic_type",
			category: "dynamic_boundary",
			summary: "Uses `Dynamic`-typed values (not statically metal-safe).",
			fix: "Convert runtime payloads to typed structures immediately after boundary crossing.",
			occurrences: 1,
			weight: 18
		};
	}

	static function dynamicFieldAccessBlocker():MetalViabilityBlocker {
		return {
			id: "dynamic_field_access",
			category: "dynamic_boundary",
			summary: "Uses dynamic field access (`obj.field` on dynamic receiver).",
			fix: "Replace dynamic field reads with typed structures or explicit boundary decoders.",
			occurrences: 1,
			weight: 14
		};
	}

	static function rawExprPenalty(count:Int):Int {
		if (count <= 0)
			return 0;
		var value = 6 + (count * 2);
		return value > 40 ? 40 : value;
	}

	static function ensureModule(modules:Map<String, ModuleAccumulator>, module:String):ModuleAccumulator {
		if (!modules.exists(module)) {
			modules.set(module, {
				module: module,
				blockers: []
			});
		}
		return modules.get(module);
	}

	static function addModuleBlocker(acc:ModuleAccumulator, blocker:MetalViabilityBlocker):Void {
		addBlocker(acc.blockers, blocker);
	}

	static function addGlobalBlocker(global:Map<String, MetalViabilityBlocker>, blocker:MetalViabilityBlocker):Void {
		addBlocker(global, blocker);
	}

	static function addBlocker(target:Map<String, MetalViabilityBlocker>, blocker:MetalViabilityBlocker):Void {
		if (target.exists(blocker.id)) {
			var prev = target.get(blocker.id);
			target.set(blocker.id, {
				id: prev.id,
				category: prev.category,
				summary: prev.summary,
				fix: prev.fix,
				occurrences: prev.occurrences + blocker.occurrences,
				weight: prev.weight > blocker.weight ? prev.weight : blocker.weight
			});
			return;
		}
		target.set(blocker.id, blocker);
	}

	static function blockersFromMap(map:Map<String, MetalViabilityBlocker>):Array<MetalViabilityBlocker> {
		var out:Array<MetalViabilityBlocker> = [];
		for (blocker in map)
			out.push(blocker);
		out.sort(compareBlockers);
		return out;
	}

	static inline function totalPenalty(blockers:Array<MetalViabilityBlocker>):Int {
		var total = 0;
		for (blocker in blockers)
			total += blocker.weight;
		return total;
	}

	static inline function clampScore(value:Int):Int {
		return value < 0 ? 0 : (value > 100 ? 100 : value);
	}

	static function compareModules(a:MetalModuleViability, b:MetalModuleViability):Int {
		if (a.score != b.score)
			return a.score < b.score ? -1 : 1;
		return a.module < b.module ? -1 : (a.module > b.module ? 1 : 0);
	}

	static function compareBlockers(a:MetalViabilityBlocker, b:MetalViabilityBlocker):Int {
		if (a.weight != b.weight)
			return a.weight > b.weight ? -1 : 1;
		return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
	}

	static inline function isReflectionPath(path:String):Bool {
		return path == "Reflect" || path == "Type" || StringTools.startsWith(path, "haxe.rtti.");
	}

	static inline function normalizeModuleLabel(value:Null<String>):String {
		if (value == null)
			return "<unknown>";
		var trimmed = StringTools.trim(value);
		return trimmed.length == 0 ? "<unknown>" : trimmed;
	}

	static inline function moduleNameForClass(classType:ClassType):String {
		if (classType.module != null && classType.module.length > 0)
			return classType.module;
		return pathFromPack(classType.pack, classType.name);
	}

	static inline function moduleNameForAbstract(abstractType:AbstractType):String {
		if (abstractType.module != null && abstractType.module.length > 0)
			return abstractType.module;
		return pathFromPack(abstractType.pack, abstractType.name);
	}

	static inline function moduleNameForEnum(enumType:EnumType):String {
		if (enumType.module != null && enumType.module.length > 0)
			return enumType.module;
		return pathFromPack(enumType.pack, enumType.name);
	}

	static inline function moduleNameForTypedef(typedefType:DefType):String {
		if (typedefType.module != null && typedefType.module.length > 0)
			return typedefType.module;
		return pathFromPack(typedefType.pack, typedefType.name);
	}

	static inline function classPath(classType:ClassType):String {
		return pathFromPack(classType.pack, classType.name);
	}

	static inline function abstractPath(abstractType:AbstractType):String {
		return pathFromPack(abstractType.pack, abstractType.name);
	}

	static inline function typedefPath(typedefType:DefType):String {
		return pathFromPack(typedefType.pack, typedefType.name);
	}

	static inline function enumPath(enumType:EnumType):String {
		return pathFromPack(enumType.pack, enumType.name);
	}

	static inline function moduleTypePath(moduleType:ModuleType):String {
		return switch (moduleType) {
			case TClassDecl(ref): classPath(ref.get());
			case TEnumDecl(ref): enumPath(ref.get());
			case TTypeDecl(ref): typedefPath(ref.get());
			case TAbstract(ref): abstractPath(ref.get());
		}
	}

	static inline function pathFromPack(pack:Array<String>, name:String):String {
		return pack == null || pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	static function unwrapMetaParen(expr:TypedExpr):TypedExpr {
		var current = expr;
		while (true) {
			switch (current.expr) {
				case TMeta(_, inner):
					current = inner;
					continue;
				case TParenthesis(inner):
					current = inner;
					continue;
				case _:
			}
			break;
		}
		return current;
	}
}

private typedef ModuleAccumulator = {
	var module:String;
	var blockers:Map<String, MetalViabilityBlocker>;
};

typedef MetalViabilityOptions = {
	var allowFallback:Bool;
	var allowUnresolvedMonomorphDynamic:Bool;
	var allowUnmappedCoreTypeDynamic:Bool;
	var nullableStrings:Bool;
};

typedef MetalViabilityBlocker = {
	var id:String;
	var category:String;
	var summary:String;
	var fix:String;
	var occurrences:Int;
	var weight:Int;
};

typedef MetalModuleViability = {
	var module:String;
	var score:Int;
	var metalReady:Bool;
	var blockers:Array<MetalViabilityBlocker>;
};

typedef MetalViabilitySnapshot = {
	var overallScore:Int;
	var moduleCount:Int;
	var moduleReadyCount:Int;
	var blockerCount:Int;
	var modules:Array<MetalModuleViability>;
	var globalBlockers:Array<MetalViabilityBlocker>;
};
