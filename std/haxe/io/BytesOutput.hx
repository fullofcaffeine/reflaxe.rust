package haxe.io;

/**
	`haxe.io.BytesOutput` (Rust target override)

	Why
	- `BytesOutput` is used throughout the stdlib to build `Bytes` incrementally.
	- On this target, `Bytes` is an `extern` wrapper over a Rust-owned buffer, so we need an
	  implementation that uses the public `BytesBuffer` API rather than target-private storage.

	What
	- An `Output` implementation backed by a `BytesBuffer`.
	- Exposes `length` and `getBytes()` like the upstream stdlib.

	How
	- Writes go into `BytesBuffer` via `addByte` / `addBytes`.
	- `getBytes()` consumes the internal buffer by returning `BytesBuffer.getBytes()`.
**/
class BytesOutput extends Output {
	var b:BytesBuffer;

	/** The length of the stream in bytes. **/
	public var length(get, never):Int;

	public function new() {
		b = new BytesBuffer();
	}

	inline function get_length():Int {
		return b.length;
	}

	override function writeByte(c:Int) {
		b.addByte(c);
	}

	override function writeBytes(buf:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > buf.length)
			throw Error.OutsideBounds;
		b.addBytes(buf, pos, len);
		return len;
	}

	@:dox(hide)
	override function prepare(_size:Int) {
		// Best-effort: `BytesBuffer` grows dynamically on this target; no explicit preallocation.
	}

	/**
		Returns the `Bytes` of this output.

		This function should not be called more than once on a given `BytesOutput` instance.
	**/
	public function getBytes():Bytes {
		return b.getBytes();
	}
}
