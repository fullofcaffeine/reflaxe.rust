package rust;

/**
 * rust.Vec<T>
 *
 * Rust-facing Vec type intended for the `rusty` profile.
 *
 * Notes:
 * - This is an extern binding to Rust's `Vec<T>` (prelude type).
 * - Helper operations that need casts (usize/i32) live in `VecTools`.
 * - `__rust__` injection is used in `VecTools` (framework code), not in apps.
 */
@:native("Vec")
extern class Vec<T> {
	public function new();

	public function push(value: T): Void;
	public function pop(): Option<T>;
	public function clone(): Vec<T>;
}
