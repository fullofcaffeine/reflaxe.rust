package haxe.ds;

import haxe.Constraints.IMap;

/**
	EnumValueMap (Rust target)

	Why
	- `Map<EnumValue, V>` specializes to `haxe.ds.EnumValueMap` in the standard library.
	- Rust requires keys that implement hashing + equality, but Haxe enum values are structurally compared.

	What
	- A pragmatic `EnumValueMap<K, V>` implementation for the Rust target.
	- Uses a stable-ish string key derived from `Std.string(key)` to index into two internal maps.

	How
	- We compute `id = Std.string(key)` and store:
	  - `keysMap`: id -> original key (so `keys()` yields `K`)
	  - `valuesMap`: id -> value
	- This requires `K: Clone` in Rust output for iteration/copy, which is typically satisfied because reflaxe.rust
	  derives `Clone` for emitted enums by default.
**/
@:rustGeneric([
	"K: Clone + Send + Sync + 'static + std::fmt::Debug",
	"V: Clone + Send + Sync + 'static + std::fmt::Debug"
])
class EnumValueMap<K:EnumValue, V> implements IMap<K, V> {
	/**
		Storage backing for Rust target enum-value-keyed map operations.

		Why public
		- `rust.MapStorageTools` centralizes unavoidable Rust-boundary storage operations.
		- Generated helper modules currently require direct field visibility.
		- Keeping these private would force repeated raw fallback inside each `EnumValueMap` method.

		How
		- Treat these fields as framework-internal storage.
		- Callers should use the `IMap` surface instead of direct storage access.
	**/
	public var keysMap:rust.HashMap<String, K>;

	public var valuesMap:rust.HashMap<String, V>;

	public function new():Void {
		keysMap = new rust.HashMap();
		valuesMap = new rust.HashMap();
	}

	public function set(key:K, value:V):Void {
		var id = Std.string(key);
		#if macro
		#else
		rust.MapStorageTools.enumValueMapSet(this, id, key, value);
		#end
	}

	@:rustReturn("Option<V>")
	public function get(key:K):Null<V> {
		var id = Std.string(key);
		#if macro
		return null;
		#else
		return rust.MapStorageTools.enumValueMapGetCloned(this, id);
		#end
	}

	public function exists(key:K):Bool {
		var id = Std.string(key);
		#if macro
		return false;
		#else
		return rust.MapStorageTools.enumValueMapExists(this, id);
		#end
	}

	public function remove(key:K):Bool {
		var id = Std.string(key);
		#if macro
		return false;
		#else
		return rust.MapStorageTools.enumValueMapRemoveExists(this, id);
		#end
	}

	public function keys():Iterator<K> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.enumValueMapKeysOwned(this);
		#end
	}

	public function iterator():Iterator<V> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.enumValueMapValuesOwned(this);
		#end
	}

	public function keyValueIterator():KeyValueIterator<K, V> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.enumValueMapKeyValuesOwned(this);
		#end
	}

	public function copy():EnumValueMap<K, V> {
		var out = new EnumValueMap<K, V>();
		#if macro
		#else
		rust.MapStorageTools.enumValueMapCloneInto(out, this);
		#end
		return out;
	}

	public function toString():String {
		#if macro
		return "{}";
		#else
		return rust.MapStorageTools.enumValueMapDebugString(this);
		#end
	}

	public function clear():Void {
		#if macro
		#else
		rust.MapStorageTools.enumValueMapClear(this);
		#end
	}
}
