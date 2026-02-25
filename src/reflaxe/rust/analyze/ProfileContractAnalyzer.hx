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
	  - Reflection/runtime-introspection module usage (`Reflect`, `Type`, `haxe.rtti.*`).
	  - Dynamic container boundary usage (`haxe.DynamicAccess`).
	  - Dynamic-fallback opt-ins that weaken rust-first/metal guarantees.
	  - Nullable-string override in metal (`rust_string_nullable`).
	  - Native target-surface imports in portable contract (warning by default, error in strict mode).

	How
	- Accepts:
	  - active profile
	  - used module paths (from type-usage analysis)
	  - user-authored native import hits
	  - policy toggles (`metalAllowFallback`, dynamic fallback defines, nullable-string override)
	- Returns a typed diagnostic bundle (`warnings`, `errors`, native import summary) so callers
	  decide presentation and deterministic report emission.
**/
class ProfileContractAnalyzer {
	public static function analyze(profile:RustProfile, modulePaths:Array<String>, metalAllowFallback:Bool, allowUnresolvedMonomorphDynamic:Bool,
			allowUnmappedCoreTypeDynamic:Bool, nullableStrings:Bool, nativeImportHits:Array<String>,
			portableNativeImportStrict:Bool):ProfileContractDiagnostics {
		var warnings:Array<String> = [];
		var errors:Array<String> = [];
		var normalizedNativeImportHits = normalizeSortedUnique(nativeImportHits);

		inline function addWarning(msg:String):Void {
			if (!warnings.contains(msg))
				warnings.push(msg);
		}

		inline function addError(msg:String):Void {
			if (!errors.contains(msg))
				errors.push(msg);
		}

		var reflectionHits:Array<String> = collectReflectionModules(modulePaths);
		if (reflectionHits.length > 0) {
			var joined = reflectionHits.join(", ");
			switch (profile) {
				case Metal:
					var msg = "metal profile forbids reflection/runtime-introspection modules; found: " + joined + ". Prefer typed fields/enums/interfaces.";
					if (metalAllowFallback)
						addWarning(msg + " (allowed because -D rust_metal_allow_fallback is set)")
					else
						addError(msg);
				case Portable:
			}
		}

		var dynamicAccessHits:Array<String> = collectDynamicAccessModules(modulePaths);
		if (dynamicAccessHits.length > 0) {
			var joined = dynamicAccessHits.join(", ");
			switch (profile) {
				case Metal:
					var msg = "metal profile forbids haxe.DynamicAccess runtime map semantics; found: "
						+ joined
						+ ". Prefer typed map surfaces (for example rust.HashMap<K,V>) at Rust-first boundaries.";
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

		if (nullableStrings) {
			switch (profile) {
				case Metal:
					var msg = "metal profile does not allow -D rust_string_nullable in metal-clean mode; keep Rust-owned String representation for Rust-first boundaries.";
					if (metalAllowFallback)
						addWarning(msg + " (allowed because -D rust_metal_allow_fallback is set)")
					else
						addError(msg);
				case Portable:
			}
		}

		if (profile == Portable && normalizedNativeImportHits.length > 0) {
			var msg = "portable contract imported native target modules: " + normalizedNativeImportHits.join(", ")
				+ ". This build is non-portable across targets.";
			if (portableNativeImportStrict)
				addError(msg + " (strict mode enabled via -D rust_portable_native_import_strict)")
			else
				addWarning(msg + " (set -D rust_portable_native_import_strict to enforce as an error)");
		}

		return {
			warnings: warnings,
			errors: errors,
			nativeImportHits: normalizedNativeImportHits
		};
	}

	static function normalizeSortedUnique(values:Array<String>):Array<String> {
		var out:Array<String> = [];
		if (values == null)
			return out;
		for (value in values) {
			if (value == null || value.length == 0)
				continue;
			if (!out.contains(value))
				out.push(value);
		}
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
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
		return path == "Reflect" || path == "Type" || StringTools.startsWith(path, "haxe.rtti.");
	}

	static function collectDynamicAccessModules(modulePaths:Array<String>):Array<String> {
		var out:Array<String> = [];
		for (path in modulePaths) {
			if (isDynamicAccessPath(path) && !out.contains(path))
				out.push(path);
		}
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	static inline function isDynamicAccessPath(path:String):Bool {
		return path == "haxe.DynamicAccess";
	}
}

typedef ProfileContractDiagnostics = {
	var warnings:Array<String>;
	var errors:Array<String>;
	var nativeImportHits:Array<String>;
};
