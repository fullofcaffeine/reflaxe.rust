package haxe.iterators;

/**
	MapKeyValueIterator (Rust target override)

	Why
	- The upstream Haxe stdlib provides `haxe.iterators.MapKeyValueIterator` as a generic helper that
	  builds `{key, value}` pairs by iterating `map.keys()` and calling `map.get(key)`.
	- That implementation relies on the "manual iterator protocol" (`hasNext()` / `next()`) which is not
	  fully supported yet in reflaxe.rust (the compiler prefers lowering `for` loops directly to Rust `for`).

	What
	- A minimal stub that exists so codebases (and some stdlib inline helpers) can typecheck.

	How
	- Prefer calling `keyValueIterator()` on `haxe.ds.*` maps directly; reflaxe.rust provides those methods
	  and lowers `for (kv in map.keyValueIterator())` to a Rust `for` loop.
	- If you end up here at runtime, `next()` throws with an actionable message.
**/
class MapKeyValueIterator<K, V> {
	public function new(map:Dynamic) {}

	public function hasNext():Bool {
		return false;
	}

	public function next():{key:K, value:V} {
		throw "`haxe.iterators.MapKeyValueIterator` is not supported yet on reflaxe.rust. Prefer `for (kv in map.keyValueIterator())`.";
	}
}
