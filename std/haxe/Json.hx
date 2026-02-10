package haxe;

/**
	`haxe.Json` (Rust target override)

	Why
	- The upstream Haxe implementation routes through `haxe.format.JsonParser` / `haxe.format.JsonPrinter`,
	  which rely on a fairly wide slice of reflection (`Type.typeof`, `ValueType`, etc.).
	- For the Rust target we want a **fast, sys-style** implementation that:
	  1) matches the public Haxe API, and
	  2) leverages Rust's mature JSON ecosystem.

	What
	- `parse(text:String):Dynamic`
	- `stringify(value:Dynamic, ?replacer, ?space):String`

	How
	- Implemented by calling into the bundled Rust runtime (`hxrt`) via target-code injection.
	- `parse` returns:
	  - JSON objects as runtime `DynObject` boxed into `Dynamic` (works with `Reflect.field`)
	  - JSON arrays as `Array<Dynamic>` boxed into `Dynamic`
	- `stringify` supports `space` for pretty printing (indent string per nesting level).
	  `replacer` is accepted for API compatibility but is not implemented yet on this target.
**/
class Json {
	/**
		Parses a JSON string into a Haxe `Dynamic` value.
	**/
	public static function parse(text:String):Dynamic {
		#if macro
		return haxe.format.JsonParser.parse(text);
		#else
		return untyped __rust__("hxrt::json::parse({0}.as_str())", text);
		#end
	}

	/**
		Encodes a Haxe `Dynamic` value as JSON.

		Notes
		- `space` enables pretty-printing (indent string per nesting level).
		- `replacer` is not supported yet on the Rust target.
	**/
	public static function stringify(value:Dynamic, ?replacer:(key:Dynamic, value:Dynamic) -> Dynamic, ?space:String):String {
		#if macro
		return haxe.format.JsonPrinter.print(value, replacer, space);
		#else
		if (replacer != null) {
			throw "haxe.Json.stringify: replacer is not supported on the Rust target yet";
		}
		return untyped __rust__("hxrt::json::stringify(&{0}, {1}.as_deref())", value, space);
		#end
	}
}
