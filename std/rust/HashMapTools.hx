package rust;

/**
 * Non-inline helpers for `rust.HashMap<K,V>`.
 *
 * Keep `__rust__` injection out of app code; use helpers like these instead.
 */
class HashMapTools {
	public static function len<K, V>(m: Ref<HashMap<K, V>>): Int {
		return untyped __rust__("{0}.len() as i32", m);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function insert<K, V>(m: MutRef<HashMap<K, V>>, key: K, value: V): Option<V> {
		return untyped __rust__("{0}.insert({1}, {2})", m, key, value);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function remove<K, V>(m: MutRef<HashMap<K, V>>, key: Ref<K>): Option<V> {
		return untyped __rust__("{0}.remove({1})", m, key);
	}
}
