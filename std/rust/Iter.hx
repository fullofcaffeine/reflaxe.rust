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
extern class Iter<T> {}

