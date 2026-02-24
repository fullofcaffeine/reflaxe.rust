package reflaxe.rust.emit;

import reflaxe.rust.analyze.HxrtFeatureAnalyzer;

/**
	ProjectEmitter

	Why
	- Project-level outputs (Cargo metadata, runtime dependency wiring) are a distinct concern from
	  expression/type lowering and should live in `emit/`.
	- The compiler should pass typed inputs into emitters rather than embedding string assembly
	  policy inline.

	What
	- Selects final `hxrt` feature sets from module usage + define overrides.
	- Renders the `hxrt` dependency line for generated `Cargo.toml`.

	How
	- `selectHxrtFeatures(...)` applies precedence:
	  1) `rust_hxrt_default_features`
	  2) manual `rust_hxrt_features`
	  3) `rust_hxrt_no_feature_infer`
	  4) analyzer inference from used modules.
	- `renderHxrtDependencyLine(...)` converts that selection into Cargo TOML syntax.
**/
class ProjectEmitter {
	public static function selectHxrtFeatures(modulePaths:Array<String>, useDefaultFeatures:Bool, manualFeaturesRaw:Null<String>,
			disableInference:Bool):Array<String> {
		if (useDefaultFeatures)
			return [];

		var manual = parseManualFeatures(manualFeaturesRaw);
		if (manual.length > 0) {
			ensureCoreFeature(manual);
			manual.sort(compareStrings);
			return manual;
		}

		if (disableInference)
			return ["core"];

		var inferred = HxrtFeatureAnalyzer.inferFromModulePaths(modulePaths);
		ensureCoreFeature(inferred);
		inferred.sort(compareStrings);
		return inferred;
	}

	public static function renderHxrtDependencyLine(modulePaths:Array<String>, useDefaultFeatures:Bool, manualFeaturesRaw:Null<String>,
			disableInference:Bool):String {
		if (useDefaultFeatures)
			return 'hxrt = { path = "./hxrt" }';

		var features = selectHxrtFeatures(modulePaths, useDefaultFeatures, manualFeaturesRaw, disableInference);
		if (features.length == 0)
			return 'hxrt = { path = "./hxrt", default-features = false }';

		var quoted = [for (f in features) '"' + f + '"'].join(", ");
		return 'hxrt = { path = "./hxrt", default-features = false, features = [' + quoted + '] }';
	}

	static function parseManualFeatures(raw:Null<String>):Array<String> {
		var out:Array<String> = [];
		if (raw == null)
			return out;

		for (part in raw.split(",")) {
			var trimmed = StringTools.trim(part);
			if (trimmed.length == 0)
				continue;
			if (!out.contains(trimmed))
				out.push(trimmed);
		}
		out.sort(compareStrings);
		return out;
	}

	static inline function ensureCoreFeature(features:Array<String>):Void {
		if (!features.contains("core"))
			features.unshift("core");
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}
