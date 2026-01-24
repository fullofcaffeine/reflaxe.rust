package rust;

/**
 * rust.OsString
 *
 * Rust-facing owned OS string (`std::ffi::OsString`) intended for the `rusty` profile.
 *
 * Notes:
 * - Prefer `OsStringTools` for constructors and conversions.
 */
@:native("std::ffi::OsString")
extern class OsString {
	public function new();
	public function clone(): OsString;
}

