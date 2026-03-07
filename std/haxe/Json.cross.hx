package haxe;

import haxe.BoundaryTypes.JsonReplacer;
import haxe.BoundaryTypes.JsonValue;
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
	- `parse(text:String):JsonValue`
	- `parseValue(text:String):haxe.json.Value`
	- `stringify(value:JsonValue, ?replacer, ?space):String`

	How
	- Implemented by calling into the bundled Rust runtime (`hxrt`) via typed extern bindings
	  in `hxrt.json.NativeJson`.
	- `parse` returns:
	  - JSON objects as runtime `DynObject` boxed into `JsonValue` (works with `Reflect.field`)
	  - JSON arrays as `Array<JsonValue>` boxed into `JsonValue`
	- `stringify` supports `space` for pretty printing (indent string per nesting level).
	- `stringify` applies `replacer` with upstream Haxe semantics:
	  - called first with the root key `""`
	  - object fields use their field name as the key
	  - array items use their string index (`"0"`, `"1"`, ...)
	  - the callback runs before descending into child values
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
		Parses a JSON string into a Haxe `JsonValue` boundary payload.
	**/
	public static function parse(text:String):JsonValue {
		#if macro
		return haxe.format.JsonParser.parse(text);
		#else
		return NativeJson.parse(text);
		#end
	}

	/**
		Parses a JSON string into a typed `haxe.json.Value`.

		This keeps the stdlib-compatible `JsonValue` parse boundary at one point while allowing
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
		Encodes a Haxe `JsonValue` boundary payload as JSON.

		Notes
		- `space` enables pretty-printing (indent string per nesting level).
		- `replacer` matches upstream Haxe `JsonPrinter` traversal order:
		  root key `""`, then object-field / array-index keys before descending further.
	**/
	public static function stringify(value:JsonValue, ?replacer:JsonReplacer, ?space:String):String {
		#if macro
		return haxe.format.JsonPrinter.print(value, replacer, space);
		#else
		if (replacer != null) {
			return NativeJson.stringifyWithReplacer(value, replacer, space);
		}
		return NativeJson.stringify(value, space);
		#end
	}

	#if !macro
	/**
		Converts the runtime JSON `JsonValue` shape into typed `haxe.json.Value`.

		Why
		- `haxe.Json.parse` must stay boundary-typed (`JsonValue`) for stdlib compatibility.
		- The rest of compiler/runtime/example code should avoid carrying untyped values.

		How
		- Reads a stable runtime kind tag from `hxrt::json`.
		- Uses typed accessors per kind and recurses for arrays/objects.
		- No stringify/reflect heuristics are used in this path.
	**/
	static function dynamicToValue(value:JsonValue):Value {
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
	static function macroDynamicToValue(value:JsonValue):Value {
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
			var input:Array<JsonValue> = cast value;
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
