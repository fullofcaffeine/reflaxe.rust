package rust;

/**
 * rust.Iter<T>
 *
 * Represents an owned iterator (`std::vec::IntoIter<T>`) in Rust output.
 *
 * Notes:
 * - This is primarily useful for iterator-first style without `__rust__` in app code.
 * - Prefer using `IterTools.fromVec(v.clone())` if you need to keep the original vec.
 */
@:native("std::vec::IntoIter")
extern class Iter<T> {
	/**
	 * Exists to make `for (x in it)` typecheck in Haxe.
	 *
	 * The compiler special-cases the desugared shape and lowers it to a Rust `for`
	 * over the owned iterator (consuming it).
	 */
	@:native("into_iter")
	public function iterator(): Iterator<T>;
}
