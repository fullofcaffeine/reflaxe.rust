package haxe;

import haxe.json.Value;
import hxrt.json.NativeJson;

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
	- `parseValue(text:String):haxe.json.Value`
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
	static inline var KIND_NULL:Int = 0;
	static inline var KIND_BOOL:Int = 1;
	static inline var KIND_INT:Int = 2;
	static inline var KIND_FLOAT:Int = 3;
	static inline var KIND_STRING:Int = 4;
	static inline var KIND_ARRAY:Int = 5;
	static inline var KIND_OBJECT:Int = 6;

	/**
		Parses a JSON string into a Haxe `Dynamic` value.
	**/
	public static function parse(text:String):Dynamic {
		#if macro
		return haxe.format.JsonParser.parse(text);
		#else
		return NativeJson.parse(text);
		#end
	}

	/**
		Parses a JSON string into a typed `haxe.json.Value`.

		This keeps the stdlib-compatible `Dynamic` parse boundary at one point while allowing
		callers to switch to exhaustive typed matching immediately afterwards.
	**/
	public static function parseValue(text:String):Value {
		#if macro
		return macroDynamicToValue(parse(text));
		#else
		return dynamicToValue(parse(text));
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
		return (untyped __rust__("hxrt::json::stringify(&{0}, {1}.as_deref())", value, space) : String);
		#end
	}

	#if !macro
	/**
		Converts the runtime JSON `Dynamic` shape into typed `haxe.json.Value`.

		Why
		- `haxe.Json.parse` must stay `Dynamic` for stdlib compatibility.
		- The rest of compiler/runtime/example code should avoid carrying `Dynamic`.

		How
		- Reads a stable runtime kind tag from `hxrt::json`.
		- Uses typed accessors per kind and recurses for arrays/objects.
		- No stringify/reflect heuristics are used in this path.
	**/
	static function dynamicToValue(value:Dynamic):Value {
		switch (NativeJson.valueKind(value)) {
			case KIND_NULL:
				return JNull;
			case KIND_BOOL:
				return JBool(NativeJson.valueAsBool(value));
			case KIND_INT:
				return JNumber(NativeJson.valueAsInt(value));
			case KIND_FLOAT:
				return JNumber(NativeJson.valueAsFloat(value));
			case KIND_STRING:
				return JString(NativeJson.valueAsString(value));
			case KIND_ARRAY:
				var len:Int = NativeJson.valueArrayLength(value);
				var out:Array<Value> = [];
				var i:Int = 0;
				while (i < len) {
					out.push(dynamicToValue(NativeJson.valueArrayGet(value, i)));
					i = i + 1;
				}
				return JArray(out);
			case KIND_OBJECT:
				var keys:Array<String> = NativeJson.valueObjectKeys(value);
				var values:Array<Value> = [];
				for (name in keys) {
					values.push(dynamicToValue(NativeJson.valueObjectField(value, name)));
				}
				return JObject(keys, values);
			case _:
				throw "haxe.Json.parseValue: unsupported parsed value kind";
		}
	}
	#end

	#if macro
	static function macroDynamicToValue(value:Dynamic):Value {
		if (value == null)
			return JNull;
		if (Std.isOfType(value, Bool))
			return JBool(cast value);
		if (Std.isOfType(value, Int))
			return JNumber(cast value);
		if (Std.isOfType(value, Float))
			return JNumber(cast value);
		if (Std.isOfType(value, String))
			return JString(cast value);

		if (Std.isOfType(value, Array)) {
			var input:Array<Dynamic> = cast value;
			var out:Array<Value> = [];
			for (entry in input) {
				out.push(macroDynamicToValue(entry));
			}
			return JArray(out);
		}

		var keys:Array<String> = Reflect.fields(value);
		if (keys != null) {
			var values:Array<Value> = [];
			for (name in keys) {
				values.push(macroDynamicToValue(Reflect.field(value, name)));
			}
			return JObject(keys, values);
		}

		throw "haxe.Json.parseValue: unsupported macro JSON value";
	}
	#end
}
