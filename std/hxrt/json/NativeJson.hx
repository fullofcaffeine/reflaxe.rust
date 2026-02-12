package hxrt.json;

import rust.Ref;

/**
	`hxrt.json.NativeJson` (Rust runtime binding)

	Why
	- `haxe.Json.parse` is part of the cross-target std API and must return `Dynamic`.
	- Calling Rust JSON helpers through raw `untyped __rust__` can leave open monomorphs in the
	  typed AST, which then surfaces as backend warnings in unrelated builds.

	What
	- Typed extern binding for `hxrt::json::parse`.

	How
	- `@:native("hxrt::json")` binds this extern class to the Rust runtime module.
	- `@:native("parse")` binds the static function to `hxrt::json::parse`.
	- The `Ref<String>` parameter models Rust `&str`/`&String` callsites without exposing
	  any `__rust__` escape hatch to app code.
**/
@:native("hxrt::json")
extern class NativeJson {
	@:native("parse")
	public static function parse(text: Ref<String>): Dynamic;
}
