package rust;

/**
 * rust.PathBuf
 *
 * Rust-facing owned path buffer (`std::path::PathBuf`) intended for the `rusty` profile.
 *
 * Notes:
 * - Prefer using `PathBufTools` for common constructors and conversions.
 * - Avoid using `__rust__` directly in apps; keep escapes in `std/`.
 */
@:native("std::path::PathBuf")
extern class PathBuf {
	public function new();
	public function clone(): PathBuf;
}

