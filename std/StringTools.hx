import haxe.iterators.StringIterator;
import haxe.iterators.StringKeyValueIterator;

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
	- A few operations use Rust intrinsics via `__rust__` on the target (non-macro) side to avoid
	  pulling in additional std modules that we don't emit yet.

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
		#if macro
		// Macro-time: rely on the host platform std (Eval) behavior by falling back to `String` ops.
		// This is "good enough" for macros and avoids target-specific behavior.
		//
		// NOTE: We purposely do not attempt full standards compliance here.
		return replace(s, " ", "%20");
		#else
		return untyped __rust__(
			"{
				let bytes = {0}.as_bytes();
				let mut out = String::new();
				for &b in bytes {
					match b {
						b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
						b' ' => out.push_str(\"%20\"),
						_ => out.push_str(&format!(\"%{:02X}\", b)),
					}
				}
				out
			}",
			s
		);
		#end
	}

	/**
		Decode an URL using the standard format.

		On the Rust target, this:
		- replaces `+` with space
		- percent-decodes `%HH` sequences into bytes
		- interprets the resulting bytes as UTF-8 (lossy on invalid sequences)
	**/
	public static function urlDecode(s:String):String {
		#if macro
		// Macro-time: keep this minimal but compatible with the common `%20`/`+` cases used by
		// serializer/unserializer and basic tooling.
		return replace(replace(s, "+", " "), "%20", " ");
		#else
		return untyped __rust__(
			"{
				fn hex_val(b: u8) -> Option<u8> {
					match b {
						b'0'..=b'9' => Some(b - b'0'),
						b'a'..=b'f' => Some(b - b'a' + 10),
						b'A'..=b'F' => Some(b - b'A' + 10),
						_ => None,
					}
				}

				let input = {0}.replace(\"+\", \" \");
				let bytes = input.as_bytes();
				let mut out: Vec<u8> = Vec::with_capacity(bytes.len());

				let mut i: usize = 0;
				while i < bytes.len() {
					if bytes[i] == b'%' && i + 2 < bytes.len() {
						let h1 = hex_val(bytes[i + 1]);
						let h2 = hex_val(bytes[i + 2]);
						if let (Some(a), Some(b)) = (h1, h2) {
							out.push((a << 4) | b);
							i += 3;
							continue;
						}
					}
					out.push(bytes[i]);
					i += 1;
				}

				String::from_utf8(out.clone()).unwrap_or_else(|_| String::from_utf8_lossy(&out).to_string())
			}",
			s
		);
		#end
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
	public static inline function startsWith(s:String, start:String):Bool {
		#if macro
		return (s.length >= start.length && s.indexOf(start, 0) == 0);
		#else
		return untyped __rust__("{0}.starts_with({1}.as_str())", s, start);
		#end
	}

	/**
		Tells if `s` ends with `end`.
	**/
	public static inline function endsWith(s:String, end:String):Bool {
		#if macro
		var elen = end.length;
		var slen = s.length;
		return (slen >= elen && s.indexOf(end, (slen - elen)) == (slen - elen));
		#else
		return untyped __rust__("{0}.ends_with({1}.as_str())", s, end);
		#end
	}

	/**
		Tells if the character in `s` at `pos` is a space.

		A character is considered space if its code is 9,10,11,12,13 or 32.
	**/
	public static function isSpace(s:String, pos:Int):Bool {
		if (s.length == 0 || pos < 0 || pos >= s.length) return false;
		var c = fastCodeAt(s, pos);
		return (c > 8 && c < 14) || c == 32;
	}

	/**
		Removes leading space characters of `s`.
	**/
	public static function ltrim(s:String):String {
		var l = s.length;
		var r = 0;
		while (r < l && isSpace(s, r)) r++;
		return (r > 0) ? s.substr(r, l - r) : s;
	}

	/**
		Removes trailing space characters of `s`.
	**/
	public static function rtrim(s:String):String {
		var l = s.length;
		var r = 0;
		while (r < l && isSpace(s, l - r - 1)) r++;
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
		if (c.length <= 0) return s;
		var padLen = l - s.length;
		if (padLen <= 0) return s;
		#if macro
		var buf = "";
		while (buf.length < padLen) buf += c;
		return buf + s;
		#else
		return untyped __rust__(
			"{
				let mut buf = String::new();
				let mut cur: i32 = 0;
				while cur < {2} {
					buf.push_str({1}.as_str());
					cur = hxrt::string::len(buf.as_str());
				}
				format!(\"{}{}\", buf, {0})
			}",
			s,
			c,
			padLen
		);
		#end
	}

	/**
		Appends `c` to `s` until `s.length` is at least `l`.
	**/
	public static function rpad(s:String, c:String, l:Int):String {
		if (c.length <= 0) return s;
		if (l <= s.length) return s;
		#if macro
		var out = s;
		while (out.length < l) out += c;
		return out;
		#else
		var padLen = l - s.length;
		return untyped __rust__(
			"{
				let mut buf = String::new();
				let mut cur: i32 = 0;
				while cur < {2} {
					buf.push_str({1}.as_str());
					cur = hxrt::string::len(buf.as_str());
				}
				format!(\"{}{}\", {0}, buf)
			}",
			s,
			c,
			padLen
		);
		#end
	}

	/**
		Replace all occurrences of `sub` in `s` by `by`.
	**/
	public static function replace(s:String, sub:String, by:String):String {
		#if macro
		return s.split(sub).join(by);
		#else
		return untyped __rust__("{0}.replace({1}.as_str(), {2}.as_str())", s, sub, by);
		#end
	}

	/**
		Encodes `n` into an uppercase hexadecimal representation.
	**/
	public static function hex(n:Int, ?digits:Int):String {
		#if !macro
		return untyped __rust__(
			"{
				let mut s = format!(\"{:X}\", {0} as u32);
				let d: i32 = {1}.unwrap_or(0);
				while d != 0 && (hxrt::string::len(s.as_str()) < d) {
					s = format!(\"0{}\", s);
				}
				s
			}",
			n,
			digits
		);
		#end

		var s = "";
		var hexChars = "0123456789ABCDEF";
		var v = n;
		do {
			s = hexChars.charAt(v & 15) + s;
			v = v >>> 4;
		} while (v > 0);

		var d = digits == null ? 0 : digits;
		if (d != 0) while (s.length < d) s = "0" + s;
		return s;
	}

	/**
		Returns a character code at `index`, or an EOF indicator when `index == s.length`.

		This is a portability helper used by std parsers and macro code.
	**/
	public static function fastCodeAt(s:String, index:Int):Int {
		#if macro
		return (index < s.length) ? s.charCodeAt(index) : -1;
		#else
		// Rust target: interpret index as a Unicode scalar index (consistent with other string intrinsics here).
		return untyped __rust__(
			"{0}.chars().nth({1} as usize).map(|c| c as i32).unwrap_or(-1)",
			s,
			index
		);
		#end
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
