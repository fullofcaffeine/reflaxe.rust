package haxe.ds;

import haxe.Constraints.IMap;

/**
	ObjectMap (Rust target)

	Why
	- Haxe `ObjectMap<K, V>` is used when `K` is an object/structure key (behind `Map<K, V>` specialization).
	- Rust requires a hashable key; for portable Haxe object keys we need an identity-based strategy.

	What
	- A best-effort `ObjectMap<K, V>` implementation for the Rust target.
	- Intended for **class instance** keys (`K` being a portable Haxe class), which are represented as
	  `Rc<RefCell<...>>` in Rust output and can be identity-keyed.

	How
	- We compute an identity string from the key's underlying `Rc` pointer (`format!("{:p}", Rc::as_ptr(...))`).
	- Two internal hash maps are kept:
	  - `keysMap`: id -> original key (so `keys()` can yield `K`)
	  - `valuesMap`: id -> value
	- Limitations (documented):
	  - Keys that are not portable Haxe class instances may not compile/work (because the identity function relies on `Rc`).
	  - Value-returning operations clone (`K: Clone`, `V: Clone`) for Haxe-like reuse semantics.
**/
@:rustGeneric([
	"K: hxrt::hxref::HxRefLike + Clone + Send + Sync + 'static + std::fmt::Debug",
	"V: Clone + Send + Sync + 'static + std::fmt::Debug"
])
class ObjectMap<K:{}, V> implements IMap<K, V> {
	/**
		Storage backing for Rust target object-keyed map operations.

		Why public
		- `rust.MapStorageTools` centralizes unavoidable Rust-boundary map storage operations.
		- Generated helper modules currently require direct field visibility.
		- Keeping these private would force repeated raw fallback inside each `ObjectMap` method.

		How
		- Treat these fields as framework-internal storage.
		- Callers should use the `IMap` API (`set/get/exists/...`) instead of direct storage access.
	**/
	public var keysMap:rust.HashMap<String, K>;

	public var valuesMap:rust.HashMap<String, V>;

	public function new():Void {
		keysMap = new rust.HashMap();
		valuesMap = new rust.HashMap();
	}

	inline function keyId(key:K):String {
		#if macro
		return "";
		#else
		return rust.MapStorageTools.objectMapKeyId(key);
		#end
	}

	public function set(key:K, value:V):Void {
		var id = keyId(key);
		#if macro
		#else
		rust.MapStorageTools.objectMapSet(this, id, key, value);
		#end
	}

	@:rustReturn("Option<V>")
	public function get(key:K):Null<V> {
		var id = keyId(key);
		#if macro
		return null;
		#else
		return rust.MapStorageTools.objectMapGetCloned(this, id);
		#end
	}

	public function exists(key:K):Bool {
		var id = keyId(key);
		#if macro
		return false;
		#else
		return rust.MapStorageTools.objectMapExists(this, id);
		#end
	}

	public function remove(key:K):Bool {
		var id = keyId(key);
		#if macro
		return false;
		#else
		return rust.MapStorageTools.objectMapRemoveExists(this, id);
		#end
	}

	public function keys():Iterator<K> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.objectMapKeysOwned(this);
		#end
	}

	public function iterator():Iterator<V> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.objectMapValuesOwned(this);
		#end
	}

	public function keyValueIterator():KeyValueIterator<K, V> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.objectMapKeyValuesOwned(this);
		#end
	}

	public function copy():ObjectMap<K, V> {
		var out = new ObjectMap<K, V>();
		#if macro
		#else
		rust.MapStorageTools.objectMapCloneInto(out, this);
		#end
		return out;
	}

	public function toString():String {
		#if macro
		return "{}";
		#else
		return rust.MapStorageTools.objectMapDebugString(this);
		#end
	}

	public function clear():Void {
		#if macro
		#else
		rust.MapStorageTools.objectMapClear(this);
		#end
	}
}
