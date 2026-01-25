/**
 * Demonstrates the preferred Rust interop pattern:
 *
 * - A hand-written Rust module is added via `-D rust_extra_src=native` (see `native/native_math.rs`).
 * - Haxe binds to it via `extern` + `@:native("crate::...")`, without `__rust__` in app code.
 */
@:native("crate::native_math")
extern class NativeMath {
	@:native("gcd")
	public static function gcd(a: Int, b: Int): Int;
}

