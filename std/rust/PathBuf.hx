package rust;

/**
 * rust.PathBuf
 *
 * Rust-facing owned path buffer (`std::path::PathBuf`) intended for the `metal` profile.
 *
 * Notes:
 * - Prefer using `PathBufTools` for common constructors and conversions.
 * - `PathBufTools` uses a typed native boundary (`std/rust/native/path_buf_tools*.rs`) so
 *   app code does not need raw target-code injection.
 * - Avoid using `__rust__` directly in apps; keep escapes in `std/`.
 */
@:native("std::path::PathBuf")
extern class PathBuf {
	public function new();
	public function clone():PathBuf;
}
