package haxe.iterators;

import haxe.DynamicAccess;

/**
	`haxe.iterators.DynamicAccessKeyValueIterator` for the Rust target.

	Why
	- `DynamicAccess.keyValueIterator()` exposes this nominal class in Haxe typed AST.
	- The upstream module is used for typing but is not otherwise emitted into generated Rust crates.
	- Key order is intentionally unspecified, while value lookup must remain lazy after construction.

	What
	- Implements the upstream `{ key:String, value:T }` iterator contract.
	- Preserves nominal iterator identity and shared cursor behavior across typed helper boundaries.

	How
	- Snapshots the source keys once, retains the live typed `DynamicAccess<T>`, and looks up each value
	  only when `next()` runs.
	- Returns the ordinary shared anonymous-record representation used by portable Haxe; key/value field
	  names do not select a special owned Rust shape.
	- Uses normal generated Haxe class lowering. The compiler's generic callback-backed structural bridge
	  owns any required ABI adaptation; this class adds no raw Rust, native facade, or
	  DynamicAccess-specific runtime helper.
**/
@:rustGeneric("T: Clone + Send + Sync + 'static + std::fmt::Debug")
class DynamicAccessKeyValueIterator<T> {
	final access:DynamicAccess<T>;
	final keys:Array<String>;
	var index:Int;

	/**
		Creates a key/value cursor over the keys present at construction time.

		Why / What / How
		- Matching upstream behavior requires a stable key list and live value reads.
		- Capture only `access.keys()` and initialize the alias-shared cursor to zero.
	**/
	public inline function new(access:DynamicAccess<T>) {
		this.access = access;
		this.keys = access.keys();
		this.index = 0;
	}

	/**
		Reports whether the captured key list contains another entry.

		Why / What / How
		- Reads the cursor and captured key count without advancing either iterator or source state.
	**/
	public inline function hasNext():Bool {
		return index < keys.length;
	}

	/**
		Returns the next captured key and its current source value.

		Why / What / How
		- Read and advance the key cursor exactly once, then cross the existing `DynamicAccess<T>` boundary
		  for that key and immediately restore the typed `{ key, value }` result.
		- The returned object remains an ordinary Haxe anonymous record with normal aliasing semantics.
	**/
	public inline function next():{key:String, value:T} {
		var key = keys[index++];
		// Preserve upstream's explicit `Null<T>` -> `T` boundary so the runtime Dynamic
		// representation cannot leak into the structural key/value result.
		return {value: (access[key] : T), key: key};
	}
}
