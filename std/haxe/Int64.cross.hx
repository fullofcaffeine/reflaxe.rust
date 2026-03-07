package haxe;

using haxe.Int64;

/**
 * `haxe.Int64` (Rust target override)
 *
 * Why:
 * - `haxe.Int64` is part of the portable Haxe numeric contract. Upstream stdlib code, `Bytes`,
 *   serializers, crypto helpers, and user code all expect the full abstract surface: arithmetic,
 *   shifts, comparisons, parsing, string conversion, and `divMod`.
 * - The earlier Rust override only exposed `make`, `ofInt`, and `copy`, which allowed a few std
 *   types to typecheck but broke real `Int64` usage immediately.
 * - For parity, the Rust target keeps the same Haxe-level API and semantics as upstream while using
 *   a regular backing class that lowers cleanly to the Rust heap model.
 *
 * What:
 * - A transitive abstract `Int64(__Int64)` matching the upstream public API.
 * - `__Int64` is a small backing class storing the `(high, low)` 32-bit words.
 * - The abstract implements the portable operator/utility surface in Haxe so the compiler lowers
 *   those operations through normal typed-ast paths instead of requiring special Rust intrinsics.
 *
 * How:
 * - This file mirrors upstream `std/haxe/Int64.hx` closely, with only target-irrelevant branches
 *   removed. That keeps semantics stable and makes future upstream diff reviews straightforward.
 * - `toString()` stays on the abstract and the backing class forwards to it so `Std.string`,
 *   `trace`, and direct string interpolation all share the same decimal formatting path.
 * - Parsing and float conversion live in `std/haxe/Int64Helper.cross.hx`, matching upstream
 *   structure and keeping the core arithmetic logic here focused.
 *
 * Design notes:
 * - We intentionally keep this logic in typed Haxe rather than writing a Rust-native `i64` extern
 *   wrapper. The contract is portable-first and must behave like upstream Haxe across backends.
 * - The backing class being an ordinary Haxe class means the compiler can represent values as the
 *   normal `HxRef<...>` heap object without a bespoke runtime encoding.
 */
@:transitive
abstract Int64(__Int64) from __Int64 to __Int64 {
	private inline function new(x:__Int64)
		this = x;

	public inline function copy():Int64
		return make(high, low);

	public static inline function make(high:Int32, low:Int32):Int64
		return new Int64(new __Int64(high, low));

	@:from public static inline function ofInt(x:Int):Int64
		return make(x >> 31, x);

	public static inline function toInt(x:Int64):Int {
		if (x.high != x.low >> 31)
			throw "Overflow";

		return x.low;
	}

	@:deprecated("haxe.Int64.is() is deprecated. Use haxe.Int64.isInt64() instead")
	inline public static function is(val:Dynamic):Bool {
		return isInt64(val);
	}

	inline public static function isInt64(val:Dynamic):Bool
		return Std.isOfType(val, __Int64);

	@:deprecated("Use high instead")
	public static inline function getHigh(x:Int64):Int32
		return x.high;

	@:deprecated("Use low instead")
	public static inline function getLow(x:Int64):Int32
		return x.low;

	public static inline function isNeg(x:Int64):Bool
		return x.high < 0;

	public static inline function isZero(x:Int64):Bool
		return x == 0;

	public static inline function compare(a:Int64, b:Int64):Int {
		var v = a.high - b.high;
		v = if (v != 0) v else Int32.ucompare(a.low, b.low);
		return a.high < 0 ? (b.high < 0 ? v : -1) : (b.high >= 0 ? v : 1);
	}

	public static inline function ucompare(a:Int64, b:Int64):Int {
		var v = Int32.ucompare(a.high, b.high);
		return if (v != 0) v else Int32.ucompare(a.low, b.low);
	}

	public static inline function toStr(x:Int64):String
		return x.toString();

	public function toString():String {
		var i:Int64 = cast this;
		if (i == 0)
			return "0";
		var str = "";
		var neg = false;
		if (i.isNeg()) {
			neg = true;
		}
		var ten:Int64 = 10;
		while (i != 0) {
			var r = i.divMod(ten);
			if (r.modulus.isNeg()) {
				str = Int64.neg(r.modulus).low + str;
				i = Int64.neg(r.quotient);
			} else {
				str = r.modulus.low + str;
				i = r.quotient;
			}
		}
		if (neg)
			str = "-" + str;
		return str;
	}

	public static inline function parseString(sParam:String):Int64 {
		return Int64Helper.parseString(sParam);
	}

	public static inline function fromFloat(f:Float):Int64 {
		return Int64Helper.fromFloat(f);
	}

	public static function divMod(dividend:Int64, divisor:Int64):{quotient:Int64, modulus:Int64} {
		if (divisor.high == 0) {
			switch (divisor.low) {
				case 0:
					throw "divide by zero";
				case 1:
					return {quotient: dividend.copy(), modulus: 0};
			}
		}

		var divSign = dividend.isNeg() != divisor.isNeg();

		var modulus = dividend.isNeg() ? -dividend : dividend.copy();
		divisor = divisor.isNeg() ? -divisor : divisor;

		var quotient:Int64 = 0;
		var mask:Int64 = 1;

		while (!divisor.isNeg()) {
			var cmp = ucompare(divisor, modulus);
			divisor <<= 1;
			mask <<= 1;
			if (cmp >= 0)
				break;
		}

		while (mask != 0) {
			if (ucompare(modulus, divisor) >= 0) {
				quotient |= mask;
				modulus -= divisor;
			}
			mask >>>= 1;
			divisor >>>= 1;
		}

		if (divSign)
			quotient = -quotient;
		if (dividend.isNeg())
			modulus = -modulus;

		return {
			quotient: quotient,
			modulus: modulus
		};
	}

	@:op(-A) public static inline function neg(x:Int64):Int64 {
		var high = ~x.high;
		var low = -x.low;
		if (low == 0)
			high++;
		return make(high, low);
	}

	@:op(++A) private inline function preIncrement():Int64 {
		this = copy();
		this.low++;
		if (this.low == 0)
			this.high++;
		return cast this;
	}

	@:op(A++) private inline function postIncrement():Int64 {
		var ret = this;
		preIncrement();
		return ret;
	}

	@:op(--A) private inline function preDecrement():Int64 {
		this = copy();
		if (this.low == 0)
			this.high--;
		this.low--;
		return cast this;
	}

	@:op(A--) private inline function postDecrement():Int64 {
		var ret = this;
		preDecrement();
		return ret;
	}

	@:op(A + B) public static inline function add(a:Int64, b:Int64):Int64 {
		var high = a.high + b.high;
		var low = a.low + b.low;
		if (Int32.ucompare(low, a.low) < 0)
			high++;
		return make(high, low);
	}

	@:op(A + B) @:commutative private static inline function addInt(a:Int64, b:Int):Int64
		return add(a, b);

	@:op(A - B) public static inline function sub(a:Int64, b:Int64):Int64 {
		var high = a.high - b.high;
		var low = a.low - b.low;
		if (Int32.ucompare(a.low, b.low) < 0)
			high--;
		return make(high, low);
	}

	@:op(A - B) private static inline function subInt(a:Int64, b:Int):Int64
		return sub(a, b);

	@:op(A - B) private static inline function intSub(a:Int, b:Int64):Int64
		return sub(a, b);

	@:op(A * B) public static inline function mul(a:Int64, b:Int64):Int64 {
		var mask = 0xFFFF;
		var al = a.low & mask, ah = a.low >>> 16;
		var bl = b.low & mask, bh = b.low >>> 16;
		var p00 = al * bl;
		var p10 = ah * bl;
		var p01 = al * bh;
		var p11 = ah * bh;
		var low = p00;
		var high = p11 + (p01 >>> 16) + (p10 >>> 16);
		p01 <<= 16;
		low += p01;
		if (Int32.ucompare(low, p01) < 0)
			high++;
		p10 <<= 16;
		low += p10;
		if (Int32.ucompare(low, p10) < 0)
			high++;
		high += a.low * b.high + a.high * b.low;
		return make(high, low);
	}

	@:op(A * B) @:commutative private static inline function mulInt(a:Int64, b:Int):Int64
		return mul(a, b);

	@:op(A / B) public static inline function div(a:Int64, b:Int64):Int64
		return divMod(a, b).quotient;

	@:op(A / B) private static inline function divInt(a:Int64, b:Int):Int64
		return div(a, b);

	@:op(A / B) private static inline function intDiv(a:Int, b:Int64):Int
		return div(a, b).toInt();

	@:op(A % B) public static inline function mod(a:Int64, b:Int64):Int64
		return divMod(a, b).modulus;

	@:op(A % B) private static inline function modInt(a:Int64, b:Int):Int
		return mod(a, b).toInt();

	@:op(A % B) private static inline function intMod(a:Int, b:Int64):Int
		return mod(a, b).toInt();

	@:op(A == B) public static inline function eq(a:Int64, b:Int64):Bool
		return a.high == b.high && a.low == b.low;

	@:op(A == B) @:commutative private static inline function eqInt(a:Int64, b:Int):Bool
		return eq(a, b);

	@:op(A != B) public static inline function neq(a:Int64, b:Int64):Bool
		return a.high != b.high || a.low != b.low;

	@:op(A != B) @:commutative private static inline function neqInt(a:Int64, b:Int):Bool
		return neq(a, b);

	@:op(A < B) private static inline function lt(a:Int64, b:Int64):Bool
		return compare(a, b) < 0;

	@:op(A < B) private static inline function ltInt(a:Int64, b:Int):Bool
		return lt(a, b);

	@:op(A < B) private static inline function intLt(a:Int, b:Int64):Bool
		return lt(a, b);

	@:op(A <= B) private static inline function lte(a:Int64, b:Int64):Bool
		return compare(a, b) <= 0;

	@:op(A <= B) private static inline function lteInt(a:Int64, b:Int):Bool
		return lte(a, b);

	@:op(A <= B) private static inline function intLte(a:Int, b:Int64):Bool
		return lte(a, b);

	@:op(A > B) private static inline function gt(a:Int64, b:Int64):Bool
		return compare(a, b) > 0;

	@:op(A > B) private static inline function gtInt(a:Int64, b:Int):Bool
		return gt(a, b);

	@:op(A > B) private static inline function intGt(a:Int, b:Int64):Bool
		return gt(a, b);

	@:op(A >= B) private static inline function gte(a:Int64, b:Int64):Bool
		return compare(a, b) >= 0;

	@:op(A >= B) private static inline function gteInt(a:Int64, b:Int):Bool
		return gte(a, b);

	@:op(A >= B) private static inline function intGte(a:Int, b:Int64):Bool
		return gte(a, b);

	@:op(~A) private static inline function complement(a:Int64):Int64
		return make(~a.high, ~a.low);

	@:op(A & B) public static inline function and(a:Int64, b:Int64):Int64
		return make(a.high & b.high, a.low & b.low);

	@:op(A | B) public static inline function or(a:Int64, b:Int64):Int64
		return make(a.high | b.high, a.low | b.low);

	@:op(A ^ B) public static inline function xor(a:Int64, b:Int64):Int64
		return make(a.high ^ b.high, a.low ^ b.low);

	@:op(A << B) public static inline function shl(a:Int64, b:Int):Int64 {
		b &= 63;
		return if (b == 0) a.copy() else if (b < 32) make((a.high << b) | (a.low >>> (32 - b)), a.low << b) else make(a.low << (b - 32), 0);
	}

	@:op(A >> B) public static inline function shr(a:Int64, b:Int):Int64 {
		b &= 63;
		return if (b == 0) a.copy() else if (b < 32) make(a.high >> b, (a.high << (32 - b)) | (a.low >>> b)) else make(a.high >> 31, a.high >> (b - 32));
	}

	@:op(A >>> B) public static inline function ushr(a:Int64, b:Int):Int64 {
		b &= 63;
		return if (b == 0) a.copy() else if (b < 32) make(a.high >>> b, (a.high << (32 - b)) | (a.low >>> b)) else make(0, a.high >>> (b - 32));
	}

	public var high(get, never):Int32;

	private inline function get_high()
		return this.high;

	public var low(get, never):Int32;

	private inline function get_low()
		return this.low;
}

private typedef __Int64 = ___Int64;

private class ___Int64 {
	public var high:Int32;
	public var low:Int32;

	public inline function new(high, low) {
		this.high = high;
		this.low = low;
	}

	public function toString():String
		return Int64.toStr(cast this);
}
