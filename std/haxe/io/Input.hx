package haxe.io;

/**
	`haxe.io.Input` (Rust target override)

	Why
	- The upstream Haxe std implementation of `Input.readBytes` writes into the provided `Bytes`
	  using target-specific internal storage access (`Bytes.getData()` or private fields).
	- On reflaxe.rust, `haxe.io.Bytes` is an `extern` wrapper over a Rust-owned buffer
	  (`HxRef<hxrt::bytes::Bytes>`), so direct internal data access is intentionally unavailable.

	What
	- An abstract reader API used throughout the stdlib.
	- Concrete inputs are expected to override `readByte()` and optionally `readBytes()`.

	How
	- The only behavioral difference vs upstream is the implementation of `readBytes`:
	  it uses `Bytes.set(...)` instead of `getData()`.
	- Everything else is kept very close to upstream so macro-time std code and portable libraries
	  continue to typecheck.
**/
class Input {
	/**
		Endianness (word byte order) used when reading numbers.

		If `true`, big-endian is used, otherwise `little-endian` is used.
	**/
	public var bigEndian(default, set):Bool;

	#if cs
	private var helper:BytesData;
	#elseif java
	private var helper:java.nio.ByteBuffer;
	#end

	/**
		Read and return one byte.
	**/
	public function readByte():Int {
		throw Error.Custom("Input.readByte is not implemented");
		return 0;
	}

	/**
		Read `len` bytes and write them into `s` to the position specified by `pos`.

		Returns the actual length of read data that can be smaller than `len`.

		See `readFullBytes` that tries to read the exact amount of specified bytes.
	**/
	public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		var k = len;
		var p = pos;
		if (p < 0 || len < 0 || p + len > s.length)
			throw Error.OutsideBounds;
		try {
			while (k > 0) {
				s.set(p, cast readByte());
				p++;
				k--;
			}
		} catch (eof:haxe.io.Eof) {}
		return len - k;
	}

	/**
		Close the input source.

		Behaviour while reading after calling this method is unspecified.
	**/
	public function close():Void {}

	function set_bigEndian(b:Bool):Bool {
		bigEndian = b;
		return b;
	}

	/* ------------------ API ------------------ */
	/**
		Read and return all available data.

		The `bufsize` optional argument specifies the size of chunks by
		which data is read. Its default value is target-specific.
	**/
	public function readAll(?bufsize:Int):Bytes {
		var bs:Null<Int> = bufsize;
		if (bs == null)
			#if php
			bs = 8192; // default value for PHP and max under certain circumstances
			#else
			bs = (1 << 14); // 16 Ko
			#end
		var bufsize:Int = bs;

		var buf = Bytes.alloc(bufsize);
		var total = new haxe.io.BytesBuffer();
		try {
			while (true) {
				var len = readBytes(buf, 0, bufsize);
				if (len == 0)
					throw Error.Blocked;
				total.addBytes(buf, 0, len);
			}
		} catch (e:Eof) {}
		return total.getBytes();
	}

	/**
		Read `len` bytes and write them into `s` to the position specified by `pos`.

		Unlike `readBytes`, this method tries to read the exact `len` amount of bytes.
	**/
	public function readFullBytes(s:Bytes, pos:Int, len:Int):Void {
		var p = pos;
		var l = len;
		while (l > 0) {
			var k = readBytes(s, p, l);
			if (k == 0)
				throw Error.Blocked;
			p += k;
			l -= k;
		}
	}

	/**
		Read and return `nbytes` bytes.
	**/
	public function read(nbytes:Int):Bytes {
		var remaining = nbytes;
		var s = Bytes.alloc(remaining);
		var p = 0;
		while (remaining > 0) {
			var k = readBytes(s, p, remaining);
			if (k == 0)
				throw Error.Blocked;
			p += k;
			remaining -= k;
		}
		return s;
	}

	/**
		Read a string until a character code specified by `end` is occurred.

		The final character is not included in the resulting string.
	**/
	public function readUntil(end:Int):String {
		var buf = new BytesBuffer();
		while (true) {
			var last = readByte();
			if (last == end) break;
			buf.addByte(last);
		}
		return buf.getBytes().toString();
	}

	/**
		Read a line of text separated by CR and/or LF bytes.

		The CR/LF characters are not included in the resulting string.
	**/
	public function readLine():String {
		var buf = new BytesBuffer();
		try {
			while (true) {
				var last = readByte();
				if (last == 10) break;
				buf.addByte(last);
			}
		} catch (e:Eof) {
			var bytes = buf.getBytes();
			if (bytes.length == 0)
				#if neko neko.Lib.rethrow #else throw #end (e);
			// fallthrough: return partial line
			return bytes.toString();
		}

		var bytes = buf.getBytes();
		// If the line ended with a CR (Windows line ending), drop it.
		var bytesLen = bytes.length;
		if (bytesLen > 0) {
			var lastByte = bytes.get(bytesLen - 1);
			if (lastByte == 13) {
				var trimmed = bytes.sub(0, bytesLen - 1);
				bytes = trimmed;
			}
		}
		return bytes.toString();
	}

	/**
		Read a 32-bit floating point number.

		Endianness is specified by the `bigEndian` property.
	**/
	public function readFloat():Float {
		return FPHelper.i32ToFloat(readInt32());
	}

	/**
		Read a 64-bit double-precision floating point number.

		Endianness is specified by the `bigEndian` property.
	**/
	public function readDouble():Float {
		var i1 = readInt32();
		var i2 = readInt32();
		return bigEndian ? FPHelper.i64ToDouble(i2, i1) : FPHelper.i64ToDouble(i1, i2);
	}

	/**
		Read a 8-bit signed integer.
	**/
	public function readInt8():Int {
		var n = readByte();
		if (n >= 128)
			return n - 256;
		return n;
	}

	/**
		Read a 16-bit signed integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function readInt16():Int {
		var ch1 = readByte();
		var ch2 = readByte();
		var n = bigEndian ? (ch1 << 8) | ch2 : ch1 | (ch2 << 8);
		if (n >= 32768)
			return n - 65536;
		return n;
	}

	/**
		Read a 16-bit unsigned integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function readUInt16():Int {
		var ch1 = readByte();
		var ch2 = readByte();
		return bigEndian ? (ch1 << 8) | ch2 : ch1 | (ch2 << 8);
	}

	/**
		Read a 24-bit signed integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function readInt24():Int {
		var ch1 = readByte();
		var ch2 = readByte();
		var ch3 = readByte();
		var n = bigEndian ? (ch1 << 16) | (ch2 << 8) | ch3 : ch1 | (ch2 << 8) | (ch3 << 16);
		if (n >= 8388608)
			return n - 16777216;
		return n;
	}

	/**
		Read a 24-bit unsigned integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function readUInt24():Int {
		var ch1 = readByte();
		var ch2 = readByte();
		var ch3 = readByte();
		return bigEndian ? (ch1 << 16) | (ch2 << 8) | ch3 : ch1 | (ch2 << 8) | (ch3 << 16);
	}

	/**
		Read a 32-bit signed integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function readInt32():Int {
		var ch1 = readByte();
		var ch2 = readByte();
		var ch3 = readByte();
		var ch4 = readByte();
		#if (php || python)
		// php will overflow integers.  Convert them back to signed 32-bit ints.
		var n = bigEndian ? ch4 | (ch3 << 8) | (ch2 << 16) | (ch1 << 24) : ch1 | (ch2 << 8) | (ch3 << 16) | (ch4 << 24);
		if (n & 0x80000000 != 0)
			return (n | 0x80000000);
		else
			return n;
		#elseif lua
		var n = bigEndian ? ch4 | (ch3 << 8) | (ch2 << 16) | (ch1 << 24) : ch1 | (ch2 << 8) | (ch3 << 16) | (ch4 << 24);
		return lua.Boot.clampInt32(n);
		#else
		return bigEndian ? ch4 | (ch3 << 8) | (ch2 << 16) | (ch1 << 24) : ch1 | (ch2 << 8) | (ch3 << 16) | (ch4 << 24);
		#end
	}

	/**
		Read and `len` bytes as a string.
	**/
	public function readString(len:Int, ?encoding:Encoding):String {
		var b = Bytes.alloc(len);
		readFullBytes(b, 0, len);
		#if neko
		return neko.Lib.stringReference(b);
		#else
		return b.getString(0, len, encoding);
		#end
	}

	#if neko
	static var _float_of_bytes = neko.Lib.load("std", "float_of_bytes", 2);
	static var _double_of_bytes = neko.Lib.load("std", "double_of_bytes", 2);

	static function __init__()
		untyped {
			Input.prototype.bigEndian = false;
		}
	#end

	#if (flash || js || python)
	function getDoubleSig(bytes:Array<Int>) {
		return (((bytes[1] & 0xF) << 16) | (bytes[2] << 8) | bytes[3]) * 4294967296.
			+ (bytes[4] >> 7) * 2147483648
			+ (((bytes[4] & 0x7F) << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7]);
	}
	#end
}
