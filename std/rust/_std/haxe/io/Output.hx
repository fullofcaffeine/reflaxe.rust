package haxe.io;

/**
	`haxe.io.Output` (Rust target override)

	Why
	- The upstream Haxe std `Output.writeBytes` reads from `Bytes` using `Bytes.getData()` or other
	  target-specific internals.
	- On reflaxe.rust, `haxe.io.Bytes` is an `extern` wrapper over a Rust-owned buffer
	  (`HxRef<hxrt::bytes::Bytes>`), so internal data access is intentionally unavailable.

	What
	- An abstract writer API used throughout the stdlib.
	- Concrete outputs are expected to override `writeByte()` and optionally `writeBytes()`.

	How
	- The only behavioral difference vs upstream is the implementation of `writeBytes`:
	  it uses `Bytes.get(...)` instead of `getData()`.
	- Everything else is kept very close to upstream so macro-time std code and portable libraries
	  continue to typecheck.
**/
class Output {
	/**
		Endianness (word byte order) used when writing numbers.

		If `true`, big-endian is used, otherwise `little-endian` is used.
	**/
	public var bigEndian(default, set):Bool;

	#if java
	private var helper:java.nio.ByteBuffer;
	#end

	/**
		Write one byte.
	**/
	public function writeByte(_c:Int):Void {
		throw Error.Custom("Output.writeByte is not implemented");
	}

	/**
		Write `len` bytes from `s` starting by position specified by `pos`.

		Returns the actual length of written data that can differ from `len`.

		See `writeFullBytes` that tries to write the exact amount of specified bytes.
	**/
	public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		#if !neko
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw Error.OutsideBounds;
		#end
		var p = pos;
		var k = len;
		while (k > 0) {
			writeByte(s.get(p));
			p++;
			k--;
		}
		return len;
	}

	/**
		Flush any buffered data.
	**/
	public function flush() {}

	/**
		Close the output.

		Behaviour while writing after calling this method is unspecified.
	**/
	public function close() {}

	function set_bigEndian(b) {
		bigEndian = b;
		return b;
	}

	/* ------------------ API ------------------ */
	/**
		Write all bytes stored in `s`.
	**/
	public function write(s:Bytes):Void {
		var l = s.length;
		var p = 0;
		while (l > 0) {
			var k = writeBytes(s, p, l);
			if (k == 0)
				throw Error.Blocked;
			p += k;
			l -= k;
		}
	}

	/**
		Write `len` bytes from `s` starting by position specified by `pos`.

		Unlike `writeBytes`, this method tries to write the exact amount of specified bytes.
	**/
	public function writeFullBytes(s:Bytes, pos:Int, len:Int) {
		var p = pos;
		var l = len;
		while (l > 0) {
			var k = writeBytes(s, p, l);
			p += k;
			l -= k;
		}
	}

	/**
		Write `x` as 32-bit floating point number.

		Endianness is specified by the `bigEndian` property.
	**/
	public function writeFloat(x:Float) {
		writeInt32(FPHelper.floatToI32(x));
	}

	/**
		Write `x` as 64-bit double-precision floating point number.

		Endianness is specified by the `bigEndian` property.
	**/
	public function writeDouble(x:Float) {
		var i64 = FPHelper.doubleToI64(x);
		if (bigEndian) {
			writeInt32(i64.high);
			writeInt32(i64.low);
		} else {
			writeInt32(i64.low);
			writeInt32(i64.high);
		}
	}

	/**
		Write `x` as 8-bit signed integer.
	**/
	public function writeInt8(x:Int) {
		if (x < -0x80 || x >= 0x80)
			throw Error.Overflow;
		writeByte(x & 0xFF);
	}

	/**
		Write `x` as 16-bit signed integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function writeInt16(x:Int) {
		if (x < -0x8000 || x >= 0x8000)
			throw Error.Overflow;
		writeUInt16(x & 0xFFFF);
	}

	/**
		Write `x` as 16-bit unsigned integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function writeUInt16(x:Int) {
		if (x < 0 || x >= 0x10000)
			throw Error.Overflow;
		if (bigEndian) {
			writeByte(x >> 8);
			writeByte(x & 0xFF);
		} else {
			writeByte(x & 0xFF);
			writeByte(x >> 8);
		}
	}

	/**
		Write `x` as 24-bit signed integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function writeInt24(x:Int) {
		if (x < -0x800000 || x >= 0x800000)
			throw Error.Overflow;
		writeUInt24(x & 0xFFFFFF);
	}

	/**
		Write `x` as 24-bit unsigned integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function writeUInt24(x:Int) {
		if (x < 0 || x >= 0x1000000)
			throw Error.Overflow;
		if (bigEndian) {
			writeByte(x >> 16);
			writeByte((x >> 8) & 0xFF);
			writeByte(x & 0xFF);
		} else {
			writeByte(x & 0xFF);
			writeByte((x >> 8) & 0xFF);
			writeByte(x >> 16);
		}
	}

	/**
		Write `x` as 32-bit signed integer.

		Endianness is specified by the `bigEndian` property.
	**/
	public function writeInt32(x:Int) {
		if (bigEndian) {
			writeByte(x >>> 24);
			writeByte((x >> 16) & 0xFF);
			writeByte((x >> 8) & 0xFF);
			writeByte(x & 0xFF);
		} else {
			writeByte(x & 0xFF);
			writeByte((x >> 8) & 0xFF);
			writeByte((x >> 16) & 0xFF);
			writeByte(x >>> 24);
		}
	}

	/**
		Inform that we are about to write at least `nbytes` bytes.

		The underlying implementation can allocate proper working space depending
		on this information, or simply ignore it. This is not a mandatory call
		but a tip and is only used in some specific cases.
	**/
	public function prepare(_nbytes:Int) {}

	/**
		Read all available data from `i` and write it.

		The `bufsize` optional argument specifies the size of chunks by
		which data is read and written. Its default value is 4096.
	**/
	public function writeInput(i:Input, ?bufsize:Int) {
		var bs:Null<Int> = bufsize;
		if (bs == null)
			bs = 4096;
		var bufsize:Int = bs;
		var buf = Bytes.alloc(bufsize);
		try {
			while (true) {
				var len = i.readBytes(buf, 0, bufsize);
				if (len == 0)
					throw Error.Blocked;
				var p = 0;
				while (len > 0) {
					var k = writeBytes(buf, p, len);
					if (k == 0)
						throw Error.Blocked;
					p += k;
					len -= k;
				}
			}
		} catch (e:Eof) {}
	}

	/**
		Write `s` string.
	**/
	public function writeString(s:String, ?encoding:Encoding) {
		#if neko
		var b = untyped new Bytes(s.length, s.__s);
		#else
		var b = Bytes.ofString(s, encoding);
		#end
		writeFullBytes(b, 0, b.length);
	}

	#if neko
	static function __init__() untyped {
		Output.prototype.bigEndian = false;
	}
	#end
}
