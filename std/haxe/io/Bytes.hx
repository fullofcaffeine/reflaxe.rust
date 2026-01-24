package haxe.io;

/**
 * Rust target override: haxe.io.Bytes is runtime-backed by `hxrt::bytes::Bytes`.
 *
 * IMPORTANT:
 * - This is `extern` on purpose so the stock std implementation does not inline into
 *   field/index operations that don't exist on the runtime-backed representation.
 * - The compiler special-cases `alloc`, `ofString`, `get`, `set`, `toString`, and `length`.
 */
extern class Bytes {
	public var length(default, null):Int;

	// Internal constructor used by some std classes (e.g. BytesBuffer).
	function new(length:Int, b:BytesData);

	public function getData():BytesData;

	public static function alloc(length:Int):Bytes;
	public static function ofString(s:String, ?encoding:Encoding):Bytes;

	public function get(pos:Int):Int;
	public function set(pos:Int, v:Int):Void;
	public function blit(pos:Int, src:Bytes, srcpos:Int, len:Int):Void;
	public function sub(pos:Int, len:Int):Bytes;
	public function getString(pos:Int, len:Int, ?encoding:Encoding):String;
	public function toString():String;
}
