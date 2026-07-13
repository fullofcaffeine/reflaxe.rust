package haxe.iterators;

/**
	Rust-target implementation of Haxe's Unicode string iterator.

	Why
	- The upstream type is public and can cross typed `Iterator<Int>` helper boundaries.
	- Upstream std files are typed but are not emitted by default, so the Rust target must own the
	  nominal module whenever generated Rust refers to it.
	- Rust strings are indexed by Unicode scalar value in this target; emitting a UTF-16 surrogate
	  walk would therefore skip valid characters instead of improving portability.

	What
	- Iterates one Unicode scalar value at a time and returns its code point as `Int`.
	- Preserves the upstream constructor and `unicodeIterator` convenience API.

	How
	- `String.length` and `StringTools.fastCodeAt` share the target's Unicode-scalar index model.
	- The iterator advances exactly one scalar index per `next()` call.
	- Structural `Iterator<Int>` adaptation remains compiler-owned so the nominal object keeps one
	  shared cursor without an eager collection or dynamic carrier.
**/
class StringIteratorUnicode {
	var offset = 0;
	var s:String;

	/**
		Why: keeps the upstream nominal construction boundary available to typed Haxe code.
		What: creates an iterator positioned before the first Unicode scalar in `s`.
		How: stores the source string and initializes the scalar offset to zero.
	**/
	public inline function new(s:String) {
		this.s = s;
	}

	/**
		Why: Haxe's iterator protocol probes availability separately from consuming a value.
		What: reports whether another Unicode scalar is available.
		How: compares the scalar cursor with the target's scalar-based `String.length`.
	**/
	public inline function hasNext():Bool {
		return offset < s.length;
	}

	/**
		Why: consumers need a platform-independent code point rather than a UTF-8 byte.
		What: returns the next Unicode scalar value as an integer code point.
		How: reads through the typed `StringTools` boundary, then advances the cursor once.
	**/
	public inline function next():Int {
		return StringTools.fastCodeAt(s, offset++);
	}

	/**
		Why: mirrors the upstream static-extension entry point used by portable Haxe code.
		What: creates a `StringIteratorUnicode` for `s`.
		How: delegates to the nominal constructor without evaluating `s` more than once.
	**/
	public static inline function unicodeIterator(s:String):StringIteratorUnicode {
		return new StringIteratorUnicode(s);
	}
}
