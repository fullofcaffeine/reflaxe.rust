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

	/** Clears cached source text at the start of a compilation-server request. */
	public static function reset():Void {
		sources = [];
	}

	/** Converts a validated Haxe source-string range into its exact UTF-8 byte range. */
	public static function utf8ByteRange(rawFile:String, start:Int, end:Int):Null<RustUtf8ByteRange> {
		var index = sourceIndex(rawFile);
		if (index == null)
			return null;
		return index.byteRange(start, end);
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

	function byteOffset(characterOffset:Int):Int {
		var existing = byteOffsets.get(characterOffset);
		if (existing != null)
			return existing;
		var measured = Bytes.ofString(content.substr(0, characterOffset)).length;
		byteOffsets.set(characterOffset, measured);
		return measured;
	}
}
