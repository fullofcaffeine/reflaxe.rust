package rust;

/**
 * Non-inline helpers for `rust.HashMap<K,V>`.
 *
 * Keep `__rust__` injection out of app code; use helpers like these instead.
 */
class HashMapTools {
	public static function len<K, V>(m: HashMap<K, V>): Int {
		return untyped __rust__("{0}.len() as i32", m);
	}
}

