package rust;

/**
 * VecTools
 *
 * Non-inline helpers for `rust.Vec<T>` that need casts (usize/i32) or small shims.
 *
 * IMPORTANT: Keep these as regular (non-inline) functions so `__rust__` stays inside
 * framework code and does not get inlined into application code.
 */
class VecTools {
	@:rustGeneric("T: Clone")
	public static function fromArray<T>(a: Array<T>): Vec<T> {
		return untyped __rust__("{0}.clone()", a);
	}

	@:rustGeneric("T: Clone")
	public static function toArray<T>(v: Vec<T>): Array<T> {
		return untyped __rust__("{0}.clone()", v);
	}

	public static function len<T>(v: Vec<T>): Int {
		return untyped __rust__("{0}.len() as i32", v);
	}

	@:rustGeneric("T: Clone")
	public static function get<T>(v: Vec<T>, index: Int): Option<T> {
		return untyped __rust__("{0}.get({1} as usize).cloned()", v, index);
	}

	public static function set<T>(v: Vec<T>, index: Int, value: T): Vec<T> {
		return untyped __rust__(
			"{ let mut __v = {0}; __v[{1} as usize] = {2}; __v }",
			v,
			index,
			value
		);
	}
}
