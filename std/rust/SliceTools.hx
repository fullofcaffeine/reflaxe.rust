package rust;

/**
 * SliceTools
 *
 * Helpers for working with `rust.Slice<T>` without `__rust__` in apps.
 *
 * IMPORTANT: keep these as non-inline so injections stay in framework code.
 */
class SliceTools {
	public static function fromVec<T>(v: Ref<Vec<T>>): Slice<T> {
		return untyped __rust__("{0}.as_slice()", v);
	}

	public static function len<T>(s: Slice<T>): Int {
		return untyped __rust__("{0}.len() as i32", s);
	}

	public static function get<T>(s: Slice<T>, index: Int): Option<Ref<T>> {
		return untyped __rust__("{0}.get({1} as usize)", s, index);
	}

	@:rustGeneric("T: Clone")
	public static function toArray<T>(s: Slice<T>): Array<T> {
		return untyped __rust__("{0}.to_vec()", s);
	}
}
