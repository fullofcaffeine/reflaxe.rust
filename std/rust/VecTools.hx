package rust;

/**
 * VecTools
 *
 * Non-inline helpers for `rust.Vec<T>` that need casts (usize/i32) or small shims.
 *
 * IMPORTANT: Keep these as regular (non-inline) functions so `__rust__` stays inside
 * framework code and does not get inlined into application code.
 *
 * Borrow-first note:
 * - Some helpers (like `len`/`get`) take a borrowed `rust.Ref<Vec<T>>` so they do not move the
 *   underlying `Vec<T>` in Rust output.
 * - In most cases you can pass a `Vec<T>` directly and the compiler will emit `&vec` at the call site.
 */
class VecTools {
	@:rustGeneric("T: Clone")
	public static function fromArray<T>(a: Array<T>): Vec<T> {
		return untyped __rust__("{0}.to_vec()", a);
	}

	@:rustGeneric("T: Clone")
	public static function toArray<T>(v: Vec<T>): Array<T> {
		return untyped __rust__("hxrt::array::Array::<T>::from_vec({0})", v);
	}

	public static function len<T>(v: Ref<Vec<T>>): Int {
		return untyped __rust__("{0}.len() as i32", v);
	}

	@:rustGeneric("T: Clone")
	public static function get<T>(v: Ref<Vec<T>>, index: Int): Option<T> {
		return untyped __rust__("{0}.get({1} as usize).cloned()", v, index);
	}

	/**
	 * Borrow-first element access.
	 *
	 * Why:
	 * - `get(...)` clones because it returns an owned `T`.
	 * - In Rusty/profile code we often want `Option<&T>` instead.
	 *
	 * How:
	 * - Requires a borrowed `Ref<Vec<T>>` so the returned `Ref<T>` cannot outlive the borrow scope.
	 */
	public static function getRef<T>(v: Ref<Vec<T>>, index: Int): Option<Ref<T>> {
		return untyped __rust__("{0}.get({1} as usize)", v, index);
	}

	/**
	 * Mutable element access (`Option<&mut T>`).
	 *
	 * NOTE:
	 * - Requires `MutRef<Vec<T>>` (so the vec binding is borrowed mutably).
	 * - Prefer using this inside `Borrow.withMut(...)` or `MutSliceTools.with(...)`.
	 */
	public static function getMut<T>(v: MutRef<Vec<T>>, index: Int): Option<MutRef<T>> {
		return untyped __rust__("{0}.get_mut({1} as usize)", v, index);
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
