package haxe.iterators;

/**
	`haxe.iterators.StringKeyValueIterator` (Rust target override)

	Why
	- `StringTools.keyValueIterator()` returns this type.
	- Macro code and some std utilities expect this iterator to exist.

	What
	- Iterates over `{ key: index, value: code }` pairs for a string.

	How
	- `key` is the current index.
	- `value` is the character code at that index (via `StringTools.fastCodeAt`).
**/
class StringKeyValueIterator {
	var offset = 0;
	var s:String;

	public inline function new(s:String) {
		this.s = s;
	}

	public inline function hasNext() {
		return offset < s.length;
	}

	public inline function next() {
		return {key: offset, value: StringTools.fastCodeAt(s, offset++)};
	}
}
