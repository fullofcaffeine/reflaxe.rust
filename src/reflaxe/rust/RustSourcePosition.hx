package reflaxe.rust;

import haxe.io.Bytes;
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import sys.FileSystem;
import sys.io.File;

/** Exact UTF-8 byte range corresponding to one Haxe compiler position. */
typedef RustUtf8ByteRange = {
	var startByte:Int;
	var endByte:Int;
}

/**
	Converts Haxe source-character offsets to the UTF-8 byte coordinates used by reports.

	Why
	- `Context.getPosInfos()` exposes offsets in Haxe source-string coordinates. Those coordinates
	  differ from UTF-8 bytes as soon as text before or inside a span contains a multibyte character.
	- Runtime plans and Rust source maps promise byte ranges, while `Context.makePosition()` expects the
	  original Haxe coordinates. Passing either representation to the other API silently misattributes
	  diagnostics.

	What
	- Resolves a source file without exposing its absolute path, caches its immutable text for the
	  current compilation, and converts in both directions at validated character boundaries.
	- `utf8ByteRange` is used for report/source-map storage; `haxePosition` converts a stored byte range
	  back before asking Haxe to display a diagnostic.

	How
	- Prefixes are encoded with `Bytes.ofString`, so the calculation follows Haxe's own string-index
	  semantics while measuring the exact UTF-8 bytes that artifacts serialize.
	- `reset` is called at compilation start to prevent compile-server state from retaining stale file
	  contents. Standalone analyzers may call it before beginning a new complete collection.
**/
class RustSourcePosition {
	static var sources:Map<String, RustSourcePositionIndex> = [];
	static var realSourceByStablePath:Map<String, String> = [];
	static var displayLocationByStableRange:Map<String, RustRememberedDisplayLocation> = [];

	/** Clears cached source text at the start of a compilation-server request. */
	public static function reset():Void {
		sources = [];
		realSourceByStablePath = [];
		displayLocationByStableRange = [];
	}

	/**
		Creates a private report path while retaining a compiler-only route back to the real file.

		Why / What / How
		- Haxe may report an absolute file when the project uses an absolute classpath. Serializing that
		  spelling would leak a machine-local checkout path, but inventing an unrelated path prevents a
		  later diagnostic from recovering the exact line and column.
		- Prefer the real project-relative or classpath-relative spelling. If neither can be proven, use a
		  deterministic `classpath/...` name and remember its real target only in this compilation.
		- The private map is reset between compile-server requests and is never written to generated files.
	**/
	public static function stableSourcePath(rawFile:String, modulePath:String):Null<String> {
		var resolved = resolveSource(rawFile);
		if (resolved == null)
			return null;
		var roots:Array<{path:String, external:Bool}> = [];
		var cwd = canonicalDirectory(Sys.getCwd());
		if (cwd != null)
			roots.push({path: cwd, external: false});
		#if macro
		for (classPath in Context.getClassPath()) {
			if (classPath == null || classPath.length == 0)
				continue;
			var root = Path.isAbsolute(classPath) ? classPath : Path.join([Sys.getCwd(), classPath]);
			var canonical = canonicalDirectory(root);
			if (canonical != null) {
				var alreadyKnown = false;
				for (known in roots)
					if (known.path == canonical) {
						alreadyKnown = true;
						break;
					}
				if (!alreadyKnown)
					roots.push({path: canonical, external: cwd == null || canonical != cwd});
			}
		}
		#end
		for (root in roots) {
			var prefix = ensureTrailingSlash(root.path);
			if (StringTools.startsWith(resolved, prefix)) {
				var relative = resolved.substr(prefix.length).split("\\").join("/");
				// A real classpath-relative spelling lets Haxe reconnect the private report range to
				// its already loaded source and print the exact line/columns. Add a synthetic prefix
				// only when that spelling resolves to a different file (for example a shadowed path).
				var stable = relative;
				if (root.external && resolveSource(relative) != resolved)
					stable = "classpath/" + relative;
				if (isSafeRelative(stable)) {
					registerStableSource(stable, resolved);
					return stable;
				}
			}
		}

		var sourceName = Path.withoutDirectory(resolved);
		if (sourceName == null || sourceName.length == 0)
			sourceName = "Source.hx";
		var segments = modulePath == null ? [] : modulePath.split(".");
		if (segments.length > 0)
			segments.pop();
		segments.unshift("classpath");
		segments.push(sourceName);
		var stable = segments.join("/");
		if (!isSafeRelative(stable))
			return null;
		registerStableSource(stable, resolved);
		return stable;
	}

	/** Converts a validated Haxe source-string range into its exact UTF-8 byte range. */
	public static function utf8ByteRange(rawFile:String, start:Int, end:Int):Null<RustUtf8ByteRange> {
		var index = sourceIndex(rawFile);
		if (index == null)
			return null;
		return index.byteRange(start, end);
	}

	/**
		Keeps Haxe's exact display range beside one private serialized byte range.

		Why / What / How
		- Rebuilding a position from a short classpath-relative name loses Haxe's internal link to an
		  externally loaded source file, so the later error can lose its line and character range.
		- Convert the already-validated private UTF-8 range back through this helper's own source index, then
		  retain only the one-based line and character numbers. No original machine path is stored in this
		  location record or written to an artifact.
		- `inlineDiagnosticPrefix` uses the saved range only when the private path is not a real project file
		  that Haxe's classic formatter can read directly.
	**/
	public static function rememberHaxePosition(stableFile:String, startByte:Int, endByte:Int):Void {
		if (!isSafeRelative(stableFile) || startByte < 0 || endByte < startByte)
			throw "Remembered Haxe positions require a private path and valid byte range";
		var key = positionKey(stableFile, startByte, endByte);
		if (displayLocationByStableRange.exists(key))
			return;
		var index = sourceIndex(stableFile);
		if (index == null)
			throw "Remembered Haxe position source could not be resolved";
		displayLocationByStableRange.set(key, index.displayLocation(startByte, endByte));
	}

	/** Converts a stored UTF-8 byte range back into the coordinates required by Haxe diagnostics. */
	public static function haxePosition(rawFile:String, startByte:Int, endByte:Int):Null<Position> {
		var resolved = resolveSource(rawFile);
		if (resolved == null)
			return null;
		var index = sourceIndex(resolved);
		if (index == null)
			return null;
		var start = index.characterOffset(startByte);
		var end = index.characterOffset(endByte);
		if (start == null || end == null)
			return null;
		return Context.makePosition({file: rawFile, min: start, max: end});
	}

	/**
		Returns a private file/line prefix when Haxe cannot format the private path itself.

		Why / What / How
		- Haxe 4.3.7 has no public API for aliasing an already loaded external source file under a private
		  display name. A fresh position keeps the safe name and exact offsets, but the classic formatter
		  omits its file/line prefix when that name is not a real file under the working directory.
		- For that external-classpath case only, return the private path plus the one-based range captured
		  from the original position. Callers prepend it to the diagnostic text while still passing Haxe the
		  safe synthetic position for machine-readable consumers.
		- Project-relative files return `null` because Haxe already formats them normally.
	**/
	public static function inlineDiagnosticPrefix(stableFile:String, startByte:Int, endByte:Int):Null<String> {
		var resolved = realSourceByStablePath.get(stableFile);
		if (resolved == null)
			return null;
		var localCandidate = Path.normalize(Path.join([Sys.getCwd(), stableFile]));
		if (FileSystem.exists(localCandidate)
			&& !FileSystem.isDirectory(localCandidate)
			&& FileSystem.fullPath(localCandidate).split("\\").join("/") == resolved)
			return null;
		var location = displayLocationByStableRange.get(positionKey(stableFile, startByte, endByte));
		if (location == null)
			return null;
		if (location.startLine == location.endLine) {
			var label = location.startColumn == location.endColumn ? "character " + location.startColumn : "characters " + location.startColumn + "-"
				+ location.endColumn;
			return stableFile + ":" + location.startLine + ": " + label;
		}
		return stableFile + ": lines " + location.startLine + "-" + location.endLine;
	}

	/**
		Creates an honest Haxe fallback position for a private external source identity.

		Why / What / How
		- Haxe 4.3.7 cannot attach a newly created private filename to the line table of a source that was
		  loaded through a different absolute filename. Passing the private byte offsets would therefore
		  print a false line-one location, while passing the original position would expose the machine path.
		- Mark the outer Haxe position as unknown in that narrow case. The diagnostic text still starts with
		  the exact private file/line/column returned by `inlineDiagnosticPrefix`.
		- The safe filename remains on the position for structured consumers, but `-1` tells Haxe's classic
		  formatter not to invent line and column data.
	**/
	public static function privateUnknownPosition(stableFile:String):Position {
		if (!isSafeRelative(stableFile))
			throw "Private diagnostic fallback requires a safe relative source identity";
		return Context.makePosition({file: stableFile, min: -1, max: -1});
	}

	static function sourceIndex(rawFile:String):Null<RustSourcePositionIndex> {
		var resolved = resolveSource(rawFile);
		if (resolved == null)
			return null;
		var existing = sources.get(resolved);
		if (existing != null)
			return existing;
		var index = new RustSourcePositionIndex(File.getContent(resolved));
		sources.set(resolved, index);
		return index;
	}

	static function resolveSource(rawFile:String):Null<String> {
		if (rawFile == null || rawFile.length == 0)
			return null;
		var remembered = realSourceByStablePath.get(rawFile.split("\\").join("/"));
		if (remembered != null && FileSystem.exists(remembered) && !FileSystem.isDirectory(remembered))
			return remembered;
		var candidate = Path.isAbsolute(rawFile) ? rawFile : Path.join([Sys.getCwd(), rawFile]);
		candidate = Path.normalize(candidate);
		if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate))
			return FileSystem.fullPath(candidate);
		#if macro
		try {
			var resolved = Context.resolvePath(rawFile);
			if (resolved != null && resolved.length > 0 && FileSystem.exists(resolved) && !FileSystem.isDirectory(resolved))
				return FileSystem.fullPath(resolved);
		} catch (_:haxe.Exception) {}
		#end
		return null;
	}

	static function registerStableSource(stable:String, resolved:String):Void {
		var existing = realSourceByStablePath.get(stable);
		if (existing != null && existing != resolved)
			throw 'Private source identity `$stable` resolves to more than one source file';
		realSourceByStablePath.set(stable, resolved);
	}

	static inline function positionKey(stableFile:String, startByte:Int, endByte:Int):String {
		return stableFile + "\u0000" + startByte + "\u0000" + endByte;
	}

	static function canonicalDirectory(raw:String):Null<String> {
		if (raw == null || raw.length == 0)
			return null;
		var normalized = Path.normalize(raw);
		if (!FileSystem.exists(normalized) || !FileSystem.isDirectory(normalized))
			return null;
		return FileSystem.fullPath(normalized).split("\\").join("/");
	}

	static inline function ensureTrailingSlash(path:String):String {
		return StringTools.endsWith(path, "/") ? path : path + "/";
	}

	static function isSafeRelative(path:String):Bool {
		if (path == null || path.length == 0 || Path.isAbsolute(path) || ~/^[A-Za-z]:/.match(path) || ~/[\x00-\x1f\x7f]/.match(path))
			return false;
		for (segment in path.split("/"))
			if (segment.length == 0 || segment == "." || segment == "..")
				return false;
		return true;
	}
}

private typedef RustRememberedDisplayLocation = {
	var startLine:Int;
	var startColumn:Int;
	var endLine:Int;
	var endColumn:Int;
}

private class RustSourcePositionIndex {
	final content:String;
	final byteOffsets:Map<Int, Int> = [];

	public function new(content:String) {
		if (content == null)
			throw "Source-position index requires text";
		this.content = content;
		byteOffsets.set(0, 0);
		byteOffsets.set(content.length, Bytes.ofString(content).length);
	}

	public function byteRange(start:Int, end:Int):RustUtf8ByteRange {
		if (start < 0 || end < start || end > content.length)
			throw "Haxe source position exceeds the resolved source text";
		return {startByte: byteOffset(start), endByte: byteOffset(end)};
	}

	public function characterOffset(byteOffset:Int):Null<Int> {
		var totalBytes = this.byteOffset(content.length);
		if (byteOffset < 0 || byteOffset > totalBytes)
			return null;
		var low = 0;
		var high = content.length;
		while (low <= high) {
			var middle = (low + high) >> 1;
			var middleByte = this.byteOffset(middle);
			if (middleByte == byteOffset)
				return middle;
			if (middleByte < byteOffset)
				low = middle + 1;
			else
				high = middle - 1;
		}
		return null;
	}

	/** Returns one-based source line and character columns for a validated UTF-8 byte range. */
	public function displayLocation(startByte:Int, endByte:Int):RustRememberedDisplayLocation {
		var start = characterOffset(startByte);
		var end = characterOffset(endByte);
		if (start == null || end == null)
			throw "Display location must begin and end on UTF-8 character boundaries";
		var startPoint = displayPoint(start);
		var endPoint = displayPoint(end);
		return {
			startLine: startPoint.line,
			startColumn: startPoint.column,
			endLine: endPoint.line,
			endColumn: endPoint.column
		};
	}

	function displayPoint(characterOffset:Int):{line:Int, column:Int} {
		var prefix = content.substr(0, characterOffset);
		var lines = ~/(?:\r\n|\r|\n)/g.split(prefix);
		return {line: lines.length, column: lines[lines.length - 1].length + 1};
	}

	function byteOffset(characterOffset:Int):Int {
		var existing = byteOffsets.get(characterOffset);
		if (existing != null)
			return existing;
		var measured = Bytes.ofString(content.substr(0, characterOffset)).length;
		byteOffsets.set(characterOffset, measured);
		return measured;
	}
}
