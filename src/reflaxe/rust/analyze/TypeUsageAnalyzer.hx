package reflaxe.rust.analyze;

import haxe.macro.Type;
import reflaxe.compiler.TypeUsageTracker.TypeOrModuleType;
import reflaxe.compiler.TypeUsageTracker.TypeUsageMap;
import reflaxe.helpers.TypeHelper;

using reflaxe.helpers.ModuleTypeHelper;

/**
	TypeUsageAnalyzer

	Why
	- `RustCompiler` needs a stable, typed way to convert Reflaxe's type-usage map into module
	  paths that downstream planners (runtime feature selection, reports, diagnostics) can consume.
	- Keeping this in `analyze/` avoids scattering `TypeOrModuleType` matching logic through emit
	  and compile stages.

	What
	- Traverses `TypeUsageMap` entries and extracts normalized module paths.
	- Supports both concrete module hits and Type entries that can be resolved to a module type.

	How
	- `collectInto(...)` appends discovered paths into a caller-provided map-set (`Map<String, Bool>`).
	- Paths are canonicalized through `ModuleType.getPath()` and deduplicated by map keys.
**/
class TypeUsageAnalyzer {
	public static function collectInto(usage:Null<TypeUsageMap>, sink:Map<String, Bool>):Void {
		if (usage == null)
			return;

		for (entries in usage) {
			if (entries == null)
				continue;
			for (entry in entries) {
				switch (entry) {
					case EModuleType(mt):
						sink.set(mt.getPath(), true);
					case EType(t):
						collectTypePathInto(t, sink);
				}
			}
		}
	}

	static function collectTypePathInto(t:Type, sink:Map<String, Bool>):Void {
		var mt = TypeHelper.toModuleType(t);
		if (mt != null)
			sink.set(mt.getPath(), true);
	}
}
