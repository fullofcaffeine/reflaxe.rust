package reflaxe.rust.analyze;

#if macro
import haxe.macro.Context;
#end

/**
	HxrtFeatureAnalyzer

	Why
	- Runtime feature inference should be deterministic and reusable from emit/report code.
	- `RustCompiler` should not own backend dependency-planning rules inline.

	What
	- Maps used Haxe/Rust module paths to `hxrt` Cargo feature names.
	- Applies minimal internal dependency edges so selected feature sets are compileable.

	How
	- `inferWithReasons(...)` accepts already-collected module paths and returns a deterministic
	  feature list plus typed provenance entries.
	- `inferFromModulePaths(...)` remains a convenience wrapper that returns only feature names.
**/
class HxrtFeatureAnalyzer {
	public static function inferFromModulePaths(modulePaths:Array<String>):Array<String> {
		return inferWithReasons(modulePaths).features;
	}

	public static function inferWithReasons(modulePaths:Array<String>):HxrtFeatureInference {
		var out:Array<String> = [];
		var reasonsByFeature:Map<String, Array<HxrtFeatureReason>> = [];

		function addReason(feature:String, sourceKind:String, source:String):Void {
			var list = reasonsByFeature.get(feature);
			if (list == null) {
				list = [];
				reasonsByFeature.set(feature, list);
			}
			for (entry in list) {
				if (entry.sourceKind == sourceKind && entry.source == source)
					return;
			}
			list.push({
				feature: feature,
				sourceKind: sourceKind,
				source: source
			});
		}

		inline function add(feature:String, sourceKind:String, source:String):Void {
			if (!out.contains(feature))
				out.push(feature);
			addReason(feature, sourceKind, source);
		}

		for (path in modulePaths) {
			if (path == "Date" || StringTools.startsWith(path, "DateTools") || StringTools.startsWith(path, "hxrt.date"))
				add("date", "module", path);

			if (path == "haxe.Json" || StringTools.startsWith(path, "haxe.json.") || StringTools.startsWith(path, "hxrt.json"))
				add("json", "module", path);

			if (StringTools.startsWith(path, "sys.net.") || StringTools.startsWith(path, "hxrt.net."))
				add("net", "module", path);

			if (StringTools.startsWith(path, "sys.ssl.") || StringTools.startsWith(path, "hxrt.ssl."))
				add("ssl", "module", path);

			if (StringTools.startsWith(path, "sys.thread.") || StringTools.startsWith(path, "hxrt.thread."))
				add("thread", "module", path);

			if (StringTools.startsWith(path, "rust.concurrent.") || StringTools.startsWith(path, "hxrt.concurrent."))
				add("thread", "module", path);

			if (path == "rust.async.Tasks" || path == "rust.async.Task")
				add("thread", "module", path);

			if (StringTools.startsWith(path, "sys.db.") || StringTools.startsWith(path, "hxrt.db."))
				add("db", "module", path);

			if (path == "sys.FileSystem"
				|| path == "sys.io.File"
				|| path == "sys.io.FileInput"
				|| path == "sys.io.FileOutput"
				|| StringTools.startsWith(path, "hxrt.fs."))
				add("fs", "module", path);

			if (path == "sys.io.Process" || StringTools.startsWith(path, "hxrt.process."))
				add("process", "module", path);

			if (path == "haxe.io.Error" || StringTools.startsWith(path, "haxe.io.Input") || StringTools.startsWith(path, "haxe.io.Output"))
				add("io", "module", path);

			if (StringTools.startsWith(path, "rust.async.") || StringTools.startsWith(path, "hxrt.async_"))
				add("async", "module", path);

			if (path == "rust.async.TokioRuntime")
				add("async_tokio", "module", path);
		}

		if (hasDefine("async_tokio_adapter"))
			add("async_tokio", "define", "async_tokio_adapter");

		// Internal dependency edges so selective runtime slices remain compileable.
		if (out.contains("net")) {
			add("io", "dependency_edge", "net->io");
			add("ssl", "dependency_edge", "net->ssl");
		}
		if (out.contains("ssl"))
			add("io", "dependency_edge", "ssl->io");
		if (out.contains("process"))
			add("fs", "dependency_edge", "process->fs");
		if (out.contains("async_tokio"))
			add("async", "dependency_edge", "async_tokio->async");

		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		var reasons:Array<HxrtFeatureReason> = [];
		for (feature in out) {
			var entries = reasonsByFeature.get(feature);
			if (entries == null)
				continue;
			entries.sort((a, b) -> {
				var kindOrder = compareStrings(a.sourceKind, b.sourceKind);
				if (kindOrder != 0)
					return kindOrder;
				return compareStrings(a.source, b.source);
			});
			for (entry in entries)
				reasons.push(entry);
		}
		return {
			features: out,
			reasons: reasons
		};
	}

	static inline function hasDefine(name:String):Bool {
		#if macro
		return Context.defined(name);
		#else
		return false;
		#end
	}

	static inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}

typedef HxrtFeatureReason = {
	var feature:String;
	var sourceKind:String;
	var source:String;
};

typedef HxrtFeatureInference = {
	var features:Array<String>;
	var reasons:Array<HxrtFeatureReason>;
};
