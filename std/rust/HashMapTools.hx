package rust;

/**
 * `rust.HashMapTools`
 *
 * Why
 * - `rust.HashMap<K,V>` is part of the Rust-first surface and frequently appears in
 *   profile-focused examples and snapshots.
 * - The previous helper used inline `untyped __rust__` expressions for every operation.
 *   That pushed routine map calls through `ERaw` fallback paths, inflating metal fallback
 *   diagnostics and obscuring whether fallback came from app code or framework internals.
 *
 * What
 * - A typed extern facade backed by a hand-written Rust module.
 * - The Haxe API remains unchanged (`Ref`/`MutRef` receivers, typed generics, typed returns),
 *   but the unavoidable native implementation details now live in `rust/native/hash_map_tools*.rs`.
 *
 * How
 * - `@:native(...)` binds the extern to a concrete Rust module included through
 *   `@:rustExtraSrc(...)`.
 * - The boundary is profile-aware:
 *   - non-nullable string mode (`metal`) uses `hash_map_tools.rs`.
 *   - nullable string mode (`portable` default) uses `hash_map_tools_nullable.rs` so
 *     `debugString` returns `hxrt::string::HxString` consistently.
 * - Callers cross a typed boundary and immediately stay in typed code, with no `Dynamic`,
 *   `Reflect`, or app-side injection required.
 */
#if rust_string_nullable
@:native("crate::hash_map_tools_nullable::HashMapTools")
@:rustExtraSrc("rust/native/hash_map_tools_nullable.rs")
#else
@:native("crate::hash_map_tools::HashMapTools")
@:rustExtraSrc("rust/native/hash_map_tools.rs")
#end
extern class HashMapTools {
	@:rustGeneric(["K: Eq + std::hash::Hash + Clone", "V: Clone"])
	@:rustReturn("Option<V>")
	public static function getCloned<K, V>(m:Ref<HashMap<K, V>>, key:Ref<K>):Null<V>;

	public static function len<K, V>(m:Ref<HashMap<K, V>>):Int;

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function insert<K, V>(m:MutRef<HashMap<K, V>>, key:K, value:V):Option<V>;

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function remove<K, V>(m:MutRef<HashMap<K, V>>, key:Ref<K>):Option<V>;

	@:rustGeneric(["K: Eq + std::hash::Hash", "V"])
	public static function removeExists<K, V>(m:MutRef<HashMap<K, V>>, key:Ref<K>):Bool;

	@:rustGeneric(["K: Eq + std::hash::Hash + Clone", "V"])
	public static function keysOwned<K, V>(m:Ref<HashMap<K, V>>):Iterator<K>;

	@:rustGeneric(["K: Eq + std::hash::Hash", "V: Clone"])
	public static function valuesOwned<K, V>(m:Ref<HashMap<K, V>>):Iterator<V>;

	@:rustGeneric(["K: Eq + std::hash::Hash + Clone", "V: Clone"])
	public static function keyValuesOwned<K, V>(m:Ref<HashMap<K, V>>):KeyValueIterator<K, V>;

	@:rustGeneric(["K: Eq + std::hash::Hash + std::fmt::Debug", "V: std::fmt::Debug"])
	public static function debugString<K, V>(m:Ref<HashMap<K, V>>):String;
}
