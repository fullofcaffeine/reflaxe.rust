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
	- `inferFromModulePaths(...)` accepts already-collected module paths and returns a sorted,
	  deduplicated feature list.
**/
class HxrtFeatureAnalyzer {
	public static function inferFromModulePaths(modulePaths:Array<String>):Array<String> {
		var out:Array<String> = [];

		inline function add(feature:String):Void {
			if (!out.contains(feature))
				out.push(feature);
		}

		for (path in modulePaths) {
			if (path == "Date" || StringTools.startsWith(path, "DateTools") || StringTools.startsWith(path, "hxrt.date"))
				add("date");

			if (path == "haxe.Json" || StringTools.startsWith(path, "haxe.json.") || StringTools.startsWith(path, "hxrt.json"))
				add("json");

			if (StringTools.startsWith(path, "sys.net.") || StringTools.startsWith(path, "hxrt.net."))
				add("net");

			if (StringTools.startsWith(path, "sys.ssl.") || StringTools.startsWith(path, "hxrt.ssl."))
				add("ssl");

			if (StringTools.startsWith(path, "sys.thread.") || StringTools.startsWith(path, "hxrt.thread."))
				add("thread");

			if (StringTools.startsWith(path, "rust.concurrent.") || StringTools.startsWith(path, "hxrt.concurrent."))
				add("thread");

			if (path == "rust.async.Tasks" || path == "rust.async.Task")
				add("thread");

			if (StringTools.startsWith(path, "sys.db.") || StringTools.startsWith(path, "hxrt.db."))
				add("db");

			if (path == "sys.FileSystem"
				|| path == "sys.io.File"
				|| path == "sys.io.FileInput"
				|| path == "sys.io.FileOutput"
				|| StringTools.startsWith(path, "hxrt.fs."))
				add("fs");

			if (path == "sys.io.Process" || StringTools.startsWith(path, "hxrt.process."))
				add("process");

			if (path == "haxe.io.Error" || StringTools.startsWith(path, "haxe.io.Input") || StringTools.startsWith(path, "haxe.io.Output"))
				add("io");

			if (StringTools.startsWith(path, "rust.async.") || StringTools.startsWith(path, "hxrt.async_"))
				add("async");

			if (path == "rust.async.TokioRuntime")
				add("async_tokio");
		}

		if (hasDefine("async_tokio_adapter"))
			add("async_tokio");

		// Internal dependency edges so selective runtime slices remain compileable.
		if (out.contains("net")) {
			add("io");
			add("ssl");
		}
		if (out.contains("ssl"))
			add("io");
		if (out.contains("process"))
			add("fs");
		if (out.contains("async_tokio"))
			add("async");

		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	static inline function hasDefine(name:String):Bool {
		#if macro
		return Context.defined(name);
		#else
		return false;
		#end
	}
}
