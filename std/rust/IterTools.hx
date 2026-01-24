package rust;

/**
 * IterTools
 *
 * Helpers for creating common iterators without `__rust__` in apps.
 */
class IterTools {
	public static function fromVec<T>(v: Vec<T>): Iter<T> {
		return untyped __rust__("{0}.into_iter()", v);
	}
}

