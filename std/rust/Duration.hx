package rust;

/**
 * rust.Duration
 *
 * Rust-facing duration (`std::time::Duration`) intended for the `rusty` profile.
 *
 * Prefer using `DurationTools` for construction and conversions (to avoid int cast issues).
 */
@:native("std::time::Duration")
extern class Duration {
	public function clone(): Duration;
}

