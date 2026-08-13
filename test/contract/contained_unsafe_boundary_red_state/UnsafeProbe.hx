/**
 * Typed probe for the current copied-helper safety boundary.
 *
 * The Rust helper intentionally contains one small `unsafe` operation. Current
 * `@:rustExtraSrc` places that helper in the generated application crate, so a
 * build with `rust_forbid_unsafe` must reject it.
 */
@:native("crate::unsafe_probe::UnsafeProbe")
@:rustExtraSrc("native/unsafe_probe.rs")
extern class UnsafeProbe {
	@:native("read_known_value")
	public static function readKnownValue():Int;
}
