package rust;

/**
 * `rust.MapStorageTools`
 *
 * Why
 * - `haxe.ds.StringMap`, `haxe.ds.IntMap`, `haxe.ds.ObjectMap`, and `haxe.ds.EnumValueMap`
 *   are heavily used in portable code and need a shared storage helper layer.
 * - The previous implementation used raw `untyped __rust__` bodies in this class, which inflated
 *   metal fallback diagnostics and made the boundary harder to audit.
 *
 * What
 * - A typed extern surface for map storage helpers implemented in a hand-written Rust module.
 * - This keeps map std overrides strongly typed at the Haxe level while moving unavoidable Rust-
 *   specific implementation details into `rust/native/map_storage_tools.rs`.
 *
 * How
 * - `@:native("crate::map_storage_tools::MapStorageTools")` binds this type to the generated crate
 *   module from `@:rustExtraSrc("rust/native/map_storage_tools.rs")`.
 * - `@:rustGeneric(...)` preserves Rust trait constraints at the API boundary.
 * - Callers cross the native boundary through typed signatures only and stay strongly typed after
 *   the call returns.
 */
#if rust_string_nullable
@:native("crate::map_storage_tools_nullable::MapStorageTools")
@:rustExtraSrc("rust/native/map_storage_tools_nullable.rs")
#else
@:native("crate::map_storage_tools::MapStorageTools")
@:rustExtraSrc("rust/native/map_storage_tools.rs")
#end
extern class MapStorageTools {
	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapSet<V>(map:haxe.ds.StringMap<V>, key:String, value:V):Void;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	@:rustReturn("Option<V>")
	public static function stringMapGetCloned<V>(map:haxe.ds.StringMap<V>, key:String):Null<V>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapExists<V>(map:haxe.ds.StringMap<V>, key:String):Bool;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapRemoveExists<V>(map:haxe.ds.StringMap<V>, key:String):Bool;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapKeysOwned<V>(map:haxe.ds.StringMap<V>):Iterator<String>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapValuesOwned<V>(map:haxe.ds.StringMap<V>):Iterator<V>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapKeyValuesOwned<V>(map:haxe.ds.StringMap<V>):KeyValueIterator<String, V>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapCloneInto<V>(dst:haxe.ds.StringMap<V>, src:haxe.ds.StringMap<V>):Void;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapDebugString<V>(map:haxe.ds.StringMap<V>):String;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function stringMapClear<V>(map:haxe.ds.StringMap<V>):Void;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapSet<V>(map:haxe.ds.IntMap<V>, key:Int, value:V):Void;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	@:rustReturn("Option<V>")
	public static function intMapGetCloned<V>(map:haxe.ds.IntMap<V>, key:Int):Null<V>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapExists<V>(map:haxe.ds.IntMap<V>, key:Int):Bool;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapRemoveExists<V>(map:haxe.ds.IntMap<V>, key:Int):Bool;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapKeysOwned<V>(map:haxe.ds.IntMap<V>):Iterator<Int>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapValuesOwned<V>(map:haxe.ds.IntMap<V>):Iterator<V>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapKeyValuesOwned<V>(map:haxe.ds.IntMap<V>):KeyValueIterator<Int, V>;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapCloneInto<V>(dst:haxe.ds.IntMap<V>, src:haxe.ds.IntMap<V>):Void;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapDebugString<V>(map:haxe.ds.IntMap<V>):String;

	@:rustGeneric("V: Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function intMapClear<V>(map:haxe.ds.IntMap<V>):Void;

	@:rustGeneric("K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug")
	public static function objectMapKeyId<K:{}>(key:K):String;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapSet<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String, key:K, value:V):Void;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	@:rustReturn("Option<V>")
	public static function objectMapGetCloned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String):Null<V>;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapExists<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String):Bool;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapRemoveExists<K:{}, V>(map:haxe.ds.ObjectMap<K, V>, id:String):Bool;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapKeysOwned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):Iterator<K>;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapValuesOwned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):Iterator<V>;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapKeyValuesOwned<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):KeyValueIterator<K, V>;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapCloneInto<K:{}, V>(dst:haxe.ds.ObjectMap<K, V>, src:haxe.ds.ObjectMap<K, V>):Void;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapDebugString<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):String;

	@:rustGeneric([
		"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function objectMapClear<K:{}, V>(map:haxe.ds.ObjectMap<K, V>):Void;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapSet<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String, key:K, value:V):Void;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	@:rustReturn("Option<V>")
	public static function enumValueMapGetCloned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String):Null<V>;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapExists<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String):Bool;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapRemoveExists<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>, id:String):Bool;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapKeysOwned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):Iterator<K>;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapValuesOwned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):Iterator<V>;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapKeyValuesOwned<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):KeyValueIterator<K, V>;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapCloneInto<K:EnumValue, V>(dst:haxe.ds.EnumValueMap<K, V>, src:haxe.ds.EnumValueMap<K, V>):Void;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapDebugString<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):String;

	@:rustGeneric([
		"K: Clone + Send + Sync + 'static + std::fmt::Debug",
		"V: Clone + Send + Sync + 'static + std::fmt::Debug"
	])
	public static function enumValueMapClear<K:EnumValue, V>(map:haxe.ds.EnumValueMap<K, V>):Void;
}
