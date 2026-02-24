package haxe.ds;

import haxe.Constraints.IMap;

/**
	IntMap (Rust target)

	Why
	- `haxe.ds.IntMap` is a common specialization behind `Map<Int, V>`.
	- Rust's `HashMap<i32, V>` is a good backend representation for Haxe `Int` keys.

	What
	- Implements the standard Haxe `IntMap<T>` API on the Rust target.
	- Backed by Rust `std::collections::HashMap<i32, T>` under the portable class-instance model.

	How
	- `get()` returns `Null<T>` in Haxe; this is lowered to `Option<T>` in Rust output.
	- Value-returning operations clone (`T: Clone`).
	- Iterators are returned as owned Rust iterators (`Vec<_>.into_iter()`), intended for `for` loops.
**/
@:rustGeneric("T: Clone + Send + Sync + 'static + std::fmt::Debug")
class IntMap<T> implements IMap<Int, T> {
	/**
		Storage backing for Rust target map operations.

		Why public
		- `rust.MapStorageTools` centralizes typed boundary helpers for map operations in another module.
		- Generated Rust helper modules currently require direct field visibility.
		- Keeping this private would re-introduce per-method raw fallback until the compiler can emit
		  friend-style visibility for this pattern.

		How
		- Consumers should use the `IMap` API surface.
	**/
	public var h:rust.HashMap<Int, T>;

	public function new():Void {
		h = new rust.HashMap();
	}

	public function set(key:Int, value:T):Void {
		#if macro
		#else
		rust.MapStorageTools.intMapSet(this, key, value);
		#end
	}

	@:rustReturn("Option<T>")
	public function get(key:Int):Null<T> {
		#if macro
		return null;
		#else
		return rust.MapStorageTools.intMapGetCloned(this, key);
		#end
	}

	public function exists(key:Int):Bool {
		#if macro
		return false;
		#else
		return rust.MapStorageTools.intMapExists(this, key);
		#end
	}

	public function remove(key:Int):Bool {
		#if macro
		return false;
		#else
		return rust.MapStorageTools.intMapRemoveExists(this, key);
		#end
	}

	public function keys():Iterator<Int> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.intMapKeysOwned(this);
		#end
	}

	public function iterator():Iterator<T> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.intMapValuesOwned(this);
		#end
	}

	public function keyValueIterator():KeyValueIterator<Int, T> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.intMapKeyValuesOwned(this);
		#end
	}

	public function copy():IntMap<T> {
		var out = new IntMap<T>();
		#if macro
		#else
		rust.MapStorageTools.intMapCloneInto(out, this);
		#end
		return out;
	}

	public function toString():String {
		#if macro
		return "{}";
		#else
		return rust.MapStorageTools.intMapDebugString(this);
		#end
	}

	public function clear():Void {
		#if macro
		#else
		rust.MapStorageTools.intMapClear(this);
		#end
	}
}
