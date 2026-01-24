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

	@:rustMutating
	public function push(value: T): Void;

	@:rustMutating
	public function pop(): Option<T>;
	public function clone(): Vec<T>;

	/**
	 * `iterator()` exists to make `for (x in vec)` typecheck in Haxe.
	 *
	 * The compiler special-cases `iterator()` on `rust.Vec<T>` and lowers it to
	 * `vec.iter().cloned()` in Rust output (to avoid moving the vec).
	 */
	@:native("iter")
	public function iterator(): Iterator<T>;
}
