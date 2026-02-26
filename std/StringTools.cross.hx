import haxe.iterators.StringIterator;
import haxe.iterators.StringKeyValueIterator;
import hxrt.string.NativeString;

/**
	`StringTools` (Rust target override)

	Why
	- The backend emits Rust for both user code and a subset of the stdlib.
	- Many parts of Haxe itself (macros, Reflaxe, std utilities) rely on `StringTools`.
	- Overriding `StringTools` in `std/` means this implementation is also used during macro-time
	  compilation, so it must include all members that Haxe/Reflaxe expect.

	What
	- Provides a pragmatic subset of Haxe 4.3.x `StringTools` needed by:
	  - the Rust backend's macro-time compilation (Reflaxe internals)
	  - the current Rust-target std overrides (`sys.Http` needs URL encoding + trimming)

	How
	- Most helpers are implemented in portable Haxe.
	- Runtime behavior stays in typed Haxe code so metal policy analysis can enforce compiler
	  contracts without raw expression fallback noise.

	Notes
	- This file intentionally avoids depending on other std modules which are not yet overridden and
	  therefore would not be emitted into Rust output.
**/
class StringTools {
	/**
		Encode an URL using a standard percent-encoding format.

		On the Rust target, this percent-encodes the UTF-8 bytes of the input string
		(space becomes `%20`).
	**/
	public static function urlEncode(s:String):String {
		var bytes = haxe.io.Bytes.ofString(s);
		var out = new StringBuf();
		for (i in 0...bytes.length) {
			var b = bytes.get(i);
			var isUnreserved = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F || b == 0x2E
				|| b == 0x7E;
			if (isUnreserved) {
				out.addChar(b);
			} else if (b == 0x20) {
				out.add("%20");
			} else {
				out.add("%");
				out.add(hex(b, 2));
			}
		}
		return out.toString();
	}

	/**
		Decode an URL using the standard format.

		On the Rust target, this:
		- replaces `+` with space
		- percent-decodes `%HH` sequences into bytes
		- interprets the resulting bytes as UTF-8 (lossy on invalid sequences)
	**/
	public static function urlDecode(s:String):String {
		var input = replace(s, "+", " ");
		var bytes:Array<Int> = [];
		var i = 0;
		while (i < input.length) {
			var c = input.substr(i, 1);
			if (c == "%" && i + 2 < input.length) {
				var hi:Int = hexDigitValue(input.substr(i + 1, 1));
				var lo:Int = hexDigitValue(input.substr(i + 2, 1));
				if (hi >= 0 && lo >= 0) {
					bytes.push((hi << 4) | lo);
					i += 3;
					continue;
				}
			}

			var chunk = haxe.io.Bytes.ofString(input.charAt(i));
			for (j in 0...chunk.length)
				bytes.push(chunk.get(j));
			i++;
		}

		var out = haxe.io.Bytes.alloc(bytes.length);
		for (index in 0...bytes.length)
			out.set(index, bytes[index]);
		return out.toString();
	}

	/**
		Returns `true` if `s` contains `value`.
	**/
	public static inline function contains(s:String, value:String):Bool {
		return s.indexOf(value) != -1;
	}

	/**
		Tells if `s` starts with `start`.
	**/
	public static function startsWith(s:String, start:String):Bool {
		return (s.length >= start.length && s.indexOf(start, 0) == 0);
	}

	/**
		Tells if `s` ends with `end`.
	**/
	public static function endsWith(s:String, end:String):Bool {
		var elen = end.length;
		var slen = s.length;
		return (slen >= elen && s.indexOf(end, (slen - elen)) == (slen - elen));
	}

	/**
		Tells if the character in `s` at `pos` is a space.

		A character is considered space if its code is 9,10,11,12,13 or 32.
	**/
	public static function isSpace(s:String, pos:Int):Bool {
		if (s.length == 0 || pos < 0 || pos >= s.length)
			return false;
		var c = fastCodeAt(s, pos);
		return (c > 8 && c < 14) || c == 32;
	}

	/**
		Removes leading space characters of `s`.
	**/
	public static function ltrim(s:String):String {
		var l = s.length;
		var r = 0;
		while (r < l && isSpace(s, r))
			r++;
		return (r > 0) ? s.substr(r, l - r) : s;
	}

	/**
		Removes trailing space characters of `s`.
	**/
	public static function rtrim(s:String):String {
		var l = s.length;
		var r = 0;
		while (r < l && isSpace(s, l - r - 1))
			r++;
		return (r > 0) ? s.substr(0, l - r) : s;
	}

	/**
		Removes leading and trailing space characters of `s`.
	**/
	public static inline function trim(s:String):String {
		return ltrim(rtrim(s));
	}

	/**
		Concatenates `c` to `s` until `s.length` is at least `l`.
	**/
	public static function lpad(s:String, c:String, l:Int):String {
		if (c.length <= 0)
			return s;
		var padLen = l - s.length;
		if (padLen <= 0)
			return s;
		var buf = "";
		while (buf.length < padLen)
			buf += c;
		return buf + s;
	}

	/**
		Appends `c` to `s` until `s.length` is at least `l`.
	**/
	public static function rpad(s:String, c:String, l:Int):String {
		if (c.length <= 0)
			return s;
		if (l <= s.length)
			return s;
		var out = s;
		while (out.length < l)
			out += c;
		return out;
	}

	/**
		Replace all occurrences of `sub` in `s` by `by`.
	**/
	public static function replace(s:String, sub:String, by:String):String {
		return s.split(sub).join(by);
	}

	/**
		Encodes `n` into an uppercase hexadecimal representation.
	**/
	public static function hex(n:Int, ?digits:Int):String {
		#if !macro
		return NativeString.hexUpper(n, digits);
		#end

		var s = "";
		var hexChars = "0123456789ABCDEF";
		var v = n;
		do {
			s = hexChars.charAt(v & 15) + s;
			v = v >>> 4;
		} while (v > 0);

		var d = digits == null ? 0 : digits;
		if (d != 0)
			while (s.length < d)
				s = "0" + s;
		return s;
	}

	/**
		Returns a character code at `index`, or an EOF indicator when `index == s.length`.

		This is a portability helper used by std parsers and macro code.
	**/
	public static function fastCodeAt(s:String, index:Int):Int {
		#if macro
		if (index < 0 || index >= s.length)
			return -1;
		var code:Null<Int> = s.charCodeAt(index);
		return code == null ? -1 : code;
		#else
		return NativeString.fastCodeAtOrEof(s, index);
		#end
	}

	static inline function hexDigitValue(ch:String):Int {
		return if (ch == "0") 0; else if (ch == "1") 1; else if (ch == "2") 2; else if (ch == "3") 3; else if (ch == "4") 4; else if (ch == "5") 5; else
			if (ch == "6") 6; else if (ch == "7") 7; else if (ch == "8") 8; else if (ch == "9") 9; else if (ch == "a"
			|| ch == "A") 10; else if (ch == "b" || ch == "B") 11; else if (ch == "c" || ch == "C") 12; else if (ch == "d" || ch == "D") 13; else if (ch == "e"
			|| ch == "E") 14; else if (ch == "f" || ch == "F") 15; else -1;
	}

	/**
		Unsafe variant of `fastCodeAt` (index must be valid).
	**/
	public static inline function unsafeCodeAt(s:String, index:Int):Int {
		return fastCodeAt(s, index);
	}

	/**
		Tells if `c` represents EOF for `fastCodeAt`.
	**/
	@:noUsing public static inline function isEof(c:Int):Bool {
		return c == -1;
	}

	/**
		Returns an iterator of char codes.
	**/
	public static inline function iterator(s:String):StringIterator {
		return new StringIterator(s);
	}

	/**
		Returns an iterator of (index, code) pairs.
	**/
	public static inline function keyValueIterator(s:String):StringKeyValueIterator {
		return new StringKeyValueIterator(s);
	}

	#if utf16
	// Used by the Unicode string iterators in std.
	static inline var MIN_SURROGATE_CODE_POINT = 65536;

	static inline function utf16CodePointAt(s:String, index:Int):Int {
		var c = StringTools.fastCodeAt(s, index);
		if (c >= 0xD800 && c <= 0xDBFF) {
			c = ((c - 0xD7C0) << 10) | (StringTools.fastCodeAt(s, index + 1) & 0x3FF);
		}
		return c;
	}
	#end
}
