package rust;

/**
 * `rust.IterTools`
 *
 * Why
 * - `IterTools.fromVec(...)` is used by Rust-first snapshots/examples that prefer owned iterator
 *   style (`Vec<T> -> IntoIter<T>`).
 * - The previous implementation used inline `untyped __rust__`, which surfaced as raw `ERaw`
 *   fallback in metal diagnostics.
 *
 * What
 * - A typed extern boundary backed by `std/rust/native/iter_tools.rs`.
 *
 * How
 * - `@:native("crate::iter_tools::IterTools")` binds this class to a crate-local Rust helper
 *   module included via `@:rustExtraSrc`.
 * - Callers stay fully typed (`Vec<T>` in, `Iter<T>` out) without raw injection in first-party
 *   Haxe code.
 */
@:native("crate::iter_tools::IterTools")
@:rustExtraSrc("rust/native/iter_tools.rs")
extern class IterTools {
	public static function fromVec<T>(v:Vec<T>):Iter<T>;
}
