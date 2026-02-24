package rust.async;

/**
	rust.async.TokioRuntime

	Why
	- The default async bridge intentionally stays lightweight (`pollster` + `futures-timer`).
	- Some Rust-first applications need a tokio-backed adapter for richer runtime behavior.

	What
	- Typed runtime-adapter toggles:
	  - `enable()` / `disable()`
	  - `isEnabled()`

	How
	- Maps to `hxrt::async_::*`.
	- Declares tokio dependency metadata via `@:rustCargo(...)` so generated Cargo manifests include
	  tokio when this adapter surface is used.
	- `hxrt` tokio behavior is feature-gated (`async_tokio`) and inferred from typed module usage.

	Boundary note
	- Keep adapter control in typed code. Do not use raw target injection for runtime switching.
**/
@:rustCargo({name: "tokio", version: "1", features: ["rt", "time"]})
@:native("hxrt::async_")
extern class TokioRuntime {
	@:native("enable_tokio_runtime")
	public static function enable():Void;

	@:native("disable_tokio_runtime")
	public static function disable():Void;

	@:native("is_tokio_runtime_enabled")
	public static function isEnabled():Bool;
}
