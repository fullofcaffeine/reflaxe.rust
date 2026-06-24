package rust;

/**
 * rust.SystemTime
 *
 * Why
 * - Rust-first Haxe code sometimes needs wall-clock time, not monotonic elapsed time.
 * - Haxe `Date` intentionally preserves Haxe stdlib semantics and may use hxrt support.
 *
 * What
 * - A typed Haxe facade for Rust's `std::time::SystemTime`.
 *
 * How
 * - Static members map directly to Rust stdlib associated items.
 * - `durationSince` maps to Rust's `duration_since`.
 * - Use `SystemTimeTools` only for small Haxe-side convenience helpers.
 * - Prefer `Instant`/`InstantTools` for elapsed-time measurement; use `SystemTime` only
 *   when the value represents civil/wall-clock time or a Unix timestamp boundary.
 */
@:native("std::time::SystemTime")
extern class SystemTime {
	@:native("UNIX_EPOCH")
	public static var UNIX_EPOCH(default, never):SystemTime;
	public static function now():SystemTime;
	public function clone():SystemTime;
	@:native("duration_since")
	public function durationSince(earlier:SystemTime):Result<Duration, SystemTimeError>;
}
