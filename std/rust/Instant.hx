package rust;

/**
 * rust.Instant
 *
 * Rust-facing monotonic clock instant (`std::time::Instant`) intended for the `rusty` profile.
 */
@:native("std::time::Instant")
extern class Instant {
	public function clone(): Instant;
}

