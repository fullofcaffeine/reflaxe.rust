package hxrt.string;

/**
	Typed bindings for `hxrt::string` helper functions.

	Why
	- `StringTools.cross.hx` needs a few runtime-specialized helpers (`hex`, `fastCodeAt`) that are
	  easier to implement in Rust than in pure Haxe while preserving exact behavior.
	- Exposing these as typed extern calls keeps std overrides beginner-friendly and avoids raw
	  `untyped __rust__` snippets in framework code.

	How
	- `@:native("hxrt::string")` maps this extern to the runtime module.
	- Each method maps to a concrete Rust function with explicit Haxe argument/return types.
**/
@:native("hxrt::string")
extern class NativeString {
	/**
		`StringTools.fastCodeAt` runtime helper.

		Returns `-1` when `index` is out of bounds.
	**/
	@:native("fast_code_at_or_eof")
	public static function fastCodeAtOrEof(s:String, index:Int):Int;

	/**
		`StringTools.hex` runtime helper.

		Formats `n` as uppercase hex and left-pads with zeros when `digits` is set.
	**/
	@:native("hex_upper")
	public static function hexUpper(n:Int, ?digits:Int):String;
}
