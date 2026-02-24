package reflaxe.rust.emit;

import reflaxe.rust.analyze.HxrtFeatureAnalyzer;
import reflaxe.rust.analyze.HxrtFeatureAnalyzer.HxrtFeatureReason;

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
	- `selectHxrtFeatureSelection(...)` applies precedence:
	  1) `rust_hxrt_default_features`
	  2) manual `rust_hxrt_features`
	  3) `rust_hxrt_no_feature_infer`
	  4) analyzer inference from used modules.
	- `selectHxrtFeatures(...)` remains a convenience wrapper for legacy callsites.
	- `renderHxrtDependencyLine(...)` converts that selection into Cargo TOML syntax.
**/
class ProjectEmitter {
	public static function selectHxrtFeatureSelection(modulePaths:Array<String>, useDefaultFeatures:Bool, manualFeaturesRaw:Null<String>,
			disableInference:Bool):HxrtFeatureSelection {
		var manual = parseManualFeatures(manualFeaturesRaw);

		if (useDefaultFeatures) {
			return {
				mode: "default_features",
				features: [],
				manualFeatures: manual,
				useDefaultFeatures: true,
				disableInference: disableInference,
				reasons: []
			};
		}

		if (manual.length > 0) {
			var features = manual.copy();
			var reasons:Array<HxrtFeatureReason> = [
				for (feature in features)
					{
						feature: feature,
						sourceKind: "define",
						source: "rust_hxrt_features"
					}
			];
			ensureCoreFeatureWithReason(features, reasons, "dependency_edge", "manual->core");
			features.sort(compareStrings);
			sortReasons(reasons);
			return {
				mode: "selective",
				features: features,
				manualFeatures: manual,
				useDefaultFeatures: false,
				disableInference: disableInference,
				reasons: reasons
			};
		}

		if (disableInference) {
			return {
				mode: "selective",
				features: ["core"],
				manualFeatures: manual,
				useDefaultFeatures: false,
				disableInference: true,
				reasons: [
					{
						feature: "core",
						sourceKind: "define",
						source: "rust_hxrt_no_feature_infer"
					}
				]
			};
		}

		var inferred = HxrtFeatureAnalyzer.inferWithReasons(modulePaths);
		var features = inferred.features.copy();
		var reasons = inferred.reasons.copy();
		ensureCoreFeatureWithReason(features, reasons, "dependency_edge", "baseline->core");
		features.sort(compareStrings);
		sortReasons(reasons);
		return {
			mode: "selective",
			features: features,
			manualFeatures: manual,
			useDefaultFeatures: false,
			disableInference: false,
			reasons: reasons
		};
	}

	public static function selectHxrtFeatures(modulePaths:Array<String>, useDefaultFeatures:Bool, manualFeaturesRaw:Null<String>,
			disableInference:Bool):Array<String> {
		return selectHxrtFeatureSelection(modulePaths, useDefaultFeatures, manualFeaturesRaw, disableInference).features;
	}

	public static function renderHxrtDependencyLine(modulePaths:Array<String>, useDefaultFeatures:Bool, manualFeaturesRaw:Null<String>,
			disableInference:Bool):String {
		var selection = selectHxrtFeatureSelection(modulePaths, useDefaultFeatures, manualFeaturesRaw, disableInference);
		if (selection.useDefaultFeatures)
			return 'hxrt = { path = "./hxrt" }';

		var features = selection.features;
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

	static function ensureCoreFeatureWithReason(features:Array<String>, reasons:Array<HxrtFeatureReason>, sourceKind:String, source:String):Void {
		if (features.contains("core"))
			return;
		features.unshift("core");
		reasons.push({
			feature: "core",
			sourceKind: sourceKind,
			source: source
		});
	}

	static function sortReasons(reasons:Array<HxrtFeatureReason>):Void {
		reasons.sort((a, b) -> {
			var featureOrder = compareStrings(a.feature, b.feature);
			if (featureOrder != 0)
				return featureOrder;
			var kindOrder = compareStrings(a.sourceKind, b.sourceKind);
			if (kindOrder != 0)
				return kindOrder;
			return compareStrings(a.source, b.source);
		});
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}

typedef HxrtFeatureSelection = {
	var mode:String;
	var features:Array<String>;
	var manualFeatures:Array<String>;
	var useDefaultFeatures:Bool;
	var disableInference:Bool;
	var reasons:Array<HxrtFeatureReason>;
};
