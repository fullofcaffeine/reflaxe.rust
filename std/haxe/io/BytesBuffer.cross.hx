package haxe.io;

/**
 * `haxe.io.BytesBuffer` (Rust target override)
 *
 * Why:
 * - The stock Haxe std implementation of `BytesBuffer` relies on target-specific internal byte
 *   representations (e.g. `BytesData`) and inlining tricks.
 * - On the Rust target we want `BytesBuffer` to be implemented purely in terms of the runtime-backed
 *   `haxe.io.Bytes` representation so it behaves predictably and stays portable at the Haxe level.
 *
 * What:
 * - A growable buffer of bytes that can be appended to (bytes, bytes ranges, strings, numbers) and
 *   then finalized into a single `Bytes` instance via `getBytes()`.
 *
 * How (implementation strategy):
 * - We keep an internal list of `Bytes` chunks plus a running `length`.
 * - Appends add new chunks (cheap) instead of reallocating a growing contiguous buffer on every call.
 * - `getBytes()` allocates a single output `Bytes` and `blit`s each chunk into it.
 *
 * Notes:
 * - `getBytes()` follows std semantics: it finalizes the buffer; after calling it, the buffer should
 *   no longer be used. We enforce this by throwing `Error.Custom(...)` if methods are called after
 *   finalization.
 */
class BytesBuffer {
	var chunks:Array<Bytes>;
	var finalized:Bool;
	var _length:Int;

	/**
		The length of the buffer in bytes.

		This is stored explicitly (instead of computed from chunk sizes on demand) so `length` remains
		O(1) and can still be queried after `getBytes()` (even though the buffer becomes finalized and
		should no longer be mutated).
	**/
	public var length(get, never):Int;

	public function new() {
		this.chunks = [];
		this.finalized = false;
		this._length = 0;
	}

	inline function ensureOpen():Void {
		if (finalized)
			throw Error.Custom("BytesBuffer is finalized");
	}

	private function get_length():Int {
		return _length;
	}

	public function addByte(byte:Int):Void {
		ensureOpen();
		var b = Bytes.alloc(1);
		b.set(0, byte);
		chunks.push(b);
		_length = _length + 1;
	}

	public function add(src:Bytes):Void {
		ensureOpen();
		chunks.push(src);
		_length = _length + src.length;
	}

	public function addString(v:String, ?encoding:Encoding):Void {
		ensureOpen();
		// Keep semantics aligned with other targets: default to UTF-8 and allow passing `encoding`.
		// The Rust target currently treats both encodings as UTF-8 at codegen/runtime level.
		add(Bytes.ofString(v, encoding));
	}

	public function addInt32(v:Int):Void {
		addByte(v & 0xFF);
		addByte((v >> 8) & 0xFF);
		addByte((v >> 16) & 0xFF);
		addByte(v >>> 24);
	}

	public function addInt64(v:haxe.Int64):Void {
		addInt32(v.low);
		addInt32(v.high);
	}

	public function addFloat(v:Float):Void {
		addInt32(FPHelper.floatToI32(v));
	}

	public function addDouble(v:Float):Void {
		addInt64(FPHelper.doubleToI64(v));
	}

	public function addBytes(src:Bytes, pos:Int, len:Int):Void {
		ensureOpen();
		// Use Bytes.sub for bounds checking + slicing, then append.
		add(src.sub(pos, len));
	}

	/**
	 * Returns either a copy or a reference of the current bytes.
	 * Once called, the buffer should no longer be used.
	 */
	public function getBytes():Bytes {
		ensureOpen();
		var out = Bytes.alloc(_length);

		var offset = 0;
		for (chunk in chunks) {
			var n = chunk.length;
			out.blit(offset, chunk, 0, n);
			offset = offset + n;
		}

		finalized = true;
		chunks = [];
		return out;
	}
}
