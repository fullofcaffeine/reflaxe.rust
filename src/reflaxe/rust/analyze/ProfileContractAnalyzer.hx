package reflaxe.rust.analyze;

import reflaxe.rust.RustProfile;

/**
	ProfileContractAnalyzer

	Why
	- Profiles should be more than output style toggles; they must communicate and enforce boundary
	  contracts with actionable diagnostics.
	- The compiler needs one typed place to evaluate those contracts from usage data and opt-in
	  compatibility flags.

	What
	- Produces warning/error diagnostics for profile-boundary violations.
	- Current contract checks:
	  - Reflection module usage (`Reflect`, `haxe.rtti.*`).
	  - Dynamic-fallback opt-ins that weaken rust-first/metal guarantees.

	How
	- Accepts:
	  - active profile
	  - used module paths (from type-usage analysis)
	  - policy toggles (`metalAllowFallback`, dynamic fallback defines)
	- Returns a typed diagnostic bundle (`warnings`, `errors`) so callers decide presentation.
**/
class ProfileContractAnalyzer {
	public static function analyze(profile:RustProfile, modulePaths:Array<String>, metalAllowFallback:Bool, allowUnresolvedMonomorphDynamic:Bool,
			allowUnmappedCoreTypeDynamic:Bool):ProfileContractDiagnostics {
		var warnings:Array<String> = [];
		var errors:Array<String> = [];

		inline function addWarning(msg:String):Void {
			if (!warnings.contains(msg))
				warnings.push(msg);
		}

		inline function addError(msg:String):Void {
			if (!errors.contains(msg))
				errors.push(msg);
		}

		var reflectHits:Array<String> = collectReflectionModules(modulePaths);
		if (reflectHits.length > 0) {
			var joined = reflectHits.join(", ");
			switch (profile) {
				case Metal:
					var msg = "metal profile forbids reflection modules; found: " + joined + ". Prefer typed fields/enums/interfaces.";
					if (metalAllowFallback)
						addWarning(msg + " (allowed because -D rust_metal_allow_fallback is set)")
					else
						addError(msg);
				case Portable:
			}
		}

		if (allowUnresolvedMonomorphDynamic) {
			switch (profile) {
				case Metal:
					var msg = "metal profile does not allow -D rust_allow_unresolved_monomorph_dynamic; keep monomorph fallbacks typed.";
					if (metalAllowFallback)
						addWarning(msg + " (allowed because -D rust_metal_allow_fallback is set)")
					else
						addError(msg);
				case Portable:
			}
		}

		if (allowUnmappedCoreTypeDynamic) {
			switch (profile) {
				case Metal:
					var msg = "metal profile does not allow -D rust_allow_unmapped_coretype_dynamic; map core types explicitly.";
					if (metalAllowFallback)
						addWarning(msg + " (allowed because -D rust_metal_allow_fallback is set)")
					else
						addError(msg);
				case Portable:
			}
		}

		return {warnings: warnings, errors: errors};
	}

	static function collectReflectionModules(modulePaths:Array<String>):Array<String> {
		var out:Array<String> = [];
		for (path in modulePaths) {
			if (isReflectionPath(path) && !out.contains(path))
				out.push(path);
		}
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	static inline function isReflectionPath(path:String):Bool {
		return path == "Reflect" || StringTools.startsWith(path, "haxe.rtti.");
	}
}

typedef ProfileContractDiagnostics = {
	var warnings:Array<String>;
	var errors:Array<String>;
};
