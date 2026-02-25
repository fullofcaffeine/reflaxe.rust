package rust;

/**
 * `rust.InstantTools`
 *
 * Why
 * - `Instant` helpers are common in Rust-first timing code.
 * - Inline `untyped __rust__` helper bodies forced these calls through `ERaw` fallback.
 *
 * What
 * - A typed extern boundary backed by `std/rust/native/instant_tools.rs`.
 *
 * How
 * - `@:native("crate::instant_tools::InstantTools")` targets a crate-local Rust helper module.
 * - Typed signatures preserve borrow semantics (`Ref<Instant>`) without app-side raw injection.
 */
@:native("crate::instant_tools::InstantTools")
@:rustExtraSrc("rust/native/instant_tools.rs")
extern class InstantTools {
	public static function now():Instant;
	public static function elapsed(i:Ref<Instant>):Duration;
	public static function elapsedMillis(i:Ref<Instant>):Float;
}
