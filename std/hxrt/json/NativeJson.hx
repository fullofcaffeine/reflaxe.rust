package hxrt.json;

import haxe.BoundaryTypes.JsonReplacer;
import haxe.BoundaryTypes.JsonValue;
import rust.Ref;

/**
	`hxrt.json.NativeJson` (Rust runtime binding)

	Why
	- `haxe.Json.parse` is part of the cross-target std API and must return a boundary
	  JSON payload (`JsonValue`).
	- Calling Rust JSON helpers through raw `untyped __rust__` can leave open monomorphs in the
	  typed AST, which then surfaces as backend warnings in unrelated builds.

	What
	- Typed extern bindings for `hxrt::json` parse helpers and runtime JSON value introspection
	  used by `haxe.Json.parseValue`.
	- Typed stringify bindings, including the `Json.stringify` replacer callback path.

	How
	- `@:native("hxrt::json")` binds this extern class to the Rust runtime module.
	- `@:native("parse")` binds the static function to `hxrt::json::parse`.
	- The `Ref<String>` parameter models Rust `&str`/`&String` callsites without exposing
	  any `__rust__` escape hatch to app code.
**/
@:native("hxrt::json")
extern class NativeJson {
	@:native("parse")
	public static function parse(text:Ref<String>):JsonValue;

	@:native("stringify")
	public static function stringify(value:JsonValue):String;

	/**
		Pretty-print JSON using an explicit indent string.

		Why
		- Borrowed nullable strings (`Ref<Null<String>>`) force awkward codegen in metal because
		  `null` and borrowed string shapes diverge across profiles.
		- The runtime has two concrete modes: no pretty-printing, or pretty-printing with a real
		  indent string. Modeling those as distinct entry points keeps the boundary typed and
		  avoids backend-specific unwrap glue.

		How
		- `String` remains profile-dependent on the Haxe side.
		- `Ref<String>` lowers to the correct borrowed Rust string representation for the active profile.
	**/
	@:native("stringify_pretty")
	public static function stringifyPretty(value:JsonValue, space:Ref<String>):String;

	@:native("stringify_with_replacer")
	public static function stringifyWithReplacer(value:JsonValue, replacer:JsonReplacer):String;

	@:native("stringify_with_replacer_pretty")
	public static function stringifyWithReplacerPretty(value:JsonValue, replacer:JsonReplacer, space:Ref<String>):String;

	/**
		Read-only JSON value introspection used by `haxe.Json.parseValue`.

		Why
		- `JsonValue` is the std-compatible dynamic boundary for parsed JSON payloads.
		- `parseValue` walks that payload recursively, and each kind/accessor call only needs to
		  inspect the current value. Passing it by value made generated Rust clone the same
		  `Dynamic` repeatedly before extracting child values.

		What
		- These bindings model the inspected value as `rust.Ref<JsonValue>`, which lowers to
		  `&Dynamic` in generated Rust.
		- Child-extraction helpers still return owned `JsonValue` where the typed
		  `haxe.json.Value` tree needs ownership for recursion.

		How
		- Callers keep ordinary `JsonValue` source code; `rust.Ref` has an `@:from` conversion so
		  Haxe type checking accepts the value while the backend prints a borrow at the extern
		  callsite.
		- The runtime counterpart accepts `&Dynamic` for these read-only helpers.
	**/
	@:native("value_kind")
	public static function valueKind(value:Ref<JsonValue>):Int;

	@:native("value_as_bool")
	public static function valueAsBool(value:Ref<JsonValue>):Bool;

	@:native("value_as_int")
	public static function valueAsInt(value:Ref<JsonValue>):Int;

	@:native("value_as_float")
	public static function valueAsFloat(value:Ref<JsonValue>):Float;

	@:native("value_as_string")
	public static function valueAsString(value:Ref<JsonValue>):String;

	@:native("value_array_length")
	public static function valueArrayLength(value:Ref<JsonValue>):Int;

	@:native("value_array_get")
	public static function valueArrayGet(value:Ref<JsonValue>, index:Int):JsonValue;

	@:native("value_object_keys")
	public static function valueObjectKeys(value:Ref<JsonValue>):Array<String>;

	@:native("value_object_field")
	public static function valueObjectField(value:Ref<JsonValue>, key:String):JsonValue;
}
