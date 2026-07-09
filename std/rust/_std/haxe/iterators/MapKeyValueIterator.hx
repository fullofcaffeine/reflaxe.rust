package haxe.iterators;

import haxe.Constraints.IMap;

/**
	MapKeyValueIterator (Rust target override)

	Why
	- The upstream Haxe stdlib provides `haxe.iterators.MapKeyValueIterator` as a generic helper that
	  builds `{key, value}` pairs by iterating `map.keys()` and calling `map.get(key)`.
	- Portable code and upstream std helpers may instantiate this class directly instead of only using
	  `for (kv in map.keyValueIterator())`.
	- The earlier Rust override was only a stub. That made Tier1 parity misleading because code could
	  typecheck while the actual helper returned no entries at runtime.

	What
	- Implements the upstream helper shape against the existing `haxe.Constraints.IMap` surface.
	- Supports the normal manual iterator protocol:
	  - `hasNext()`
	  - `next()`

	How
	- Stores the source map and an iterator over its keys.
	- `next()` pulls the next key and looks up the corresponding value through `map.get(key)`.
	- The value lookup is cast back to `V`, matching upstream assumptions that a key produced by
	  `keys()` refers to an existing entry.
**/
@:rustGeneric([
	"K: Clone + Send + Sync + 'static + std::fmt::Debug",
	"V: Clone + Send + Sync + 'static + std::fmt::Debug"
])
class MapKeyValueIterator<K, V> {
	final map:IMap<K, V>;
	final keys:Iterator<K>;

	public inline function new(map:IMap<K, V>) {
		this.keys = map.keys();
		this.map = map;
	}

	public inline function hasNext():Bool {
		return keys.hasNext();
	}

	public inline function next():{key:K, value:V} {
		var key = keys.next();
		var value:V = cast map.get(rust.CloneTools.cloneValue(key));
		return {key: key, value: value};
	}
}
