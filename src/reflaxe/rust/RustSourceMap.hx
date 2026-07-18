package reflaxe.rust;

import haxe.DynamicAccess;
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import reflaxe.rust.ast.RustAST.RustGeneratedOriginReason;
import reflaxe.rust.ast.RustAST.RustOrigin;
import sys.FileSystem;
import sys.io.File;

/** The structural Rust node whose printed bytes own one mapping range. */
enum RustSourceMapNodeKind {
	Item;
	Statement;
	Expression;
}

/** A one-based line/UTF-8-byte-column paired with its zero-based byte offset. */
private typedef RustSourceMapPoint = {
	var byteOffset:Int;
	var line:Int;
	var column:Int;
}

/**
	An immutable half-open range in the exact generated Rust UTF-8 bytes.

	Why / What / How
	- Source-map documents must remain valid after construction; a caller must not be able to mutate a
	  previously validated typedef payload behind a `final` mapping field.
	- `at` validates non-empty byte and forward line/column ranges and stores only immutable scalars.
**/
class RustGeneratedSourceSpan {
	public final startByte:Int;
	public final endByte:Int;
	public final startLine:Int;
	public final startColumn:Int;
	public final endLine:Int;
	public final endColumn:Int;

	private function new(startByte:Int, endByte:Int, startLine:Int, startColumn:Int, endLine:Int, endColumn:Int) {
		if (startByte < 0 || endByte <= startByte || startLine <= 0 || startColumn <= 0 || endLine <= 0 || endColumn <= 0
			|| endLine < startLine || (endLine == startLine && endColumn <= startColumn))
			throw "Rust generated source span must be non-empty and forward";
		this.startByte = startByte;
		this.endByte = endByte;
		this.startLine = startLine;
		this.startColumn = startColumn;
		this.endLine = endLine;
		this.endColumn = endColumn;
	}

	public static function at(startByte:Int, endByte:Int, startLine:Int, startColumn:Int, endLine:Int,
			endColumn:Int):RustGeneratedSourceSpan {
		return new RustGeneratedSourceSpan(startByte, endByte, startLine, startColumn, endLine, endColumn);
	}
}

/**
	An immutable exact Haxe source position with a path-private file identity.

	Why / What / How
	- Haxe positions may be zero-width, but their bytes and line/column points must never move after a
	  source-map document has validated them.
	- `at` rejects unsafe filenames and backward positions before storing immutable scalar fields.
**/
class RustHaxeSourceSpan {
	public final file:String;
	public final startByte:Int;
	public final endByte:Int;
	public final startLine:Int;
	public final startColumn:Int;
	public final endLine:Int;
	public final endColumn:Int;

	private function new(file:String, startByte:Int, endByte:Int, startLine:Int, startColumn:Int, endLine:Int, endColumn:Int) {
		this.file = RustSourceMap.requireRelativePath(file, "Haxe source file");
		if (startByte < 0 || endByte < startByte || startLine <= 0 || startColumn <= 0 || endLine <= 0 || endColumn <= 0
			|| endLine < startLine || (endLine == startLine && endColumn < startColumn))
			throw "Rust Haxe source span must be forward";
		this.startByte = startByte;
		this.endByte = endByte;
		this.startLine = startLine;
		this.startColumn = startColumn;
		this.endLine = endLine;
		this.endColumn = endColumn;
	}

	public static function at(file:String, startByte:Int, endByte:Int, startLine:Int, startColumn:Int, endLine:Int,
			endColumn:Int):RustHaxeSourceSpan {
		return new RustHaxeSourceSpan(file, startByte, endByte, startLine, startColumn, endLine, endColumn);
	}
}

/** The typed origin returned to a rustc-diagnostic consumer. */
enum RustMappedOrigin {
	MappedHaxeSource(source:RustHaxeSourceSpan);
	MappedCompilerGenerated(reason:RustGeneratedOriginReason);
}

/**
	One validated origin candidate for a half-open generated UTF-8 byte range.

	Why / What / How
	- Nested AST nodes can legitimately cover the same Rust bytes, so a mapping retains both its node
	  kind and structural `originDepth` for deterministic selection.
	- The constructor rejects empty/backward generated spans, unsafe Haxe paths, unknown generated
	  reasons, and incoherent line/column ranges.
	- Consumers normally obtain instances through `RustSourceMap.decode` or `lookup`, not by parsing
	  JSON fields themselves.
**/
@:allow(reflaxe.rust.RustSourceMap)
class RustSourceMapping {
	public final nodeKind:RustSourceMapNodeKind;
	/** Structural wrapper depth; larger values are more specific when generated spans tie. */
	public final originDepth:Int;
	public final generated:RustGeneratedSourceSpan;
	public final origin:RustMappedOrigin;

	private function new(nodeKind:RustSourceMapNodeKind, originDepth:Int, generated:RustGeneratedSourceSpan, origin:RustMappedOrigin) {
		if (nodeKind == null || generated == null || origin == null)
			throw "Rust source mapping fields cannot be null";
		if (originDepth < 0)
			throw "Rust source mapping origin depth cannot be negative";
		if (generated.startByte < 0 || generated.endByte <= generated.startByte)
			throw "Rust source mapping requires a non-empty generated byte range";
		if (generated.startLine <= 0 || generated.startColumn <= 0 || generated.endLine <= 0 || generated.endColumn <= 0
			|| generated.endLine < generated.startLine
			|| (generated.endLine == generated.startLine && generated.endColumn <= generated.startColumn))
			throw "Rust source mapping requires a forward generated line/column range";
		switch (origin) {
			case MappedHaxeSource(source):
				if (source == null)
					throw "Mapped Haxe source span cannot be null";
				RustSourceMap.requireRelativePath(source.file, "Haxe source file");
				if (source.startByte < 0 || source.endByte < source.startByte || source.startLine <= 0 || source.startColumn <= 0
					|| source.endLine <= 0 || source.endColumn <= 0 || source.endLine < source.startLine
					|| (source.endLine == source.startLine && source.endColumn < source.startColumn))
					throw "Mapped Haxe source requires a forward byte and line/column range";
			case MappedCompilerGenerated(reason):
				RustGeneratedOriginReason.fromId(reason.id());
		}
		this.nodeKind = nodeKind;
		this.originDepth = originDepth;
		this.generated = generated;
		this.origin = origin;
	}
}

/**
	All mappings tied to one exact generated filename and complete content hash.

	Why / What / How
	- A filename and byte span are not enough after formatting or regeneration.
	- The file owns a defensive mapping copy plus the emitted UTF-8 length, line count, and SHA-256.
	- `RustSourceMap.lookup` accepts the entry only when the caller supplies matching current bytes.
**/
@:allow(reflaxe.rust.RustSourceMap)
class RustSourceMapFile {
	public final generatedFile:String;
	public final byteLength:Int;
	public final lineCount:Int;
	public final contentHash:String;
	final values:Array<RustSourceMapping>;
	public var mappingCount(get, never):Int;

	private function new(generatedFile:String, byteLength:Int, lineCount:Int, contentHash:String, mappings:Array<RustSourceMapping>) {
		this.generatedFile = RustSourceMap.requireRelativePath(generatedFile, "generated Rust file");
		if (byteLength < 0 || lineCount < 0 || (byteLength == 0 && lineCount != 0) || (byteLength > 0 && lineCount == 0))
			throw "Rust source-map byte length and line count are inconsistent";
		if (contentHash == null || !~/^[a-f0-9]{64}$/.match(contentHash))
			throw "Rust source-map content hash must be lowercase SHA-256";
		if (mappings == null)
			throw "Rust source-map mappings cannot be null";
		this.byteLength = byteLength;
		this.lineCount = lineCount;
		this.contentHash = contentHash;
		this.values = mappings.copy();
		for (mapping in values) {
			if (mapping == null || mapping.generated.endByte > byteLength || mapping.generated.endLine > lineCount)
				throw "Rust source mapping exceeds its generated file";
		}
	}

	function get_mappingCount():Int {
		return values.length;
	}

	public function mappingAt(index:Int):RustSourceMapping {
		if (index < 0 || index >= values.length)
			throw 'Rust source mapping index out of bounds: $index';
		return values[index];
	}

	public function iterator():Iterator<RustSourceMapping> {
		return values.iterator();
	}
}

/**
	A validated, deterministic `rust-source-map.json` document.

	Why / What / How
	- Schema/generator checks prevent a consumer from interpreting a different artifact as this map.
	- Files are defensively copied and must be unique in complete-filename order.
	- Use indexed access or iteration after `RustSourceMap.decode`; the underlying array is not exposed.
**/
@:allow(reflaxe.rust.RustSourceMap)
class RustSourceMapDocument {
	public final schemaVersion:Int;
	public final generator:String;
	final values:Array<RustSourceMapFile>;
	public var fileCount(get, never):Int;

	private function new(schemaVersion:Int, generator:String, files:Array<RustSourceMapFile>) {
		if (schemaVersion != RustSourceMap.SCHEMA_VERSION)
			throw 'Unsupported Rust source-map schema version: $schemaVersion';
		if (generator != RustSourceMap.GENERATOR)
			throw 'Unsupported Rust source-map generator: $generator';
		if (files == null)
			throw "Rust source-map files cannot be null";
		this.schemaVersion = schemaVersion;
		this.generator = generator;
		this.values = files.copy();
		var previous:Null<String> = null;
		for (file in values) {
			if (file == null)
				throw "Rust source-map file cannot be null";
			if (previous != null && previous >= file.generatedFile)
				throw "Rust source-map files must be unique and sorted";
			previous = file.generatedFile;
		}
	}

	function get_fileCount():Int {
		return values.length;
	}

	public function fileAt(index:Int):RustSourceMapFile {
		if (index < 0 || index >= values.length)
			throw 'Rust source-map file index out of bounds: $index';
		return values[index];
	}

	public function iterator():Iterator<RustSourceMapFile> {
		return values.iterator();
	}
}

/**
	The exact generated span reported by rustc JSON diagnostics.

	Why / What / How
	- Consumers must supply rustc's full generated filename plus its half-open UTF-8 byte range.
	- Construction rejects absolute/traversing filenames and inverted ranges.
	- Lookup performs exact filename and content-hash matching; it never falls back to a basename.
**/
class RustcGeneratedSpan {
	public final generatedFile:String;
	public final startByte:Int;
	public final endByte:Int;

	private function new(generatedFile:String, startByte:Int, endByte:Int) {
		this.generatedFile = RustSourceMap.requireRelativePath(generatedFile, "rustc generated file");
		if (startByte < 0 || endByte < startByte)
			throw "rustc generated byte span is invalid";
		this.startByte = startByte;
		this.endByte = endByte;
	}

	public static function at(generatedFile:String, startByte:Int, endByte:Int):RustcGeneratedSpan {
		return new RustcGeneratedSpan(generatedFile, startByte, endByte);
	}
}

/**
	Printer result metadata before Haxe positions become path-private source spans.

	Why / What / How
	- The printer knows exact generated byte offsets while Haxe macro `Position` remains the honest
	  source authority.
	- Encoding later resolves that position against the compilation root and known classpaths.
	- Same-file chunk aggregation shifts byte offsets while retaining structural origin depth.
**/
class RustPrintedSourceMapping {
	public final nodeKind:RustSourceMapNodeKind;
	public final origin:RustOrigin;
	public final originDepth:Int;
	public final startByte:Int;
	public final endByte:Int;

	private function new(nodeKind:RustSourceMapNodeKind, origin:RustOrigin, originDepth:Int, startByte:Int, endByte:Int) {
		if (nodeKind == null || origin == null)
			throw "Printed Rust source mapping metadata cannot be null";
		if (originDepth < 0)
			throw "Printed Rust source mapping origin depth cannot be negative";
		if (startByte < 0 || endByte <= startByte)
			throw "Printed Rust source mapping requires a non-empty byte range";
		this.nodeKind = nodeKind;
		this.origin = origin;
		this.originDepth = originDepth;
		this.startByte = startByte;
		this.endByte = endByte;
	}

	public static function at(nodeKind:RustSourceMapNodeKind, origin:RustOrigin, originDepth:Int, startByte:Int,
			endByte:Int):RustPrintedSourceMapping {
		return new RustPrintedSourceMapping(nodeKind, origin, originDepth, startByte, endByte);
	}

	public function shifted(byteDelta:Int):RustPrintedSourceMapping {
		if (byteDelta < 0)
			throw "Printed Rust source mapping shift cannot be negative";
		return at(nodeKind, origin, originDepth, startByte + byteDelta, endByte + byteDelta);
	}
}

/**
	One mapping-aware printer result paired with Reflaxe's exact generated filename.

	Why / What / How
	- Reflaxe may aggregate several Haxe declarations into one Rust file, so each iterator chunk keeps
	  its code, precomputed UTF-8 byte length, and local mapping offsets together.
	- Construction computes that length once, defensively copies mappings, and checks that none exceeds
	  the chunk bytes.
	- `RustSourceMap.encode` joins chunks with the same separator as Reflaxe's output manager.
**/
class RustPrintedSourceFile {
	public final generatedFile:String;
	public final code:String;
	public final byteLength:Int;
	final values:Array<RustPrintedSourceMapping>;
	public var mappingCount(get, never):Int;

	private function new(generatedFile:String, code:String, mappings:Array<RustPrintedSourceMapping>) {
		this.generatedFile = RustSourceMap.requireRelativePath(generatedFile, "printed generated Rust file");
		if (code == null || mappings == null)
			throw "Printed Rust source file fields cannot be null";
		this.code = code;
		this.values = mappings.copy();
		this.byteLength = Bytes.ofString(code).length;
		for (mapping in values) {
			if (mapping == null || mapping.endByte > byteLength)
				throw "Printed Rust source mapping exceeds its file";
		}
	}

	public static function of(generatedFile:String, code:String, mappings:Array<RustPrintedSourceMapping>):RustPrintedSourceFile {
		return new RustPrintedSourceFile(generatedFile, code, mappings);
	}

	function get_mappingCount():Int {
		return values.length;
	}

	public function mappingAt(index:Int):RustPrintedSourceMapping {
		if (index < 0 || index >= values.length)
			throw 'Printed Rust source mapping index out of bounds: $index';
		return values[index];
	}

	public function iterator():Iterator<RustPrintedSourceMapping> {
		return values.iterator();
	}
}

private typedef AggregatedPrintedFile = {
	var generatedFile:String;
	var chunks:Array<String>;
	var byteLength:Int;
	var mappings:Array<RustPrintedSourceMapping>;
}

private typedef ResolvedSourceIdentity = {
	var stableFile:String;
	var absoluteFile:String;
}

private typedef RustSourceMapEncodeState = {
	var sourceRoot:String;
	var resolvedSources:Map<String, ResolvedSourceIdentity>;
	var indexedSources:Map<String, RustSourceByteIndex>;
	var sourceSpans:Map<String, RustHaxeSourceSpan>;
}

private typedef RustSourceMapJsonOrigin = {
	var kind:String;
	@:optional var source:RustHaxeSourceSpan;
	@:optional var reason:String;
}

private typedef RustSourceMapJsonMapping = {
	var nodeKind:String;
	var originDepth:Int;
	var generated:RustGeneratedSourceSpan;
	var origin:RustSourceMapJsonOrigin;
}

private typedef RustSourceMapJsonFile = {
	var generatedFile:String;
	var byteLength:Int;
	var lineCount:Int;
	var contentHash:String;
	var mappings:Array<RustSourceMapJsonMapping>;
}

/**
	The single unavoidable untyped value at the JSON parser boundary.

	Why / What / How
	- `haxe.Json.parse` returns an untyped value.
	- The decoder passes this alias only through the validating helpers at the bottom of this module.
	- No lookup, path, origin, or span logic accepts this type after field validation.
**/
private typedef RustSourceMapJsonValue = Dynamic;

/** Precomputed newline offsets keep mapping resolution O(log lines) instead of rescanning files. */
private class RustSourceByteIndex {
	public final bytes:Bytes;
	public final lineCount:Int;
	final lineStarts:Array<Int>;

	public function new(bytes:Bytes) {
		if (bytes == null)
			throw "Rust source byte index cannot wrap null bytes";
		this.bytes = bytes;
		this.lineStarts = [0];
		for (index in 0...bytes.length) {
			if (bytes.get(index) == 10)
				lineStarts.push(index + 1);
		}
		this.lineCount = bytes.length == 0 ? 0 : lineStarts.length;
	}

	public function pointAt(offset:Int):RustSourceMapPoint {
		if (offset < 0 || offset > bytes.length)
			throw 'Source-map byte offset is out of bounds: $offset';
		var low = 0;
		var high = lineStarts.length;
		while (low + 1 < high) {
			var middle = low + Std.int((high - low) / 2);
			if (lineStarts[middle] <= offset)
				low = middle;
			else
				high = middle;
		}
		return {byteOffset: offset, line: low + 1, column: offset - lineStarts[low] + 1};
	}
}

/**
	Codec and exact lookup authority for deterministic `rust-source-map.json` artifacts.

	Why
	- rustc reports generated Rust filenames and byte spans. Mapping those diagnostics by basename or
	  stale line numbers can confidently blame the wrong Haxe expression.
	- Haxe `Position.file` may be absolute, so serializing it directly leaks machine-local paths and
	  makes identical builds differ across checkouts.

	What
	- Aggregates printer chunks exactly as Reflaxe's file-per-module writer does (`\n\n` between
	  chunks), records a SHA-256 of the complete generated file, and emits schema-versioned JSON.
	- Converts Haxe positions to project-relative or classpath-relative identities with exact byte and
	  line/column ranges.
	- Decodes JSON at one tightly scoped dynamic boundary and immediately rebuilds validated typed
	  values.

	How
	- `encode` receives mapping-aware printer results and the compilation working directory.
	- `decode` rejects unknown reasons, absolute/traversing paths, invalid hashes, unsorted files, and
	  malformed spans.
	- `lookup` requires the exact current generated content. A rustfmt edit or any other byte change
	  fails closed by hash mismatch instead of guessing.
**/
class RustSourceMap {
	public static inline var SCHEMA_VERSION:Int = 1;
	public static inline var GENERATOR:String = "reflaxe.rust";
	static inline var OUTPUT_CHUNK_SEPARATOR:String = "\n\n";
	static final OUTPUT_CHUNK_SEPARATOR_BYTE_LENGTH:Int = Bytes.ofString(OUTPUT_CHUNK_SEPARATOR).length;

	/**
		Builds canonical source-map JSON from exact printer chunks.

		Why / What / How
		- Resolves source positions once against an absolute compilation root, caches source byte indexes,
		  sorts every filename/mapping by a total order, and removes exact duplicate entries.
		- Same-file aggregation stores chunks with a running byte length, shifts each mapping once, and
		  joins text once so large generated modules do not repeatedly copy or re-encode every prefix.
		- Hashes the same UTF-8 byte buffers used for offsets and appends one newline to the JSON artifact.
	**/
	public static function encode(printedFiles:Array<RustPrintedSourceFile>, sourceRoot:String):String {
		if (printedFiles == null)
			throw "Printed Rust source files cannot be null";
		var root = canonicalPath(sourceRoot);
		if (!Path.isAbsolute(root))
			throw "Rust source-map root must be absolute";
		var state:RustSourceMapEncodeState = {
			sourceRoot: root,
			resolvedSources: [],
			indexedSources: [],
			sourceSpans: []
		};

		var byFile:Map<String, AggregatedPrintedFile> = [];
		for (printed in printedFiles) {
			if (printed == null)
				throw "Printed Rust source file cannot be null";
			var existing = byFile.get(printed.generatedFile);
			if (existing == null) {
				var mappings = [for (mapping in printed) mapping];
				byFile.set(printed.generatedFile, {
					generatedFile: printed.generatedFile,
					chunks: [printed.code],
					byteLength: printed.byteLength,
					mappings: mappings
				});
			} else {
				var byteDelta = existing.byteLength + OUTPUT_CHUNK_SEPARATOR_BYTE_LENGTH;
				existing.chunks.push(printed.code);
				existing.byteLength = byteDelta + printed.byteLength;
				for (mapping in printed)
					existing.mappings.push(mapping.shifted(byteDelta));
			}
		}

		var names = [for (name in byFile.keys()) name];
		names.sort(compareStrings);
		var typedFiles:Array<RustSourceMapFile> = [];
		var jsonFiles:Array<RustSourceMapJsonFile> = [];
		for (name in names) {
			var aggregated = byFile.get(name);
			if (aggregated == null)
				continue;
			var codeBytes = Bytes.ofString(aggregated.chunks.join(OUTPUT_CHUNK_SEPARATOR));
			if (codeBytes.length != aggregated.byteLength)
				throw "Aggregated Rust source byte length drifted from its running length";
			var generatedIndex = new RustSourceByteIndex(codeBytes);
			var mappings = [for (mapping in aggregated.mappings) resolveMapping(mapping, generatedIndex, state)];
			mappings.sort(compareMappings);
			mappings = deduplicateMappings(mappings);
			var contentHash = Sha256.make(codeBytes).toHex();
			var typedFile = new RustSourceMapFile(name, codeBytes.length, generatedIndex.lineCount, contentHash, mappings);
			typedFiles.push(typedFile);
			jsonFiles.push(encodeFile(typedFile));
		}
		new RustSourceMapDocument(SCHEMA_VERSION, GENERATOR, typedFiles);
		// This artifact can contain thousands of fine-grained entries even for a small crate. Keep the
		// machine contract compact; callers can pretty-print it for inspection without changing meaning.
		return Json.stringify({schemaVersion: SCHEMA_VERSION, generator: GENERATOR, files: jsonFiles}) + "\n";
	}

	/**
		Decodes untrusted source-map JSON into typed, validated values.

		Why / What / How
		- JSON is the unavoidable untyped boundary; every field immediately passes through a typed
		  validator before document construction.
		- Unknown origin reasons, unsafe paths, duplicates, and non-deterministic ordering fail closed.
	**/
	public static function decode(encoded:String):RustSourceMapDocument {
		if (encoded == null)
			throw "Rust source-map JSON cannot be null";
		var raw:RustSourceMapJsonValue;
		try {
			raw = Json.parse(encoded);
		} catch (error:haxe.Exception) {
			throw 'Invalid Rust source-map JSON: ${error.message}';
		}
		var root = object(raw, "source-map root");
		var schemaVersion = integer(root.get("schemaVersion"), "schemaVersion");
		var generator = string(root.get("generator"), "generator");
		var fileValues = array(root.get("files"), "files");
		var files:Array<RustSourceMapFile> = [];
		for (index in 0...fileValues.length)
			files.push(decodeFile(object(fileValues[index], 'files[$index]'), 'files[$index]'));
		return new RustSourceMapDocument(schemaVersion, generator, files);
	}

	/**
		Finds the most precise honest origin for one rustc generated span.

		Why / What / How
		- Requires exact filename, byte length, SHA-256, and containing half-open range; no basename or
		  line-number fallback exists.
		- Ties prefer the smaller generated range, expression over statement over item, then the deeper
		  origin wrapper and a deterministic final origin order.
	**/
	public static function lookup(document:RustSourceMapDocument, span:RustcGeneratedSpan, generatedContent:String):Null<RustSourceMapping> {
		if (document == null || span == null || generatedContent == null)
			return null;
		var selected:Null<RustSourceMapFile> = null;
		for (file in document) {
			if (file.generatedFile == span.generatedFile) {
				selected = file;
				break;
			}
		}
		if (selected == null)
			return null;
		var bytes = Bytes.ofString(generatedContent);
		if (bytes.length != selected.byteLength || Sha256.make(bytes).toHex() != selected.contentHash)
			return null;
		var generatedIndex = new RustSourceByteIndex(bytes);
		if (!coordinatesMatchContent(selected, generatedIndex))
			return null;
		if (span.endByte > selected.byteLength)
			return null;

		var best:Null<RustSourceMapping> = null;
		for (mapping in selected) {
			var contains = if (span.startByte == span.endByte) {
				mapping.generated.startByte <= span.startByte && mapping.generated.endByte > span.startByte;
			} else {
				mapping.generated.startByte <= span.startByte && mapping.generated.endByte >= span.endByte;
			};
			if (!contains)
				continue;
			if (best == null || isMorePrecise(mapping, best))
				best = mapping;
		}
		return best;
	}

	/**
		Checks decoded coordinate metadata against the exact content already authenticated by lookup.

		Why
		- A correct filename, byte length, and SHA-256 prove which bytes were mapped, but do not prove that
		  untrusted JSON reported honest line/column coordinates for those bytes.
		- Consumers may display those coordinates directly, so accepting a contradictory map would make the
		  versioned artifact internally dishonest despite exact freshness checks.

		What / How
		- Reuses one byte index for the selected file, verifies its exact line count, and recomputes both
		  endpoints of every mapping.
		- Any disagreement rejects the complete file before span selection; lookup never returns a partially
		  trusted mapping.
	**/
	static function coordinatesMatchContent(file:RustSourceMapFile, index:RustSourceByteIndex):Bool {
		if (file.lineCount != index.lineCount)
			return false;
		for (mapping in file) {
			var start = index.pointAt(mapping.generated.startByte);
			var end = index.pointAt(mapping.generated.endByte);
			if (mapping.generated.startLine != start.line
				|| mapping.generated.startColumn != start.column
				|| mapping.generated.endLine != end.line
				|| mapping.generated.endColumn != end.column)
				return false;
		}
		return true;
	}

	/**
		Validates and canonicalizes one artifact path without permitting traversal.

		Why / What / How
		- Checks raw slash-normalized components before `Path.normalize`, because normalization would
		  otherwise hide `safe/../file`.
		- Rejects absolute, drive-qualified, empty, dot, and dot-dot components.
	**/
	public static function requireRelativePath(value:String, label:String):String {
		return RustSourcePath.requireRelativePath(value, label);
	}

	static function resolveMapping(mapping:RustPrintedSourceMapping, generatedIndex:RustSourceByteIndex,
			state:RustSourceMapEncodeState):RustSourceMapping {
		var start = generatedIndex.pointAt(mapping.startByte);
		var end = generatedIndex.pointAt(mapping.endByte);
		var generated = RustGeneratedSourceSpan.at(start.byteOffset, end.byteOffset, start.line, start.column, end.line, end.column);
		var origin:RustMappedOrigin = switch (mapping.origin) {
			case OriginHaxeSource(pos): MappedHaxeSource(resolveHaxeSource(pos, state));
			case OriginCompilerGenerated(reason): MappedCompilerGenerated(RustGeneratedOriginReason.fromId(reason.id()));
		};
		return new RustSourceMapping(mapping.nodeKind, mapping.originDepth, generated, origin);
	}

	static function resolveHaxeSource(pos:Position, state:RustSourceMapEncodeState):RustHaxeSourceSpan {
		if (pos == null)
			throw "Mapped Haxe origin is missing its position";
		var info = Context.getPosInfos(pos);
		if (info == null || info.file == null || info.file.length == 0)
			throw "Mapped Haxe origin is missing its source file";
		if (info.min < 0 || info.max < info.min)
			throw "Mapped Haxe origin requires a valid source byte range";
		var spanKey = info.file.length + ":" + info.file + ":" + info.min + ":" + info.max;
		var cachedSpan = state.sourceSpans.get(spanKey);
		if (cachedSpan != null)
			return cachedSpan;
		var resolved = state.resolvedSources.get(info.file);
		if (resolved == null) {
			resolved = resolveSourceFile(info.file, state.sourceRoot);
			state.resolvedSources.set(info.file, resolved);
		}
		var sourceIndex = state.indexedSources.get(resolved.absoluteFile);
		if (sourceIndex == null) {
			sourceIndex = new RustSourceByteIndex(File.getBytes(resolved.absoluteFile));
			state.indexedSources.set(resolved.absoluteFile, sourceIndex);
		}
		var byteRange = RustSourcePosition.utf8ByteRange(resolved.absoluteFile, info.min, info.max);
		if (byteRange == null || byteRange.endByte > sourceIndex.bytes.length)
			throw 'Mapped Haxe origin exceeds ${resolved.stableFile}';
		var start = sourceIndex.pointAt(byteRange.startByte);
		var end = sourceIndex.pointAt(byteRange.endByte);
		var span = RustHaxeSourceSpan.at(resolved.stableFile, byteRange.startByte, byteRange.endByte, start.line, start.column, end.line, end.column);
		state.sourceSpans.set(spanKey, span);
		return span;
	}

	static function resolveSourceFile(rawFile:String, sourceRoot:String):{stableFile:String, absoluteFile:String} {
		var normalizedRaw = normalizePath(rawFile);
		var absolute:Null<String> = null;
		if (Path.isAbsolute(normalizedRaw)) {
			absolute = canonicalPath(normalizedRaw);
		} else {
			var projectCandidate = canonicalPath(Path.join([sourceRoot, normalizedRaw]));
			if (FileSystem.exists(projectCandidate) && !FileSystem.isDirectory(projectCandidate))
				absolute = projectCandidate;
			#if macro
			if (absolute == null) {
				try {
					var resolved = Context.resolvePath(normalizedRaw);
					if (resolved != null && resolved.length > 0) {
						var candidate = Path.isAbsolute(resolved) ? resolved : Path.join([sourceRoot, resolved]);
						candidate = canonicalPath(candidate);
						if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate))
							absolute = candidate;
					}
				} catch (_:haxe.Exception) {}
			}
			#end
		}
		if (absolute == null || !FileSystem.exists(absolute) || FileSystem.isDirectory(absolute))
			throw 'Cannot resolve mapped Haxe source file without guessing: $rawFile';

		var projectRelative = relativeUnder(absolute, sourceRoot);
		if (projectRelative != null)
			return {stableFile: requireRelativePath(projectRelative, "Haxe source file"), absoluteFile: absolute};

		var candidates:Array<String> = [];
		#if macro
		for (classPath in Context.getClassPath()) {
			if (classPath == null || classPath.length == 0)
				continue;
			var root = canonicalPath(Path.isAbsolute(classPath) ? classPath : Path.join([sourceRoot, classPath]));
			var relative = relativeUnder(absolute, root);
			if (relative != null)
				candidates.push("classpath/" + requireRelativePath(relative, "classpath Haxe source file"));
		}
		#end
		candidates.sort((left, right) -> left.length != right.length ? left.length - right.length : compareStrings(left, right));
		if (candidates.length == 0)
			throw 'Mapped Haxe source is outside the project and known classpaths: $rawFile';
		return {stableFile: candidates[0], absoluteFile: absolute};
	}

	static function encodeFile(file:RustSourceMapFile):RustSourceMapJsonFile {
		var mappings:Array<RustSourceMapJsonMapping> = [];
		for (mapping in file)
			mappings.push(encodeMapping(mapping));
		return {
			generatedFile: file.generatedFile,
			byteLength: file.byteLength,
			lineCount: file.lineCount,
			contentHash: file.contentHash,
			mappings: mappings
		};
	}

	static function encodeMapping(mapping:RustSourceMapping):RustSourceMapJsonMapping {
		var origin:RustSourceMapJsonOrigin = switch (mapping.origin) {
			case MappedHaxeSource(source): {
				kind: "haxe-source",
				source: source
			};
			case MappedCompilerGenerated(reason): {
				kind: "compiler-generated",
				reason: reason.id()
			};
		};
		return {
			nodeKind: nodeKindId(mapping.nodeKind),
			originDepth: mapping.originDepth,
			generated: mapping.generated,
			origin: origin
		};
	}

	static function decodeFile(raw:DynamicAccess<RustSourceMapJsonValue>, label:String):RustSourceMapFile {
		var generatedFile = string(raw.get("generatedFile"), label + ".generatedFile");
		var byteLength = integer(raw.get("byteLength"), label + ".byteLength");
		var lineCount = integer(raw.get("lineCount"), label + ".lineCount");
		var contentHash = string(raw.get("contentHash"), label + ".contentHash");
		var mappingValues = array(raw.get("mappings"), label + ".mappings");
		var mappings:Array<RustSourceMapping> = [];
		for (index in 0...mappingValues.length)
			mappings.push(decodeMapping(object(mappingValues[index], '$label.mappings[$index]'), '$label.mappings[$index]'));
		for (index in 1...mappings.length) {
			var order = compareMappings(mappings[index - 1], mappings[index]);
			if (order > 0)
				throw '$label.mappings must use deterministic total ordering';
			if (order == 0)
				throw '$label.mappings must not contain duplicate entries';
		}
		return new RustSourceMapFile(generatedFile, byteLength, lineCount, contentHash, mappings);
	}

	static function decodeMapping(raw:DynamicAccess<RustSourceMapJsonValue>, label:String):RustSourceMapping {
		var nodeKind = nodeKindFromId(string(raw.get("nodeKind"), label + ".nodeKind"));
		var originDepth = integer(raw.get("originDepth"), label + ".originDepth");
		var generatedRaw = object(raw.get("generated"), label + ".generated");
		var generated = RustGeneratedSourceSpan.at(integer(generatedRaw.get("startByte"), label + ".generated.startByte"),
			integer(generatedRaw.get("endByte"), label + ".generated.endByte"),
			positiveInteger(generatedRaw.get("startLine"), label + ".generated.startLine"),
			positiveInteger(generatedRaw.get("startColumn"), label + ".generated.startColumn"),
			positiveInteger(generatedRaw.get("endLine"), label + ".generated.endLine"),
			positiveInteger(generatedRaw.get("endColumn"), label + ".generated.endColumn"));
		var originRaw = object(raw.get("origin"), label + ".origin");
		var originKind = string(originRaw.get("kind"), label + ".origin.kind");
		var origin:RustMappedOrigin = switch (originKind) {
			case "haxe-source":
				var sourceRaw = object(originRaw.get("source"), label + ".origin.source");
				var source = RustHaxeSourceSpan.at(string(sourceRaw.get("file"), label + ".origin.source.file"),
					integer(sourceRaw.get("startByte"), label + ".origin.source.startByte"),
					integer(sourceRaw.get("endByte"), label + ".origin.source.endByte"),
					positiveInteger(sourceRaw.get("startLine"), label + ".origin.source.startLine"),
					positiveInteger(sourceRaw.get("startColumn"), label + ".origin.source.startColumn"),
					positiveInteger(sourceRaw.get("endLine"), label + ".origin.source.endLine"),
					positiveInteger(sourceRaw.get("endColumn"), label + ".origin.source.endColumn"));
				MappedHaxeSource(source);
			case "compiler-generated":
				MappedCompilerGenerated(reasonFromId(string(originRaw.get("reason"), label + ".origin.reason")));
			case _:
				throw '$label.origin.kind is unsupported: $originKind';
		};
		return new RustSourceMapping(nodeKind, originDepth, generated, origin);
	}

	static function isMorePrecise(candidate:RustSourceMapping, current:RustSourceMapping):Bool {
		var candidateLength = candidate.generated.endByte - candidate.generated.startByte;
		var currentLength = current.generated.endByte - current.generated.startByte;
		if (candidateLength != currentLength)
			return candidateLength < currentLength;
		var candidateKind = nodeKindRank(candidate.nodeKind);
		var currentKind = nodeKindRank(current.nodeKind);
		if (candidateKind != currentKind)
			return candidateKind > currentKind;
		if (candidate.originDepth != current.originDepth)
			return candidate.originDepth > current.originDepth;
		return compareOrigins(candidate.origin, current.origin) < 0;
	}

	static function compareMappings(left:RustSourceMapping, right:RustSourceMapping):Int {
		if (left.generated.startByte != right.generated.startByte)
			return left.generated.startByte - right.generated.startByte;
		if (left.generated.endByte != right.generated.endByte)
			return right.generated.endByte - left.generated.endByte;
		var kindOrder = nodeKindRank(left.nodeKind) - nodeKindRank(right.nodeKind);
		if (kindOrder != 0)
			return kindOrder;
		if (left.originDepth != right.originDepth)
			return left.originDepth < right.originDepth ? -1 : 1;
		return compareOrigins(left.origin, right.origin);
	}

	static function deduplicateMappings(mappings:Array<RustSourceMapping>):Array<RustSourceMapping> {
		var out:Array<RustSourceMapping> = [];
		for (mapping in mappings) {
			if (out.length == 0 || compareMappings(out[out.length - 1], mapping) != 0)
				out.push(mapping);
		}
		return out;
	}

	static function compareOrigins(left:RustMappedOrigin, right:RustMappedOrigin):Int {
		return switch [left, right] {
			case [MappedCompilerGenerated(leftReason), MappedCompilerGenerated(rightReason)]:
				compareStrings(leftReason.id(), rightReason.id());
			case [MappedCompilerGenerated(_), MappedHaxeSource(_)]: -1;
			case [MappedHaxeSource(_), MappedCompilerGenerated(_)]: 1;
			case [MappedHaxeSource(leftSource), MappedHaxeSource(rightSource)]:
				var order = compareStrings(leftSource.file, rightSource.file);
				if (order == 0)
					order = compareInts(leftSource.startByte, rightSource.startByte);
				if (order == 0)
					order = compareInts(leftSource.endByte, rightSource.endByte);
				if (order == 0)
					order = compareInts(leftSource.startLine, rightSource.startLine);
				if (order == 0)
					order = compareInts(leftSource.startColumn, rightSource.startColumn);
				if (order == 0)
					order = compareInts(leftSource.endLine, rightSource.endLine);
				if (order == 0)
					order = compareInts(leftSource.endColumn, rightSource.endColumn);
				order;
		};
	}

	static function nodeKindRank(kind:RustSourceMapNodeKind):Int {
		return switch (kind) {
			case Item: 0;
			case Statement: 1;
			case Expression: 2;
		};
	}

	static function nodeKindId(kind:RustSourceMapNodeKind):String {
		return switch (kind) {
			case Item: "item";
			case Statement: "statement";
			case Expression: "expression";
		};
	}

	static function nodeKindFromId(value:String):RustSourceMapNodeKind {
		return switch (value) {
			case "item": Item;
			case "statement": Statement;
			case "expression": Expression;
			case _: throw 'Unsupported Rust source-map node kind: $value';
		};
	}

	static function reasonFromId(value:String):RustGeneratedOriginReason {
		return RustGeneratedOriginReason.fromId(value);
	}

	static function relativeUnder(file:String, root:String):Null<String> {
		var normalizedFile = canonicalPath(file);
		var normalizedRoot = canonicalPath(root);
		var prefix = StringTools.endsWith(normalizedRoot, "/") ? normalizedRoot : normalizedRoot + "/";
		if (!StringTools.startsWith(normalizedFile, prefix))
			return null;
		return normalizedFile.substr(prefix.length);
	}

	static function canonicalPath(value:String):String {
		if (value == null || value.length == 0)
			throw "Path cannot be empty";
		var normalized = normalizePath(value);
		try {
			if (FileSystem.exists(normalized))
				normalized = normalizePath(FileSystem.fullPath(normalized));
		} catch (_:haxe.Exception) {}
		return normalized;
	}

	static function normalizePath(value:String):String {
		return Path.normalize(value).split("\\").join("/");
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	static function compareInts(left:Int, right:Int):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	/**
		The only dynamic boundary in source-map consumption.

		Why / What / How
		- JSON parsing necessarily yields `Dynamic`. These helpers validate every field immediately and
		  return concrete typed values before any lookup logic runs.
		- No `Dynamic`, `Reflect`, or unchecked object access escapes this small codec section.
	**/
	static function object(value:RustSourceMapJsonValue, label:String):DynamicAccess<RustSourceMapJsonValue> {
		if (value == null)
			throw '$label must be an object';
		return switch (Type.typeof(value)) {
			case TObject: cast value;
			case _: throw '$label must be an object';
		};
	}

	static function array(value:RustSourceMapJsonValue, label:String):Array<RustSourceMapJsonValue> {
		if (value == null || !Std.isOfType(value, Array))
			throw '$label must be an array';
		return cast value;
	}

	static function string(value:RustSourceMapJsonValue, label:String):String {
		if (value == null || !Std.isOfType(value, String))
			throw '$label must be a string';
		return cast value;
	}

	static function integer(value:RustSourceMapJsonValue, label:String):Int {
		if (value == null || !Std.isOfType(value, Int))
			throw '$label must be an integer';
		return cast value;
	}

	static function positiveInteger(value:RustSourceMapJsonValue, label:String):Int {
		var result = integer(value, label);
		if (result <= 0)
			throw '$label must be positive';
		return result;
	}
}
