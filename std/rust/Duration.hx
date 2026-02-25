package rust;

/**
 * rust.Duration
 *
 * Rust-facing duration (`std::time::Duration`) intended for the `metal` profile.
 *
 * Prefer using `DurationTools` for construction and conversions (to avoid int cast issues).
 * `DurationTools` crosses into Rust through a typed extern boundary
 * (`std/rust/native/duration_tools.rs`).
 */
@:native("std::time::Duration")
extern class Duration {
	public function clone():Duration;
}
