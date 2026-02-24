package rust;

/**
 * rust.MapStorageTools
 *
 * Why
 * - `haxe.ds.StringMap` and `haxe.ds.IntMap` store Rust `HashMap` state inside portable class refs.
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
}
