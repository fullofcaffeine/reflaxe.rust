package reflaxe.rust;

#if macro
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** One request-local binding from a classpath ordinal to its private Haxe path. */
final class SupportCrateAdmissionClasspathBinding {
	public final ref:Int;
	public final path:String;

	public function new(ref:Int, path:String) {
		this.ref = ref;
		this.path = path;
	}
}

/** One declaration locator. Semantic crate policy stays in `SupportCrateRequestPlan`. */
final class SupportCrateAdmissionDeclaration {
	public final ref:Int;
	final sourceRootSegmentValues:Array<String>;

	public function new(ref:Int, sourceRootSegments:Array<String>) {
		this.ref = ref;
		this.sourceRootSegmentValues = sourceRootSegments.copy();
	}

	public function sourceRootSegments():Array<String> {
		return sourceRootSegmentValues.copy();
	}
}

/** Private, one-shot input to the package-owned source-admission helper. */
final class SupportCrateAdmissionRequest {
	final classpathValues:Array<SupportCrateAdmissionClasspathBinding>;
	final declarationValues:Array<SupportCrateAdmissionDeclaration>;

	public function new(classpaths:Array<SupportCrateAdmissionClasspathBinding>, declarations:Array<SupportCrateAdmissionDeclaration>) {
		this.classpathValues = classpaths.copy();
		this.declarationValues = declarations.copy();
	}

	public function classpaths():Array<SupportCrateAdmissionClasspathBinding> {
		return classpathValues.copy();
	}

	public function declarations():Array<SupportCrateAdmissionDeclaration> {
		return declarationValues.copy();
	}
}

/** The only logical entry kinds that a successful helper response can contain. */
enum abstract SupportCrateAdmissionTreeKind(Int) to Int {
	var Directory = 0;
	var File = 1;
}

/** One immutable logical directory or file returned by the helper. */
final class SupportCrateAdmissionTreeEntry {
	public final kind:SupportCrateAdmissionTreeKind;
	final pathSegmentValues:Array<String>;
	final fileByteValues:Null<Bytes>;

	private function new(kind:SupportCrateAdmissionTreeKind, pathSegments:Array<String>, fileBytes:Null<Bytes>) {
		this.kind = kind;
		this.pathSegmentValues = pathSegments.copy();
		this.fileByteValues = fileBytes == null ? null : copyBytes(fileBytes);
	}

	public static function directory(pathSegments:Array<String>):SupportCrateAdmissionTreeEntry {
		return new SupportCrateAdmissionTreeEntry(Directory, pathSegments, null);
	}

	public static function file(pathSegments:Array<String>, bytes:Bytes):SupportCrateAdmissionTreeEntry {
		return new SupportCrateAdmissionTreeEntry(File, pathSegments, bytes);
	}

	public function pathSegments():Array<String> {
		return pathSegmentValues.copy();
	}

	public function fileBytes():Null<Bytes> {
		return fileByteValues == null ? null : copyBytes(fileByteValues);
	}

	static function copyBytes(bytes:Bytes):Bytes {
		return bytes.sub(0, bytes.length);
	}
}

/** One complete admitted tree for one declaration. */
final class SupportCrateAdmissionBundle {
	public final declarationRef:Int;
	public final selectedClasspathRef:Int;
	final entryValues:Array<SupportCrateAdmissionTreeEntry>;

	public function new(declarationRef:Int, selectedClasspathRef:Int, entries:Array<SupportCrateAdmissionTreeEntry>) {
		this.declarationRef = declarationRef;
		this.selectedClasspathRef = selectedClasspathRef;
		this.entryValues = entries.copy();
	}

	public function entries():Array<SupportCrateAdmissionTreeEntry> {
		return entryValues.copy();
	}
}

/** A successful all-or-nothing helper response. */
final class SupportCrateAdmissionAccepted {
	final bundleValues:Array<SupportCrateAdmissionBundle>;

	public function new(bundles:Array<SupportCrateAdmissionBundle>) {
		this.bundleValues = bundles.copy();
	}

	public function bundles():Array<SupportCrateAdmissionBundle> {
		return bundleValues.copy();
	}
}

/** Closed native error categories that the helper can report without leaking host facts. */
enum abstract SupportCrateAdmissionErrorCode(Int) to Int {
	var HostCapabilityUnavailable = 1;
	var ClasspathInvalid = 2;
	var SourceNotFound = 3;
	var SourceAmbiguous = 4;
	var SourceInvalid = 5;
	var SourceChanged = 6;
}

/** One classified helper rejection. `-1` means that an ordinal is not applicable. */
final class SupportCrateAdmissionRejected {
	public final code:SupportCrateAdmissionErrorCode;
	public final declarationRef:Int;
	public final classpathRef:Int;
	public final componentIndex:Int;

	public function new(code:SupportCrateAdmissionErrorCode, declarationRef:Int, classpathRef:Int, componentIndex:Int) {
		this.code = code;
		this.declarationRef = declarationRef;
		this.classpathRef = classpathRef;
		this.componentIndex = componentIndex;
	}
}

/** The only two complete response outcomes. */
enum SupportCrateAdmissionResponse {
	Accepted(value:SupportCrateAdmissionAccepted);
	Rejected(value:SupportCrateAdmissionRejected);
}

/** Stable internal decoder error. Public compiler diagnostics map this to one typed diagnostic ID. */
final class SupportCrateAdmissionProtocolError extends haxe.Exception {}

/**
	Closed binary protocol for Stage 2B support-crate source admission.

	Why
	- The native helper needs private classpath locators, but paths must never enter durable plans.
	- A strict binary frame avoids an untyped JSON or reflection boundary inside the compiler.

	What
	- Encodes one request and one all-or-nothing response with fixed little-endian fields.
	- Carries both directory and file entries so Haxe can validate the complete logical tree.

	How
	- Every count, ordinal, kind, length, order, and reserved field is validated before use.
	- Arrays and byte buffers are copied at model boundaries.
	- Native paths exist only in `SupportCrateAdmissionRequest` and request bytes.
**/
final class SupportCrateAdmissionProtocol {
	public static inline var MAJOR:Int = 1;
	public static inline var MINOR:Int = 0;
	public static inline var MAX_CLASSPATHS:Int = 256;
	public static inline var MAX_CLASSPATH_BYTES:Int = 16 * 1024;
	public static inline var MAX_CLASSPATH_COMPONENTS:Int = 128;
	public static inline var MAX_DECLARATIONS:Int = 32;
	public static inline var MAX_REQUEST_BYTES:Int = 1024 * 1024;
	public static inline var MAX_FILES_PER_CRATE:Int = 256;
	public static inline var MAX_TREE_ENTRIES_PER_CRATE:Int = MAX_FILES_PER_CRATE * 33;
	public static inline var MAX_PATH_DEPTH:Int = 32;
	public static inline var MAX_PATH_SEGMENT_BYTES:Int = 255;
	public static inline var MAX_FILE_BYTES:Int = 2 * 1024 * 1024;
	public static inline var MAX_CRATE_BYTES:Int = 16 * 1024 * 1024;
	public static inline var MAX_TOTAL_SOURCE_BYTES:Int = 32 * 1024 * 1024;
	public static inline var MAX_RESPONSE_BYTES:Int = 40 * 1024 * 1024;
	static inline var SLASH_BYTE:Int = 47;

	static final REQUEST_MAGIC = Bytes.ofString("HXRSADQ1");
	static final RESPONSE_MAGIC = Bytes.ofString("HXRSADR1");

	public static function encodeRequest(request:SupportCrateAdmissionRequest):Bytes {
		var classpaths = request.classpaths();
		var declarations = request.declarations();
		requireCount("classpath", classpaths.length, 1, MAX_CLASSPATHS);
		requireCount("declaration", declarations.length, 1, MAX_DECLARATIONS);

		var payload = new AdmissionFrameWriter();
		for (index in 0...classpaths.length) {
			var classpath = classpaths[index];
			if (classpath.ref != index)
				throw protocolError("classpath refs must equal their frame ordinal");
			payload.writeU32(classpath.ref);
			payload.writeSizedString(classpath.path, MAX_CLASSPATH_BYTES, "classpath path");
		}
		for (index in 0...declarations.length) {
			var declaration = declarations[index];
			if (declaration.ref != index)
				throw protocolError("declaration refs must equal their frame ordinal");
			var segments = declaration.sourceRootSegments();
			requireCount("sourceRoot segment", segments.length, 1, MAX_PATH_DEPTH);
			payload.writeU32(declaration.ref);
			payload.writeU16(segments.length);
			payload.writeU16(0);
			for (segment in segments)
				payload.writeSegment(segment);
		}

		var payloadBytes = payload.toBytes();
		var frame = new AdmissionFrameWriter();
		frame.writeBytes(REQUEST_MAGIC);
		frame.writeU16(MAJOR);
		frame.writeU16(MINOR);
		frame.writeU32(payloadBytes.length);
		frame.writeU32(0);
		frame.writeU16(classpaths.length);
		frame.writeU16(declarations.length);
		frame.writeBytes(payloadBytes);
		var bytes = frame.toBytes();
		if (bytes.length > MAX_REQUEST_BYTES)
			throw protocolError("request frame exceeds its byte limit");
		return bytes;
	}

	public static function decodeRequest(bytes:Bytes):SupportCrateAdmissionRequest {
		if (bytes.length > MAX_REQUEST_BYTES)
			throw protocolError("request frame exceeds its byte limit");
		var reader = new AdmissionFrameReader(bytes);
		reader.requireMagic(REQUEST_MAGIC, "request");
		requireVersion(reader);
		var payloadLength = reader.readBoundedU32(MAX_REQUEST_BYTES, "request payload length");
		if (reader.readU32() != 0)
			throw protocolError("request flags must be zero");
		var classpathCount = reader.readU16();
		var declarationCount = reader.readU16();
		requireCount("classpath", classpathCount, 1, MAX_CLASSPATHS);
		requireCount("declaration", declarationCount, 1, MAX_DECLARATIONS);
		if (payloadLength != reader.remaining())
			throw protocolError("request payload length does not match the frame");

		var classpaths = new Array<SupportCrateAdmissionClasspathBinding>();
		for (index in 0...classpathCount) {
			var ref = reader.readU32();
			if (ref != index)
				throw protocolError("classpath refs must equal their frame ordinal");
			classpaths.push(new SupportCrateAdmissionClasspathBinding(ref, reader.readSizedString(MAX_CLASSPATH_BYTES, "classpath path")));
		}
		var declarations = new Array<SupportCrateAdmissionDeclaration>();
		for (index in 0...declarationCount) {
			var ref = reader.readU32();
			if (ref != index)
				throw protocolError("declaration refs must equal their frame ordinal");
			var segmentCount = reader.readU16();
			requireCount("sourceRoot segment", segmentCount, 1, MAX_PATH_DEPTH);
			if (reader.readU16() != 0)
				throw protocolError("declaration reserved field must be zero");
			var segments = new Array<String>();
			for (_ in 0...segmentCount)
				segments.push(reader.readSegment());
			declarations.push(new SupportCrateAdmissionDeclaration(ref, segments));
		}
		reader.requireEnd("request");
		return new SupportCrateAdmissionRequest(classpaths, declarations);
	}

	public static function encodeResponse(response:SupportCrateAdmissionResponse):Bytes {
		var payload = new AdmissionFrameWriter();
		var status = 0;
		var bundleCount = 0;
		switch (response) {
			case Accepted(value):
				var bundles = value.bundles();
				requireCount("response bundle", bundles.length, 1, MAX_DECLARATIONS);
				bundleCount = bundles.length;
				for (index in 0...bundles.length)
					writeBundle(payload, bundles[index], index);
			case Rejected(value):
				status = 1;
				payload.writeU16(value.code);
				payload.writeU16(0);
				payload.writeU32(value.declarationRef);
				payload.writeU32(value.classpathRef);
				payload.writeU32(value.componentIndex);
		}

		var payloadBytes = payload.toBytes();
		var frame = new AdmissionFrameWriter();
		frame.writeBytes(RESPONSE_MAGIC);
		frame.writeU16(MAJOR);
		frame.writeU16(MINOR);
		frame.writeU32(payloadBytes.length);
		frame.writeU16(status);
		frame.writeU16(bundleCount);
		frame.writeU32(0);
		frame.writeBytes(payloadBytes);
		var bytes = frame.toBytes();
		if (bytes.length > MAX_RESPONSE_BYTES)
			throw protocolError("response frame exceeds its byte limit");
		return bytes;
	}

	public static function decodeResponse(bytes:Bytes, expectedClasspaths:Int, expectedDeclarations:Int):SupportCrateAdmissionResponse {
		requireCount("expected classpath", expectedClasspaths, 1, MAX_CLASSPATHS);
		requireCount("expected declaration", expectedDeclarations, 1, MAX_DECLARATIONS);
		if (bytes.length > MAX_RESPONSE_BYTES)
			throw protocolError("response frame exceeds its byte limit");
		var reader = new AdmissionFrameReader(bytes);
		reader.requireMagic(RESPONSE_MAGIC, "response");
		requireVersion(reader);
		var payloadLength = reader.readBoundedU32(MAX_RESPONSE_BYTES, "response payload length");
		var status = reader.readU16();
		var bundleCount = reader.readU16();
		if (reader.readU32() != 0)
			throw protocolError("response flags must be zero");
		if (payloadLength != reader.remaining())
			throw protocolError("response payload length does not match the frame");

		var response:SupportCrateAdmissionResponse;
		switch (status) {
			case 0:
				if (bundleCount != expectedDeclarations)
					throw protocolError("success response must contain every expected bundle");
				var bundles = new Array<SupportCrateAdmissionBundle>();
				var totalSourceBytes = 0;
				for (index in 0...bundleCount) {
					var decoded = readBundle(reader, index, expectedClasspaths);
					totalSourceBytes += decoded.sourceBytes;
					if (totalSourceBytes > MAX_TOTAL_SOURCE_BYTES)
						throw protocolError("response exceeds the total source-byte limit");
					bundles.push(decoded.bundle);
				}
				response = Accepted(new SupportCrateAdmissionAccepted(bundles));
			case 1:
				if (bundleCount != 0)
					throw protocolError("rejected response cannot contain bundles");
				var code = decodeErrorCode(reader.readU16());
				if (reader.readU16() != 0)
					throw protocolError("error reserved field must be zero");
				var declarationRef = reader.readU32();
				var classpathRef = reader.readU32();
				var componentIndex = reader.readU32();
				requireOptionalOrdinal("declaration", declarationRef, expectedDeclarations);
				requireOptionalOrdinal("classpath", classpathRef, expectedClasspaths);
				if (componentIndex < -1 || componentIndex >= MAX_CLASSPATH_COMPONENTS)
					throw protocolError("error component index is outside the closed range");
				response = Rejected(new SupportCrateAdmissionRejected(code, declarationRef, classpathRef, componentIndex));
			default:
				throw protocolError("response status is unknown");
		}
		reader.requireEnd("response");
		return response;
	}

	static function writeBundle(writer:AdmissionFrameWriter, bundle:SupportCrateAdmissionBundle, expectedRef:Int):Void {
		if (bundle.declarationRef != expectedRef)
			throw protocolError("bundle declaration refs must equal their frame ordinal");
		if (bundle.selectedClasspathRef < 0 || bundle.selectedClasspathRef >= MAX_CLASSPATHS)
			throw protocolError("selected classpath ref is outside the closed range");
		var entries = bundle.entries();
		requireCount("tree entry", entries.length, 1, MAX_TREE_ENTRIES_PER_CRATE);
		writer.writeU32(bundle.declarationRef);
		writer.writeU32(bundle.selectedClasspathRef);
		writer.writeU16(entries.length);
		writer.writeU16(0);
		var lastPath:Null<Bytes> = null;
		var fileCount = 0;
		var crateBytes = 0;
		for (entry in entries) {
			var encodedPath = encodedLogicalPath(entry.pathSegments());
			if (lastPath != null && lastPath.compare(encodedPath) >= 0)
				throw protocolError("tree entries must use strict byte order without duplicates");
			lastPath = encodedPath;
			writer.writeU8(entry.kind);
			writer.writeU8(0);
			var segments = entry.pathSegments();
			writer.writeU16(segments.length);
			for (segment in segments)
				writer.writeSegment(segment);
			switch (entry.kind) {
				case Directory:
					if (entry.fileBytes() != null)
						throw protocolError("directory entry cannot contain file bytes");
					writer.writeU32(0);
				case File:
					var bytes = entry.fileBytes();
					if (bytes == null)
						throw protocolError("file entry must contain bytes");
					fileCount++;
					if (fileCount > MAX_FILES_PER_CRATE || bytes.length > MAX_FILE_BYTES)
						throw protocolError("file entry exceeds its closed byte or count limit");
					crateBytes += bytes.length;
					if (crateBytes > MAX_CRATE_BYTES)
						throw protocolError("bundle exceeds its source-byte limit");
					writer.writeU32(bytes.length);
					writer.writeBytes(bytes);
			}
		}
	}

	static function readBundle(reader:AdmissionFrameReader, expectedRef:Int,
		expectedClasspaths:Int):{bundle:SupportCrateAdmissionBundle, sourceBytes:Int} {
		var declarationRef = reader.readU32();
		if (declarationRef != expectedRef)
			throw protocolError("bundle declaration refs must equal their frame ordinal");
		var selectedClasspathRef = reader.readU32();
		if (selectedClasspathRef < 0 || selectedClasspathRef >= expectedClasspaths)
			throw protocolError("selected classpath ref is outside the request range");
		var entryCount = reader.readU16();
		requireCount("tree entry", entryCount, 1, MAX_TREE_ENTRIES_PER_CRATE);
		if (reader.readU16() != 0)
			throw protocolError("bundle reserved field must be zero");
		var entries = new Array<SupportCrateAdmissionTreeEntry>();
		var lastPath:Null<Bytes> = null;
		var fileCount = 0;
		var crateBytes = 0;
		for (_ in 0...entryCount) {
			var kind = decodeTreeKind(reader.readU8());
			if (reader.readU8() != 0)
				throw protocolError("tree-entry reserved field must be zero");
			var segmentCount = reader.readU16();
			requireCount("tree path segment", segmentCount, 1, MAX_PATH_DEPTH);
			var segments = new Array<String>();
			for (_ in 0...segmentCount)
				segments.push(reader.readSegment());
			var encodedPath = encodedLogicalPath(segments);
			if (lastPath != null && lastPath.compare(encodedPath) >= 0)
				throw protocolError("tree entries must use strict byte order without duplicates");
			lastPath = encodedPath;
			var byteLength = reader.readBoundedU32(MAX_FILE_BYTES, "tree-entry byte length");
			switch (kind) {
				case Directory:
					if (byteLength != 0)
						throw protocolError("directory entry cannot contain file bytes");
					entries.push(SupportCrateAdmissionTreeEntry.directory(segments));
				case File:
					fileCount++;
					if (fileCount > MAX_FILES_PER_CRATE)
						throw protocolError("bundle exceeds its file-count limit");
					crateBytes += byteLength;
					if (crateBytes > MAX_CRATE_BYTES)
						throw protocolError("bundle exceeds its source-byte limit");
					entries.push(SupportCrateAdmissionTreeEntry.file(segments, reader.readBytes(byteLength)));
			}
		}
		return {
			bundle: new SupportCrateAdmissionBundle(declarationRef, selectedClasspathRef, entries),
			sourceBytes: crateBytes
		};
	}

	static function requireVersion(reader:AdmissionFrameReader):Void {
		if (reader.readU16() != MAJOR || reader.readU16() != MINOR)
			throw protocolError("protocol version is unsupported");
	}

	static function requireCount(name:String, value:Int, minimum:Int, maximum:Int):Void {
		if (value < minimum || value > maximum)
			throw protocolError(name + " count is outside the closed range");
	}

	static function requireOptionalOrdinal(name:String, value:Int, upperExclusive:Int):Void {
		if (value != -1 && (value < 0 || value >= upperExclusive))
			throw protocolError(name + " ref is outside the request range");
	}

	static function decodeTreeKind(value:Int):SupportCrateAdmissionTreeKind {
		return switch (value) {
			case 0: Directory;
			case 1: File;
			default: throw protocolError("tree-entry kind is unknown");
		}
	}

	static function decodeErrorCode(value:Int):SupportCrateAdmissionErrorCode {
		return switch (value) {
			case 1: HostCapabilityUnavailable;
			case 2: ClasspathInvalid;
			case 3: SourceNotFound;
			case 4: SourceAmbiguous;
			case 5: SourceInvalid;
			case 6: SourceChanged;
			default: throw protocolError("admission error code is unknown");
		}
	}

	static function encodedLogicalPath(segments:Array<String>):Bytes {
		requireCount("tree path segment", segments.length, 1, MAX_PATH_DEPTH);
		var writer = new AdmissionFrameWriter();
		for (index in 0...segments.length) {
			if (index > 0)
				writer.writeU8(SLASH_BYTE);
			writer.writeBytes(AdmissionFrameWriter.validatedStringBytes(segments[index], MAX_PATH_SEGMENT_BYTES, "path segment", true));
		}
		return writer.toBytes();
	}

	static function protocolError(detail:String):SupportCrateAdmissionProtocolError {
		return new SupportCrateAdmissionProtocolError(detail);
	}
}

private final class AdmissionFrameWriter {
	final buffer:BytesBuffer;

	public function new() {
		buffer = new BytesBuffer();
	}

	public function writeU8(value:Int):Void { // numeric-suffix-guard: allow-standard-encoding (unsigned 8-bit field)
		if (value < 0 || value > 0xff)
			throw new SupportCrateAdmissionProtocolError("u8 value is outside its range");
		buffer.addByte(value);
	}

	public function writeU16(value:Int):Void { // numeric-suffix-guard: allow-standard-encoding (unsigned 16-bit field)
		if (value < 0 || value > 0xffff)
			throw new SupportCrateAdmissionProtocolError("u16 value is outside its range");
		buffer.addByte(value & 0xff);
		buffer.addByte((value >>> 8) & 0xff);
	}

	public function writeU32(value:Int):Void { // numeric-suffix-guard: allow-standard-encoding (unsigned 32-bit field)
		if (value < -1)
			throw new SupportCrateAdmissionProtocolError("u32 value is outside the admitted range");
		buffer.addByte(value & 0xff);
		buffer.addByte((value >>> 8) & 0xff);
		buffer.addByte((value >>> 16) & 0xff);
		buffer.addByte((value >>> 24) & 0xff);
	}

	public function writeBytes(bytes:Bytes):Void {
		buffer.addBytes(bytes, 0, bytes.length);
	}

	public function writeSizedString(value:String, maximumBytes:Int, name:String):Void {
		var bytes = validatedStringBytes(value, maximumBytes, name, false);
		writeU32(bytes.length);
		writeBytes(bytes);
	}

	public function writeSegment(value:String):Void {
		var bytes = validatedStringBytes(value, SupportCrateAdmissionProtocol.MAX_PATH_SEGMENT_BYTES, "path segment", true);
		writeU16(bytes.length);
		writeBytes(bytes);
	}

	public function toBytes():Bytes {
		return buffer.getBytes();
	}

	public static function validatedStringBytes(value:String, maximumBytes:Int, name:String, rejectSlash:Bool):Bytes {
		var bytes = Bytes.ofString(value);
		if (bytes.length == 0 && rejectSlash)
			throw new SupportCrateAdmissionProtocolError(name + " cannot be empty");
		if (bytes.length > maximumBytes)
			throw new SupportCrateAdmissionProtocolError(name + " exceeds its byte limit");
		for (index in 0...bytes.length) {
			var byte = bytes.get(index);
			if (byte == 0)
				throw new SupportCrateAdmissionProtocolError(name + " contains NUL");
			if (rejectSlash && byte == 47)
				throw new SupportCrateAdmissionProtocolError(name + " contains a path separator");
		}
		return bytes;
	}
}

private final class AdmissionFrameReader {
	final bytes:Bytes;
	var offset:Int;

	public function new(bytes:Bytes) {
		this.bytes = bytes;
		this.offset = 0;
	}

	public function remaining():Int {
		return bytes.length - offset;
	}

	public function readU8():Int { // numeric-suffix-guard: allow-standard-encoding (unsigned 8-bit field)
		requireAvailable(1);
		return bytes.get(offset++);
	}

	public function readU16():Int { // numeric-suffix-guard: allow-standard-encoding (unsigned 16-bit field)
		var first = readU8();
		return first | (readU8() << 8);
	}

	public function readU32():Int { // numeric-suffix-guard: allow-standard-encoding (unsigned 32-bit field)
		var first = readU8();
		var second = readU8();
		var third = readU8();
		var fourth = readU8();
		return first | (second << 8) | (third << 16) | (fourth << 24);
	}

	public function readBoundedU32(maximum:Int, // numeric-suffix-guard: allow-standard-encoding (unsigned 32-bit field)
		name:String):Int {
		var value = readU32();
		if (value < 0 || value > maximum)
			throw new SupportCrateAdmissionProtocolError(name + " is outside its closed range");
		return value;
	}

	public function readBytes(length:Int):Bytes {
		requireAvailable(length);
		var value = bytes.sub(offset, length);
		offset += length;
		return value;
	}

	public function readSizedString(maximumBytes:Int, name:String):String {
		var length = readBoundedU32(maximumBytes, name + " length");
		return decodeString(readBytes(length), name, false);
	}

	public function readSegment():String {
		var length = readU16();
		if (length < 1 || length > SupportCrateAdmissionProtocol.MAX_PATH_SEGMENT_BYTES)
			throw new SupportCrateAdmissionProtocolError("path segment length is outside its closed range");
		return decodeString(readBytes(length), "path segment", true);
	}

	public function requireMagic(expected:Bytes, name:String):Void {
		if (readBytes(expected.length).compare(expected) != 0)
			throw new SupportCrateAdmissionProtocolError(name + " magic is invalid");
	}

	public function requireEnd(name:String):Void {
		if (remaining() != 0)
			throw new SupportCrateAdmissionProtocolError(name + " contains trailing bytes");
	}

	function requireAvailable(length:Int):Void {
		if (length < 0 || length > remaining())
			throw new SupportCrateAdmissionProtocolError("frame is truncated");
	}

	static function decodeString(bytes:Bytes, name:String, rejectSlash:Bool):String {
		for (index in 0...bytes.length) {
			var byte = bytes.get(index);
			if (byte == 0)
				throw new SupportCrateAdmissionProtocolError(name + " contains NUL");
			if (rejectSlash && byte == 47)
				throw new SupportCrateAdmissionProtocolError(name + " contains a path separator");
		}
		var value:String;
		try {
			value = bytes.toString();
		} catch (_:haxe.Exception) {
			throw new SupportCrateAdmissionProtocolError(name + " is not canonical UTF-8");
		}
		if (Bytes.ofString(value).compare(bytes) != 0)
			throw new SupportCrateAdmissionProtocolError(name + " is not canonical UTF-8");
		return value;
	}
}
#end
