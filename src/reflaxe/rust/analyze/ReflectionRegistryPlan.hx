package reflaxe.rust.analyze;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Position;
import haxe.macro.Type;

typedef ReflectionClassEntry = {
	var runtimeName:String;
	var stableKey:String;
	var stableId:Int;
	var sourceModule:String;
	var pos:Position;
};

typedef ReflectionEnumEntry = {
	var runtimeName:String;
	var stableKey:String;
	var stableId:Int;
	var sourceModule:String;
	var constructors:Array<String>;
	var pos:Position;
};

enum ReflectionRegistryIssueKind {
	DuplicateRuntimeName;
	DuplicateStableId;
}

typedef ReflectionRegistryIssue = {
	var kind:ReflectionRegistryIssueKind;
	var message:String;
	var pos:Position;
};

typedef ReflectionRegistryPlanData = {
	var classes:Array<ReflectionClassEntry>;
	var enums:Array<ReflectionEnumEntry>;
	var issues:Array<ReflectionRegistryIssue>;
};

/**
	Builds the compiler-owned closed reflection registry.

	Why
	- `Type.resolveClass` and related admitted operations need runtime lookup, but the compiler already
	  knows the complete set of target declarations. A general runtime reflection VM would duplicate
	  that knowledge, increase `hxrt`, and make unsupported open-world behavior look available.
	- Haxe runtime names deliberately omit the containing module for secondary types. Deriving names
	  from the source module therefore produces observable errors such as `Main.Helper` instead of
	  `Helper`.
	- The existing `Class<T>` / `Enum<T>` carrier is a stable `u32` id. Name or id collisions must fail
	  during compilation rather than resolving nondeterministically at runtime.

	What
	- Produces immutable, deterministically sorted public emitted-Haxe class and enum entries from the typed target
	  module set.
	- Records enum constructors in Haxe declaration order.
	- Reports duplicate runtime names and cross-registry stable-id collisions as typed issues for the
	  compiler diagnostic boundary.

	How
	- Runtime names use `pack + declaration name`; the Haxe module name is never included.
	- Extern/native declarations, abstract implementation classes, and explicitly private declarations
	  are omitted from dynamic name resolution. Direct type-expression operations remain
	  compiler-lowered and can still report their exact static name.
	- The caller supplies the existing stable-id function so reflection and dynamic subtype handling
	  cannot drift to parallel identity schemes.
**/
class ReflectionRegistryPlan {
	public static function build(moduleTypes:Array<ModuleType>, stableIdForKey:String->Int):ReflectionRegistryPlanData {
		var classes:Array<ReflectionClassEntry> = [];
		var enums:Array<ReflectionEnumEntry> = [];
		var issues:Array<ReflectionRegistryIssue> = [];
		var classNames:Map<String, ReflectionClassEntry> = [];
		var enumNames:Map<String, ReflectionEnumEntry> = [];
		var ids:Map<String, {stableKey:String, runtimeName:String, pos:Position}> = [];

		function registerId(stableKey:String, runtimeName:String, stableId:Int, pos:Position):Void {
			var idKey = Std.string(stableId);
			var previous = ids.get(idKey);
			if (previous == null) {
				ids.set(idKey, {stableKey: stableKey, runtimeName: runtimeName, pos: pos});
				return;
			}
			if (previous.stableKey == stableKey)
				return;
			issues.push({
				kind: DuplicateStableId,
				message: "closed reflection registry stable-id collision between `" + previous.runtimeName + "` and `" + runtimeName + "`",
				pos: pos
			});
		}

		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef): {
						var classType = classRef.get();
						if (classType == null || classType.isExtern || classType.isPrivate || isAbstractImplementation(classType))
							continue;
						var runtimeName = runtimeName(classType.pack, classType.name);
						var stableKey = stableKey(classType.pack, classType.name);
						var entry:ReflectionClassEntry = {
							runtimeName: runtimeName,
							stableKey: stableKey,
							stableId: stableIdForKey(stableKey),
							sourceModule: classType.module,
							pos: classType.pos
						};
						var previous = classNames.get(runtimeName);
						if (previous != null && previous.sourceModule != entry.sourceModule) {
							issues.push({
								kind: DuplicateRuntimeName,
								message: "closed reflection registry has more than one public class named `" + runtimeName + "`",
								pos: classType.pos
							});
							continue;
						}
						if (previous == null) {
							classNames.set(runtimeName, entry);
							classes.push(entry);
							registerId(stableKey, runtimeName, entry.stableId, classType.pos);
						}
					}
				case TEnumDecl(enumRef): {
						var enumType = enumRef.get();
						if (enumType == null || enumType.isExtern || enumType.isPrivate)
							continue;
						var runtimeName = runtimeName(enumType.pack, enumType.name);
						var stableKey = stableKey(enumType.pack, enumType.name);
						var constructors = enumConstructors(enumType);
						var entry:ReflectionEnumEntry = {
							runtimeName: runtimeName,
							stableKey: stableKey,
							stableId: stableIdForKey(stableKey),
							sourceModule: enumType.module,
							constructors: constructors,
							pos: enumType.pos
						};
						var previous = enumNames.get(runtimeName);
						if (previous != null && previous.sourceModule != entry.sourceModule) {
							issues.push({
								kind: DuplicateRuntimeName,
								message: "closed reflection registry has more than one public enum named `" + runtimeName + "`",
								pos: enumType.pos
							});
							continue;
						}
						if (previous == null) {
							enumNames.set(runtimeName, entry);
							enums.push(entry);
							registerId(stableKey, runtimeName, entry.stableId, enumType.pos);
						}
					}
				case _:
			}
		}

		classes.sort((left, right) -> compareStrings(left.runtimeName, right.runtimeName));
		enums.sort((left, right) -> compareStrings(left.runtimeName, right.runtimeName));
		issues.sort((left, right) -> compareStrings(left.message, right.message));
		return {classes: classes, enums: enums, issues: issues};
	}

	static function isAbstractImplementation(classType:ClassType):Bool {
		return switch (classType.kind) {
			case KAbstractImpl(_): true;
			case _: false;
		}
	}

	static function enumConstructors(enumType:EnumType):Array<String> {
		var fields:Array<{name:String, index:Int}> = [];
		for (name in enumType.constructs.keys()) {
			var field = enumType.constructs.get(name);
			if (field != null)
				fields.push({name: field.name, index: field.index});
		}
		fields.sort((left, right) -> left.index == right.index ? compareStrings(left.name, right.name) : left.index - right.index);
		return fields.map(field -> field.name);
	}

	static inline function runtimeName(pack:Array<String>, name:String):String {
		return pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	static inline function stableKey(pack:Array<String>, name:String):String {
		return pack.join(".") + "." + name;
	}

	static inline function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
