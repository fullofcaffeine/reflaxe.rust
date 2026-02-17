package hxrt.json;

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

	@:native("value_kind")
	public static function valueKind(value:JsonValue):Int;

	@:native("value_as_bool")
	public static function valueAsBool(value:JsonValue):Bool;

	@:native("value_as_int")
	public static function valueAsInt(value:JsonValue):Int;

	@:native("value_as_float")
	public static function valueAsFloat(value:JsonValue):Float;

	@:native("value_as_string")
	public static function valueAsString(value:JsonValue):String;

	@:native("value_array_length")
	public static function valueArrayLength(value:JsonValue):Int;

	@:native("value_array_get")
	public static function valueArrayGet(value:JsonValue, index:Int):JsonValue;

	@:native("value_object_keys")
	public static function valueObjectKeys(value:JsonValue):Array<String>;

	@:native("value_object_field")
	public static function valueObjectField(value:JsonValue, key:String):JsonValue;
}
