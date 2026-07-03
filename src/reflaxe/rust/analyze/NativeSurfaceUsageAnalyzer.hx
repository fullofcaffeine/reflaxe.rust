package reflaxe.rust.analyze;

/**
	Serialized source for a typed native-surface hit.

	Why
	- Contract reports need to distinguish old source-text import scanning from typed compiler
	  usage. The typed signal catches aliases, fully-qualified references, and generated references
	  once they appear in the typed usage map.

	What
	- `typed_module_usage` means the hit came from Reflaxe/Haxe typed type usage, not from scanning
	  `import` lines in source text.

	How
	- Values serialize directly into `contract_report.*`.
**/
enum abstract NativeSurfaceSourceKind(String) to String {
	var TypedModuleUsage = "typed_module_usage";
}

/**
	Serialized kind for a native target surface.

	Why
	- `rust.*` is the first-class native surface for this backend, while other target namespaces are
	  still target-native portability hazards in Haxe portable code.
	- A stable enum lets reports explain the distinction without relying on prose-only messages.

	What
	- `rust_native` means the consumed surface belongs to this backend's Rust-native API.
	- `target_native` means a different Haxe target-native namespace such as `cpp.*` or `js.*`.

	How
	- Values serialize directly into typed native import report entries.
**/
enum abstract NativeSurfaceKind(String) to String {
	var RustNative = "rust_native";
	var TargetNative = "target_native";
}

/**
	Typed contract-report entry for a consumed native target module.

	Why
	- Source-text import scans miss aliases, fully-qualified references, macro/generated usage, and
	  metadata-driven references. Capability-driven boundary reporting needs a typed ledger.
	- Keeping this as a separate entry preserves the legacy `nativeImportHits` field while giving
	  CI and future diagnostics a stronger source of truth.

	What
	- `modulePath`: normalized Haxe module path observed in typed usage.
	- `nativeFamily`: target namespace family (`rust`, `cpp`, `js`, etc.).
	- `surfaceKind`: whether this is this backend's Rust-native surface or another native target
	  namespace.
	- `sourceKind`: provenance of the hit.

	How
	- `NativeSurfaceUsageAnalyzer.collectTypedNativeImportHits(...)` builds deterministic entries
	  from `TypeUsageAnalyzer` module paths after canonicalizing backend/native suffixes back to the
	  Haxe surface module.
**/
typedef TypedNativeImportHit = {
	var modulePath:String;
	var nativeFamily:String;
	var surfaceKind:NativeSurfaceKind;
	var sourceKind:NativeSurfaceSourceKind;
};

private typedef NativeTargetPrefix = {
	var prefix:String;
	var family:String;
	var surfaceKind:NativeSurfaceKind;
};

/**
	NativeSurfaceUsageAnalyzer

	Why
	- Portable/native boundary reports should be typed compiler artifacts, not just regex hits over
	  source files.
	- This is the first bridge from typed module usage into explicit native-surface accounting.

	What
	- Classifies consumed module paths whose leading namespace is target-native (`rust.*`, `cpp.*`,
	  `js.*`, etc.).
	- Produces stable, sorted `TypedNativeImportHit` records for `contract_report.*`.

	How
	- The caller passes module paths from `TypeUsageAnalyzer`.
	- Matching is prefix-based but over typed module paths, so aliases and fully-qualified uses
	  resolve to the same report entry.
	- Backend-native suffixes from `@:native` paths and type-parameter pseudo paths are collapsed
	  to the first Haxe type segment (`rust.Option.T` -> `rust.Option`).
**/
class NativeSurfaceUsageAnalyzer {
	static final TARGET_PREFIXES:Array<NativeTargetPrefix> = [
		{prefix: "rust.", family: "rust", surfaceKind: RustNative},
		{prefix: "cpp.", family: "cpp", surfaceKind: TargetNative},
		{prefix: "cs.", family: "cs", surfaceKind: TargetNative},
		{prefix: "java.", family: "java", surfaceKind: TargetNative},
		{prefix: "jvm.", family: "jvm", surfaceKind: TargetNative},
		{prefix: "python.", family: "python", surfaceKind: TargetNative},
		{prefix: "php.", family: "php", surfaceKind: TargetNative},
		{prefix: "lua.", family: "lua", surfaceKind: TargetNative},
		{prefix: "js.", family: "js", surfaceKind: TargetNative},
		{prefix: "flash.", family: "flash", surfaceKind: TargetNative},
		{prefix: "hl.", family: "hl", surfaceKind: TargetNative},
		{prefix: "neko.", family: "neko", surfaceKind: TargetNative}
	];

	public static function collectTypedNativeImportHits(modulePaths:Array<String>):Array<TypedNativeImportHit> {
		var out:Array<TypedNativeImportHit> = [];
		var seen:Map<String, Bool> = [];
		if (modulePaths == null)
			return out;

		for (rawModulePath in modulePaths) {
			var modulePath = normalizeTypedModulePath(rawModulePath);
			var prefix = nativeTargetPrefixForModulePath(modulePath);
			if (prefix == null)
				continue;
			if (seen.exists(modulePath))
				continue;
			seen.set(modulePath, true);
			out.push({
				modulePath: modulePath,
				nativeFamily: prefix.family,
				surfaceKind: prefix.surfaceKind,
				sourceKind: TypedModuleUsage
			});
		}
		out.sort(compareHits);
		return out;
	}

	public static function isNativeTargetModulePath(modulePath:String):Bool {
		return nativeTargetPrefixForModulePath(modulePath) != null;
	}

	static function nativeTargetPrefixForModulePath(modulePath:String):Null<NativeTargetPrefix> {
		if (modulePath == null || modulePath.length == 0)
			return null;
		for (prefix in TARGET_PREFIXES) {
			if (StringTools.startsWith(modulePath, prefix.prefix))
				return prefix;
		}
		return null;
	}

	static function normalizeTypedModulePath(modulePath:String):String {
		if (modulePath == null || modulePath.length == 0)
			return "";

		var cleaned = modulePath;
		var genericIndex = cleaned.indexOf("<");
		if (genericIndex >= 0)
			cleaned = cleaned.substr(0, genericIndex);
		var rustPathIndex = cleaned.indexOf("::");
		if (rustPathIndex >= 0)
			cleaned = cleaned.substr(0, rustPathIndex);

		var segments = cleaned.split(".");
		var out:Array<String> = [];
		for (segment in segments) {
			if (segment.length == 0)
				break;
			out.push(segment);
			if (startsWithUppercase(segment))
				break;
		}
		return out.length == 0 ? cleaned : out.join(".");
	}

	static function startsWithUppercase(value:String):Bool {
		if (value == null || value.length == 0)
			return false;
		var code = value.charCodeAt(0);
		return code >= 65 && code <= 90;
	}

	static function compareHits(a:TypedNativeImportHit, b:TypedNativeImportHit):Int {
		var byModule = compareStrings(a.modulePath, b.modulePath);
		if (byModule != 0)
			return byModule;
		return compareStrings(a.nativeFamily, b.nativeFamily);
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}
