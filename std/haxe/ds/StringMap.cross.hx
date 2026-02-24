package haxe.ds;

import haxe.Constraints.IMap;

/**
	StringMap (Rust target)

	Why
	- A large amount of portable Haxe code relies on `haxe.ds.StringMap` (directly, or via `Map<String, V>`).
	- Rust has no built-in "null", so *absence* is represented in Rust output via `Option<T>` (backend detail).
	- We want a fast, predictable implementation backed by Rust's standard `HashMap`.

	What
	- Implements the standard Haxe `StringMap<T>` API on the Rust target.
	- Backed by Rust `std::collections::HashMap<String, T>` stored inside the portable runtime model
	  (`HxRef<T> = Rc<RefCell<T>>` for class instances).

	How
	- `get()` returns `Null<T>` per Haxe API. In Rust output this is lowered to `Option<T>`:
	  - `Some(v)` when present
	  - `None` when missing
	- For simplicity and to preserve Haxe "values can be re-used" expectations, `get()/iterator()/keyValueIterator()`
	  clone stored values (`T: Clone` in Rust output).
	- Iteration methods (`keys()`, `iterator()`, `keyValueIterator()`) return owned Rust iterators
	  (`Vec<_>.into_iter()`), and the compiler lowers Haxe `for` loops to Rust `for` loops over these iterators.
	  Manual `.hasNext()` / `.next()` usage is not guaranteed to work yet.
**/
@:rustGeneric("T: Clone + Send + Sync + 'static + std::fmt::Debug")
class StringMap<T> implements IMap<String, T> {
	/**
		Storage backing for Rust target map operations.

		Why public
		- `rust.MapStorageTools` hosts shared typed boundary helpers in a separate module.
		- Generated helper modules currently require direct field visibility in emitted Rust.
		- Keeping this private would force repeated raw fallback in each map method until the compiler
		  supports friend-style visibility for this cross-module pattern.

		How
		- User code should use map APIs (`set/get/...`) instead of touching storage directly.
	**/
	public var h:rust.HashMap<String, T>;

	public function new():Void {
		h = new rust.HashMap();
	}

	public function set(key:String, value:T):Void {
		#if macro
		#else
		rust.MapStorageTools.stringMapSet(this, key, value);
		#end
	}

	@:rustReturn("Option<T>")
	public function get(key:String):Null<T> {
		#if macro
		return null;
		#else
		return rust.MapStorageTools.stringMapGetCloned(this, key);
		#end
	}

	public function exists(key:String):Bool {
		#if macro
		return false;
		#else
		return rust.MapStorageTools.stringMapExists(this, key);
		#end
	}

	public function remove(key:String):Bool {
		#if macro
		return false;
		#else
		return rust.MapStorageTools.stringMapRemoveExists(this, key);
		#end
	}

	public function keys():Iterator<String> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.stringMapKeysOwned(this);
		#end
	}

	public function iterator():Iterator<T> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.stringMapValuesOwned(this);
		#end
	}

	public function keyValueIterator():KeyValueIterator<String, T> {
		#if macro
		return [].iterator();
		#else
		return rust.MapStorageTools.stringMapKeyValuesOwned(this);
		#end
	}

	public function copy():StringMap<T> {
		var out = new StringMap<T>();
		#if macro
		#else
		rust.MapStorageTools.stringMapCloneInto(out, this);
		#end
		return out;
	}

	public function toString():String {
		#if macro
		return "{}";
		#else
		return rust.MapStorageTools.stringMapDebugString(this);
		#end
	}

	public function clear():Void {
		#if macro
		#else
		rust.MapStorageTools.stringMapClear(this);
		#end
	}
}
