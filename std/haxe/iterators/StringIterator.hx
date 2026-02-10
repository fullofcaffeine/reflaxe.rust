package haxe.iterators;

/**
	`haxe.iterators.StringIterator` (Rust target override)

	Why
	- `StringTools.iterator()` returns this type and parts of the macro/std code expect it to exist.
	- The Rust backend currently lowers `for` loops to owned iterators, but some std utilities still
	  reference `StringIterator` directly.

	What
	- Iterates over character codes in a string.

	How
	- Uses `StringTools.unsafeCodeAt` to obtain a code value and advances an offset.
**/
class StringIterator {
	var offset = 0;
	var s:String;

	public inline function new(s:String) {
		this.s = s;
	}

	public inline function hasNext() {
		return offset < s.length;
	}

	public inline function next() {
		return StringTools.unsafeCodeAt(s, offset++);
	}
}

