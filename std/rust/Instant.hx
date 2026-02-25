package rust;

/**
 * rust.Instant
 *
 * Rust-facing monotonic clock instant (`std::time::Instant`) intended for the `metal` profile.
 *
 * Prefer using `InstantTools` for typed helper operations at the boundary.
 */
@:native("std::time::Instant")
extern class Instant {
	public function clone():Instant;
}
