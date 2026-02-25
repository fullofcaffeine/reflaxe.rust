package rust;

/**
 * `rust.DurationTools`
 *
 * Why
 * - Duration construction/conversion helpers are used in Rust-first snapshots and examples.
 * - The previous implementation used inline `untyped __rust__`, which showed up as `ERaw`
 *   fallback in metal diagnostics.
 *
 * What
 * - A typed extern facade backed by `std/rust/native/duration_tools.rs`.
 * - Existing public API is preserved (`fromMillis`, `fromSecs`, `asMillis`, `sleep`).
 *
 * How
 * - `@:native("crate::duration_tools::DurationTools")` binds this class to a hand-written
 *   Rust helper module included with `@:rustExtraSrc`.
 * - Callers stay fully typed across the boundary with no `Dynamic` or `Reflect` fallback.
 */
@:native("crate::duration_tools::DurationTools")
@:rustExtraSrc("rust/native/duration_tools.rs")
extern class DurationTools {
	public static function fromMillis(ms:Int):Duration;
	public static function fromSecs(secs:Int):Duration;
	public static function asMillis(d:Duration):Float;
	public static function sleep(d:Duration):Void;
}
