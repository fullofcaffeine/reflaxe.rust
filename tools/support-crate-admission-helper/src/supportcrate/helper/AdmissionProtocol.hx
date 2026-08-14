package supportcrate.helper;

import rust.Option;
import rust.Result;
import rust.Vec;
import rust.VecTools;
import rust.process.CurrentProcess;
import supportcrate.helper.AdmissionEngine.AdmissionBundle;

final class AdmissionClasspath {
	public final ref:Int;
	public final path:String;

	public function new(ref:Int, path:String) {
		this.ref = ref;
		this.path = path;
	}
}

final class AdmissionDeclaration {
	public final ref:Int;
	public final sourceRoot:Vec<String>;

	public function new(ref:Int, sourceRoot:Vec<String>) {
		this.ref = ref;
		this.sourceRoot = sourceRoot;
	}
}

final class AdmissionRequest {
	public final classpaths:Vec<AdmissionClasspath>;
	public final declarations:Vec<AdmissionDeclaration>;

	public function new(classpaths:Vec<AdmissionClasspath>, declarations:Vec<AdmissionDeclaration>) {
		this.classpaths = classpaths;
		this.declarations = declarations;
	}
}

/** Metal-side decoder and response writer for the closed internal protocol. */
final class AdmissionProtocol {
	public static inline final MAX_REQUEST_BYTES = 1024 * 1024;
	public static inline final MAX_CLASSPATHS = 256;
	public static inline final MAX_CLASSPATH_BYTES = 16 * 1024;
	public static inline final MAX_DECLARATIONS = 32;
	public static inline final MAX_PATH_DEPTH = 32;
	public static inline final MAX_PATH_SEGMENT_BYTES = 255;

	static inline final MAJOR = 1;
	static inline final MINOR = 0;

	public static function readRequest():Option<AdmissionRequest> {
		var bytes = new Vec<Int>();
		var complete = false;
		while (!complete) {
			var nextLimit = MAX_REQUEST_BYTES - AdmissionByteTools.length(bytes);
			if (nextLimit <= 0)
				nextLimit = 1;
			switch CurrentProcess.readStdinChunk(nextLimit) {
				case Err(_): return None;
				case Ok(chunk):
					if (chunk.isEmpty()) {
						complete = true;
					} else {
						bytes = AdmissionByteTools.append(bytes, chunk);
						if (AdmissionByteTools.length(bytes) > MAX_REQUEST_BYTES)
							return None;
					}
			}
		}
		return decodeRequest(bytes);
	}

	public static function decodeRequest(bytes:Vec<Int>):Option<AdmissionRequest> {
		var reader = new AdmissionReader(bytes);
		if (!reader.readMagic("HXRSADQ1") || reader.readU16() != MAJOR || reader.readU16() != MINOR)
			return None;
		var payloadLength = reader.readU32();
		if (payloadLength < 0 || payloadLength > MAX_REQUEST_BYTES || reader.readU32() != 0)
			return None;
		var classpathCount = reader.readU16();
		var declarationCount = reader.readU16();
		if (!closedCount(classpathCount, 1, MAX_CLASSPATHS) || !closedCount(declarationCount, 1, MAX_DECLARATIONS))
			return None;
		if (payloadLength != reader.remaining())
			return None;

		var classpaths = new Vec<AdmissionClasspath>();
		for (index in 0...classpathCount) {
			if (reader.readU32() != index)
				return None;
			var path = reader.readString32(MAX_CLASSPATH_BYTES, false);
			if (!reader.valid || !validClasspathLocator(path))
				return None;
			classpaths.push(new AdmissionClasspath(index, path));
		}

		var declarations = new Vec<AdmissionDeclaration>();
		for (index in 0...declarationCount) {
			if (reader.readU32() != index)
				return None;
			var segmentCount = reader.readU16();
			if (!closedCount(segmentCount, 1, MAX_PATH_DEPTH) || reader.readU16() != 0)
				return None;
			var segments = new Vec<String>();
			for (_ in 0...segmentCount) {
				var segment = reader.readString16(MAX_PATH_SEGMENT_BYTES, true);
				if (!reader.valid || !validSourceSegment(segment))
					return None;
				segments.push(segment);
			}
			declarations.push(new AdmissionDeclaration(index, segments));
		}
		if (!reader.valid || reader.remaining() != 0)
			return None;
		return Some(new AdmissionRequest(classpaths, declarations));
	}

	public static function rejected(code:Int, declarationRef:Int, classpathRef:Int, componentIndex:Int):Vec<Int> {
		var payload = new AdmissionWriter();
		payload.writeU16(code);
		payload.writeU16(0);
		payload.writeU32(declarationRef);
		payload.writeU32(classpathRef);
		payload.writeU32(componentIndex);
		var payloadBytes = payload.finish();

		var frame = new AdmissionWriter();
		frame.writeAscii("HXRSADR1");
		frame.writeU16(MAJOR);
		frame.writeU16(MINOR);
		frame.writeU32(AdmissionByteTools.length(payloadBytes));
		frame.writeU16(1);
		frame.writeU16(0);
		frame.writeU32(0);
		frame.writeAll(payloadBytes);
		return frame.finish();
	}

	public static function accepted(bundles:Vec<AdmissionBundle>):Vec<Int> {
		var payload = new AdmissionWriter();
		var bundleIndex = 0;
		while (bundleIndex < VecTools.len(bundles)) {
			var bundle = switch VecTools.get(bundles, bundleIndex) {
				case Some(value): value;
				case None: return rejected(5, bundleIndex, -1, -1);
			};
			payload.writeU32(bundle.declarationRef);
			payload.writeU32(bundle.classpathRef);
			payload.writeU16(VecTools.len(bundle.entries));
			payload.writeU16(0);
			var entryIndex = 0;
			while (entryIndex < VecTools.len(bundle.entries)) {
				var entry = switch VecTools.get(bundle.entries, entryIndex) {
					case Some(value): value;
					case None: return rejected(5, bundle.declarationRef, bundle.classpathRef, -1);
				};
				payload.writeU8(entry.kind);
				payload.writeU8(0);
				payload.writeU16(VecTools.len(entry.path));
				var pathIndex = 0;
				while (pathIndex < VecTools.len(entry.path)) {
					switch VecTools.get(entry.path, pathIndex) {
						case Some(segment): payload.writeString16(segment);
						case None: return rejected(5, bundle.declarationRef, bundle.classpathRef, pathIndex);
					}
					pathIndex++;
				}
				switch entry.bytes {
					case None: payload.writeU32(0);
					case Some(bytes):
						payload.writeU32(AdmissionByteTools.length(bytes));
						payload.writeAll(bytes);
				}
				entryIndex++;
			}
			bundleIndex++;
		}
		var payloadBytes = payload.finish();
		var frame = new AdmissionWriter();
		frame.writeAscii("HXRSADR1");
		frame.writeU16(MAJOR);
		frame.writeU16(MINOR);
		frame.writeU32(AdmissionByteTools.length(payloadBytes));
		frame.writeU16(0);
		frame.writeU16(VecTools.len(bundles));
		frame.writeU32(0);
		frame.writeAll(payloadBytes);
		return frame.finish();
	}

	static function closedCount(value:Int, minimum:Int, maximum:Int):Bool {
		return value >= minimum && value <= maximum;
	}

	static function validClasspathLocator(value:String):Bool {
		if (value.length > 1 && value.charAt(0) == "/" && value.charAt(1) == "/")
			return false;
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			if (code == 0 || code == "\\".code || code < 0x20 || code == 0x7f)
				return false;
		}
		return true;
	}

	static function validSourceSegment(value:String):Bool {
		if (value.length == 0 || value == "." || value == "..")
			return false;
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			if (code == 0 || code == "/".code || code == "\\".code || code == ":".code || code < 0x20 || code == 0x7f)
				return false;
		}
		return true;
	}
}

private final class AdmissionReader {
	final bytes:Vec<Int>;
	var offset:Int;
	public var valid(default, null):Bool;

	public function new(bytes:Vec<Int>) {
		this.bytes = bytes;
		offset = 0;
		valid = true;
	}

	public function remaining():Int {
		return AdmissionByteTools.length(bytes) - offset;
	}

	public function readMagic(expected:String):Bool {
		var expectedBytes = AdmissionByteTools.encodeUtf8(expected);
		for (index in 0...AdmissionByteTools.length(expectedBytes))
			if (readU8() != AdmissionByteTools.get(expectedBytes, index))
				return false;
		return valid;
	}

	public function readU8():Int {
		if (!valid || remaining() < 1) {
			valid = false;
			return 0;
		}
		var value = AdmissionByteTools.get(bytes, offset);
		offset++;
		if (value < 0 || value > 255) {
			valid = false;
			return 0;
		}
		return value;
	}

	public function readU16():Int {
		var first = readU8();
		return first | (readU8() << 8);
	}

	public function readU32():Int {
		var first = readU8();
		var second = readU8();
		var third = readU8();
		var fourth = readU8();
		return first | (second << 8) | (third << 16) | (fourth << 24);
	}

	public function readString16(maximum:Int, rejectSlash:Bool):String {
		return readString(readU16(), maximum, rejectSlash);
	}

	public function readString32(maximum:Int, rejectSlash:Bool):String {
		return readString(readU32(), maximum, rejectSlash);
	}

	function readString(length:Int, maximum:Int, rejectSlash:Bool):String {
		if (length < 0 || length > maximum || length > remaining()) {
			valid = false;
			return "";
		}
		var value = new Vec<Int>();
		for (_ in 0...length) {
			var byte = readU8();
			if (byte == 0 || (rejectSlash && byte == "/".code))
				valid = false;
			value.push(byte);
		}
		return switch AdmissionByteTools.decodeUtf8(value) {
			case Ok(text): text;
			case Err(_):
				valid = false;
				"";
		};
	}
}

private final class AdmissionWriter {
	var bytes:Vec<Int>;

	public function new() {
		bytes = new Vec<Int>();
	}

	public function writeAscii(value:String):Void {
		writeAll(AdmissionByteTools.encodeUtf8(value));
	}

	public function writeU8(value:Int):Void {
		bytes = AdmissionByteTools.appendByte(bytes, value & 0xff);
	}

	public function writeString16(value:String):Void {
		var encoded = AdmissionByteTools.encodeUtf8(value);
		writeU16(AdmissionByteTools.length(encoded));
		writeAll(encoded);
	}

	public function writeU16(value:Int):Void {
		bytes = AdmissionByteTools.appendByte(bytes, value & 0xff);
		bytes = AdmissionByteTools.appendByte(bytes, (value >>> 8) & 0xff);
	}

	public function writeU32(value:Int):Void {
		bytes = AdmissionByteTools.appendByte(bytes, value & 0xff);
		bytes = AdmissionByteTools.appendByte(bytes, (value >>> 8) & 0xff);
		bytes = AdmissionByteTools.appendByte(bytes, (value >>> 16) & 0xff);
		bytes = AdmissionByteTools.appendByte(bytes, (value >>> 24) & 0xff);
	}

	public function writeAll(value:Vec<Int>):Void {
		bytes = AdmissionByteTools.append(bytes, value);
	}

	public function finish():Vec<Int> {
		return bytes;
	}
}
