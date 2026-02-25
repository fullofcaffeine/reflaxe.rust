package reflaxe.rust.analyze;

import haxe.macro.Type;

/**
	MetalIslandAnalyzer

	Why
	- `metal` as a whole-profile switch is useful, but performance migrations are often incremental.
	- We need a typed way to mark "this module/function should obey metal constraints now" while
	  the rest of the project can remain in `portable`.
	- Island collection must be deterministic so CI diagnostics and viability reports stay stable.

	What
	- Collects metal-lane declarations from typed modules and returns:
	  - a sorted, deduplicated module list (`modules`),
	  - declaration records with source labels + positions (`declarations`) for actionable errors.
	- Supports metadata on:
	  - module types (`class`, `enum`, `typedef`, `abstract`),
	  - class/abstract-impl fields (methods/vars).
	- Canonical lane metadata is `@:haxeMetal`; `@:rustMetal` is also accepted as an alias
	  for compatibility while migrations are in progress.

	How
	- Walks `Context.getAllModuleTypes()` input.
	- Normalizes module names using the same base-type module resolution style used by viability analysis.
	- Deduplicates modules in a typed map and sorts output to guarantee deterministic ordering.
**/
class MetalIslandAnalyzer {
	public static function collect(moduleTypes:Array<ModuleType>):MetalIslandSnapshot {
		var moduleSet:Map<String, Bool> = [];
		var declarations:Array<MetalIslandDeclaration> = [];

		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					var module = moduleNameForClass(classType);
					addTypeDeclarationIfTagged(moduleSet, declarations, module, "class " + classPath(classType), classType.meta, classType.pos);
					collectFieldDeclarations(moduleSet, declarations, module, classType.name, classType.fields.get());
					collectFieldDeclarations(moduleSet, declarations, module, classType.name, classType.statics.get(), true);
				case TEnumDecl(enumRef):
					var enumType = enumRef.get();
					var module = moduleNameForEnum(enumType);
					addTypeDeclarationIfTagged(moduleSet, declarations, module, "enum " + enumPath(enumType), enumType.meta, enumType.pos);
				case TTypeDecl(typeRef):
					var typeDecl = typeRef.get();
					var module = moduleNameForTypedef(typeDecl);
					addTypeDeclarationIfTagged(moduleSet, declarations, module, "typedef " + typedefPath(typeDecl), typeDecl.meta, typeDecl.pos);
				case TAbstract(absRef):
					var abstractType = absRef.get();
					var module = moduleNameForAbstract(abstractType);
					addTypeDeclarationIfTagged(moduleSet, declarations, module, "abstract " + abstractPath(abstractType), abstractType.meta, abstractType.pos);
					if (abstractType.impl != null) {
						var impl = abstractType.impl.get();
						if (impl != null) {
							collectFieldDeclarations(moduleSet, declarations, module, abstractType.name, impl.fields.get());
							collectFieldDeclarations(moduleSet, declarations, module, abstractType.name, impl.statics.get(), true);
						}
					}
			}
		}

		var modules = [for (module in moduleSet.keys()) module];
		modules.sort(compareStrings);
		declarations.sort(compareDeclarations);
		return {
			modules: modules,
			declarations: declarations
		};
	}

	static function collectFieldDeclarations(moduleSet:Map<String, Bool>, declarations:Array<MetalIslandDeclaration>, module:String, owner:String,
			fields:Array<ClassField>, isStatic:Bool = false):Void {
		if (fields == null)
			return;
		var prefix = isStatic ? "static field " : "field ";
		for (field in fields) {
			if (field == null || field.meta == null)
				continue;
			if (!metaHasMetalLane(field.meta))
				continue;
			addDeclaration(moduleSet, declarations, module, prefix + owner + "." + field.name, field.pos);
		}
	}

	static function addTypeDeclarationIfTagged(moduleSet:Map<String, Bool>, declarations:Array<MetalIslandDeclaration>, module:String, source:String,
			meta:MetaAccess, pos:haxe.macro.Expr.Position):Void {
		if (meta == null)
			return;
		if (!metaHasMetalLane(meta))
			return;
		addDeclaration(moduleSet, declarations, module, source, pos);
	}

	static function addDeclaration(moduleSet:Map<String, Bool>, declarations:Array<MetalIslandDeclaration>, module:String, source:String,
			pos:haxe.macro.Expr.Position):Void {
		var normalized = normalizeModuleLabel(module);
		moduleSet.set(normalized, true);
		declarations.push({
			module: normalized,
			source: source,
			pos: pos
		});
	}

	static function metaHasMetalLane(meta:MetaAccess):Bool {
		for (entry in meta.get()) {
			if (entry.name == ":haxeMetal" || entry.name == "haxeMetal" || entry.name == ":rustMetal" || entry.name == "rustMetal")
				return true;
		}
		return false;
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

	static inline function enumPath(enumType:EnumType):String {
		return pathFromPack(enumType.pack, enumType.name);
	}

	static inline function typedefPath(typedefType:DefType):String {
		return pathFromPack(typedefType.pack, typedefType.name);
	}

	static inline function pathFromPack(pack:Array<String>, name:String):String {
		return pack == null || pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	static function compareDeclarations(a:MetalIslandDeclaration, b:MetalIslandDeclaration):Int {
		var moduleCmp = compareStrings(a.module, b.module);
		if (moduleCmp != 0)
			return moduleCmp;
		return compareStrings(a.source, b.source);
	}
}

typedef MetalIslandDeclaration = {
	var module:String;
	var source:String;
	var pos:haxe.macro.Expr.Position;
}

typedef MetalIslandSnapshot = {
	var modules:Array<String>;
	var declarations:Array<MetalIslandDeclaration>;
}
