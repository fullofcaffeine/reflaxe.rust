package rust;

/**
 * rust.MapStorageTools
 *
 * Why
 * - `haxe.ds.StringMap`, `haxe.ds.IntMap`, `haxe.ds.ObjectMap`, and `haxe.ds.EnumValueMap`
 *   store Rust `HashMap` state inside portable class refs.
 * - Direct field access from map methods can produce clone-shaped borrow codegen; mutating those
 *   temporaries would break map semantics.
 *
 * What
 * - Typed framework-only helpers that perform map storage operations through one raw Rust boundary.
 * - Keeps map modules (`haxe.ds.StringMap` / `haxe.ds.IntMap`) strongly typed and free of repeated
 *   inline raw expressions.
 *
 * How
 * - Each helper takes the concrete map owner type and performs borrow + operation in one expression.
 * - Callers return to typed Haxe immediately after crossing this boundary.
 */
class MapStorageTools {
	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapSet<V>(map:haxe.ds.StringMap<V>, key:String, value:V):Void {
		untyped __rust__("{0}.borrow_mut().h.insert({1}, {2});", map, key, value);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	@:rustReturn("Option<V>")
	public static function stringMapGetCloned<V>(map:haxe.ds.StringMap<V>, key:String):Null<V> {
		return untyped __rust__("{0}.borrow().h.get(&{1}).cloned()", map, key);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapExists<V>(map:haxe.ds.StringMap<V>, key:String):Bool {
		return untyped __rust__("{0}.borrow().h.contains_key(&{1})", map, key);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapRemoveExists<V>(map:haxe.ds.StringMap<V>, key:String):Bool {
		return untyped __rust__("{0}.borrow_mut().h.remove(&{1}).is_some()", map, key);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapKeysOwned<V>(map:haxe.ds.StringMap<V>):Iterator<String> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.keys().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapValuesOwned<V>(map:haxe.ds.StringMap<V>):Iterator<V> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.values().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapKeyValuesOwned<V>(map:haxe.ds.StringMap<V>):KeyValueIterator<String, V> {
		return
			untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.iter().map(|(k, v)| hxrt::iter::KeyValue { key: k.clone(), value: v.clone() }).collect::<Vec<_>>())",
			map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapCloneInto<V>(dst:haxe.ds.StringMap<V>, src:haxe.ds.StringMap<V>):Void {
		untyped __rust__("{0}.borrow_mut().h = {1}.borrow().h.clone();", dst, src);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapDebugString<V>(map:haxe.ds.StringMap<V>):String {
		return untyped __rust__("format!(\"{:?}\", {0}.borrow().h)", map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapClear<V>(map:haxe.ds.StringMap<V>):Void {
		untyped __rust__("{0}.borrow_mut().h.clear();", map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapSet<V>(map:haxe.ds.IntMap<V>, key:Int, value:V):Void {
		untyped __rust__("{0}.borrow_mut().h.insert({1}, {2});", map, key, value);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	@:rustReturn("Option<V>")
	public static function intMapGetCloned<V>(map:haxe.ds.IntMap<V>, key:Int):Null<V> {
		return untyped __rust__("{0}.borrow().h.get(&{1}).cloned()", map, key);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapExists<V>(map:haxe.ds.IntMap<V>, key:Int):Bool {
		return untyped __rust__("{0}.borrow().h.contains_key(&{1})", map, key);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapRemoveExists<V>(map:haxe.ds.IntMap<V>, key:Int):Bool {
		return untyped __rust__("{0}.borrow_mut().h.remove(&{1}).is_some()", map, key);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapKeysOwned<V>(map:haxe.ds.IntMap<V>):Iterator<Int> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.keys().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapValuesOwned<V>(map:haxe.ds.IntMap<V>):Iterator<V> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.values().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapKeyValuesOwned<V>(map:haxe.ds.IntMap<V>):KeyValueIterator<Int, V> {
		return
			untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().h.iter().map(|(k, v)| hxrt::iter::KeyValue { key: k.clone(), value: v.clone() }).collect::<Vec<_>>())",
			map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapCloneInto<V>(dst:haxe.ds.IntMap<V>, src:haxe.ds.IntMap<V>):Void {
		untyped __rust__("{0}.borrow_mut().h = {1}.borrow().h.clone();", dst, src);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapDebugString<V>(map:haxe.ds.IntMap<V>):String {
		return untyped __rust__("format!(\"{:?}\", {0}.borrow().h)", map);
	}

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapClear<V>(map:haxe.ds.IntMap<V>):Void {
		untyped __rust__("{0}.borrow_mut().h.clear();", map);
	}

	@:rustGeneric("K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function objectMapKeyId<K:{}>(key:K):String {
		return untyped __rust__("hxrt::hxref::ptr_id(&{0})", key);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapSet<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String, key:K, value:V):Void {
		untyped __rust__("{ let mut __s = {0}.borrow_mut(); __s.keys_map.insert({1}.clone(), {2}); __s.values_map.insert({1}, {3}); }", map, id, key, value);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	@:rustReturn("Option<V>")
	public static function objectMapGetCloned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String):Null<V> {
		return untyped __rust__("{0}.borrow().values_map.get(&{1}).cloned()", map, id);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapExists<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String):Bool {
		return untyped __rust__("{0}.borrow().values_map.contains_key(&{1})", map, id);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapRemoveExists<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String):Bool {
		return
			untyped __rust__("{ let mut __s = {0}.borrow_mut(); let __existed = __s.values_map.remove(&{1}).is_some(); __s.keys_map.remove(&{1}); __existed }",
				map, id);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapKeysOwned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):Iterator<K> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().keys_map.values().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapValuesOwned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):Iterator<V> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().values_map.values().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapKeyValuesOwned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):KeyValueIterator<K, V> {
		return
			untyped __rust__("hxrt::iter::Iter::from_vec({ let __s = {0}.borrow(); __s.values_map.iter().map(|(id, v)| hxrt::iter::KeyValue { key: __s.keys_map.get(id).unwrap().clone(), value: v.clone() }).collect::<Vec<_>>() })",
			map);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapCloneInto<K:{}, V>(dst:haxe.ds.ObjectMap<K, V>, src:haxe.ds.ObjectMap<K, V>):Void {
		untyped __rust__("{ let __s = {1}.borrow(); let mut __o = {0}.borrow_mut(); __o.keys_map = __s.keys_map.clone(); __o.values_map = __s.values_map.clone(); }",
			dst,
			src);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapDebugString<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):String {
		return untyped __rust__("format!(\"{:?}\", {0}.borrow().values_map)", map);
	}

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapClear<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):Void {
		untyped __rust__("{ let mut __s = {0}.borrow_mut(); __s.keys_map.clear(); __s.values_map.clear(); }", map);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapSet<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String, key:K, value:V):Void {
		untyped __rust__("{ let mut __s = {0}.borrow_mut(); __s.keys_map.insert({1}.clone(), {2}); __s.values_map.insert({1}, {3}); }", map, id, key, value);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	@:rustReturn("Option<V>")
	public static function enumValueMapGetCloned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String):Null<V> {
		return untyped __rust__("{0}.borrow().values_map.get(&{1}).cloned()", map, id);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapExists<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String):Bool {
		return untyped __rust__("{0}.borrow().values_map.contains_key(&{1})", map, id);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapRemoveExists<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String):Bool {
		return
			untyped __rust__("{ let mut __s = {0}.borrow_mut(); let __existed = __s.values_map.remove(&{1}).is_some(); __s.keys_map.remove(&{1}); __existed }",
				map, id);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapKeysOwned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):Iterator<K> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().keys_map.values().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapValuesOwned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):Iterator<V> {
		return untyped __rust__("hxrt::iter::Iter::from_vec({0}.borrow().values_map.values().cloned().collect::<Vec<_>>())", map);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapKeyValuesOwned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):KeyValueIterator<K, V> {
		return
			untyped __rust__("hxrt::iter::Iter::from_vec({ let __s = {0}.borrow(); __s.values_map.iter().map(|(id, v)| hxrt::iter::KeyValue { key: __s.keys_map.get(id).unwrap().clone(), value: v.clone() }).collect::<Vec<_>>() })",
			map);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapCloneInto<K:EnumValue, V>(dst:haxe.ds.EnumValueMap<K, V>, src:haxe.ds.EnumValueMap<K, V>):Void {
		untyped __rust__("{ let __s = {1}.borrow(); let mut __o = {0}.borrow_mut(); __o.keys_map = __s.keys_map.clone(); __o.values_map = __s.values_map.clone(); }",
			dst,
			src);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapDebugString<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):String {
		return untyped __rust__("format!(\"{:?}\", {0}.borrow().values_map)", map);
	}

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapClear<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):Void {
		untyped __rust__("{ let mut __s = {0}.borrow_mut(); __s.keys_map.clear(); __s.values_map.clear(); }", map);
	}
}
