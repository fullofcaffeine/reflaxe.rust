package rust;

/**
 * rust.SystemTimeError
 *
 * Extern binding to Rust's `std::time::SystemTimeError`, returned by
 * `SystemTime.durationSince(...)` when the receiver is earlier than the supplied base time.
 */
@:native("std::time::SystemTimeError")
extern class SystemTimeError {
	public function clone():SystemTimeError;
}
