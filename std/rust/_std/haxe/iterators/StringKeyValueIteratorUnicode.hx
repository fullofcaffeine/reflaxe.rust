package haxe.iterators;

/**
	Rust-target implementation of Haxe's Unicode key/value string iterator.

	Why
	- The upstream nominal type is visible to Haxe consumers but is not emitted automatically.
	- A key/value iterator must expose logical character positions and Unicode code points without
	  leaking Rust UTF-8 byte offsets.
	- Typed helper adaptation must preserve the iterator object's shared cursor and record shape.

	What
	- Produces `{key:Int, value:Int}` records for each Unicode scalar in source order.
	- Keys are zero-based logical scalar positions; values are Unicode code points.
	- Preserves the upstream constructor and `unicodeKeyValueIterator` convenience API.

	How
	- Both the read cursor and reported logical key advance once per Unicode scalar.
	- `StringTools.fastCodeAt` performs the typed scalar lookup.
	- The compiler's existing structural key/value iterator bridge carries the nominal iterator
	  through helpers without collecting it or introducing a runtime-dynamic payload.
**/
class StringKeyValueIteratorUnicode {
	var offset = 0;
	var charOffset = 0;
	var s:String;

	/**
		Why: keeps the upstream nominal construction boundary available to typed Haxe code.
		What: creates an iterator positioned before the first Unicode scalar in `s`.
		How: stores the source and initializes its scalar and logical-key cursors to zero.
	**/
	public inline function new(s:String) {
		this.s = s;
	}

	/**
		Why: Haxe's key/value iterator protocol probes availability without consuming a pair.
		What: reports whether another Unicode scalar pair is available.
		How: compares the scalar cursor with the target's scalar-based `String.length`.
	**/
	public inline function hasNext():Bool {
		return offset < s.length;
	}

	/**
		Why: consumers need stable logical keys and platform-independent code points.
		What: returns the next `{key, value}` pair.
		How: reads one scalar code point, increments the source cursor once, and increments the
		logical character key once.
	**/
	public inline function next():{key:Int, value:Int} {
		return {key: charOffset++, value: StringTools.fastCodeAt(s, offset++)};
	}

	/**
		Why: mirrors the upstream static-extension entry point used by portable Haxe code.
		What: creates a `StringKeyValueIteratorUnicode` for `s`.
		How: delegates to the nominal constructor without evaluating `s` more than once.
	**/
	public static inline function unicodeKeyValueIterator(s:String):StringKeyValueIteratorUnicode {
		return new StringKeyValueIteratorUnicode(s);
	}
}
