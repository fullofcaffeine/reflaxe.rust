package rust;

/**
 * Non-inline helpers for `rust.HashMap<K,V>`.
 *
 * Keep `__rust__` injection out of app code; use helpers like these instead.
 */
class HashMapTools {
	@:rustGeneric(["K: Eq + std::hash::Hash + Clone", "V: Clone"])
	@:rustReturn("Option<V>")
	public static function getCloned<K, V>(m:Ref<HashMap<K, V>>, key:Ref<K>):Null<V> {
		return untyped __rust__("{0}.get({1}).cloned()", m, key);
	}

	public static function len<K, V>(m:Ref<HashMap<K, V>>):Int {
		return untyped __rust__("{0}.len() as i32", m);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function insert<K, V>(m:MutRef<HashMap<K, V>>, key:K, value:V):Option<V> {
		return untyped __rust__("{0}.insert({1}, {2})", m, key, value);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function remove<K, V>(m:MutRef<HashMap<K, V>>, key:Ref<K>):Option<V> {
		return untyped __rust__("{0}.remove({1})", m, key);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function removeExists<K, V>(m:MutRef<HashMap<K, V>>, key:Ref<K>):Bool {
		return untyped __rust__("{0}.remove({1}).is_some()", m, key);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash + Clone", "V"])
	public static function keysOwned<K, V>(m:Ref<HashMap<K, V>>):Iterator<K> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.keys().cloned().collect::<Vec<_>>())", m);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash", "V: Clone"])
	public static function valuesOwned<K, V>(m:Ref<HashMap<K, V>>):Iterator<V> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.values().cloned().collect::<Vec<_>>())", m);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash + Clone", "V: Clone"])
	public static function keyValuesOwned<K, V>(m:Ref<HashMap<K, V>>):KeyValueIterator<K, V> {
		return
			untyped __rust__("hxrt::iter::Iter::from_vec({0}.iter().map(|(k, v)| hxrt::iter::KeyValue { key: k.clone(), value: v.clone() }).collect::<Vec<_>>())",
				m);
	}

	@:rustGeneric(["K: Eq + std::hash::Hash + std::fmt::Debug", "V: std::fmt::Debug"])
	public static function debugString<K, V>(m:Ref<HashMap<K, V>>):String {
		return untyped __rust__("format!(\"{:?}\", {0})", m);
	}
}
