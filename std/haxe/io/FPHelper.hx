package haxe.io;

import haxe.Int64;

/**
 * `haxe.io.FPHelper` (Rust target override)
 *
 * Why:
 * - Some std APIs (notably `BytesBuffer`) need to serialize floats/doubles using IEEE-754 bit
 *   patterns (e.g. `floatToI32`).
 *
 * What:
 * - Minimal float/double bit conversion helpers used by our std overrides.
 *
 * How:
 * - Implemented using `__rust__` as a *framework-only* escape hatch because Haxe does not provide a
 *   portable way to reinterpret floating-point bits.
 * - This keeps all injection usage inside `std/` and preserves the project rule that applications
 *   should not call `__rust__` directly.
 */
class FPHelper {
	// NOTE: When compiling a Rust target build we use `__rust__` for true bit-casts. For any other
	// compilation mode (including macro/eval), keep a pure-Haxe fallback so the stdlib can typecheck.

	#if !rust_output
	static inline var LN2 = 0.6931471805599453; // Math.log(2)

	static inline function _i32ToFloat(i: Int): Float {
		var sign = 1 - ((i >>> 31) << 1);
		var e = (i >> 23) & 0xff;
		if (e == 255) return (i & 0x7fffff) == 0 ? (sign > 0 ? Math.POSITIVE_INFINITY : Math.NEGATIVE_INFINITY) : Math.NaN;
		var m = e == 0 ? (i & 0x7fffff) << 1 : (i & 0x7fffff) | 0x800000;
		return sign * m * Math.pow(2, e - 150);
	}

	static inline function _i64ToDouble(lo: Int, hi: Int): Float {
		var sign = 1 - ((hi >>> 31) << 1);
		var e = (hi >> 20) & 0x7ff;
		if (e == 2047) return lo == 0 && (hi & 0xFFFFF) == 0 ? (sign > 0 ? Math.POSITIVE_INFINITY : Math.NEGATIVE_INFINITY) : Math.NaN;
		var m = 2.220446049250313e-16 * ((hi & 0xFFFFF) * 4294967296. + (lo >>> 31) * 2147483648. + (lo & 0x7FFFFFFF));
		m = e == 0 ? m * 2.0 : m + 1.0;
		return sign * m * Math.pow(2, e - 1023);
	}

	static inline function _floatToI32(f: Float): Int {
		if (f == 0) return 0;
		var af = f < 0 ? -f : f;
		var exp = Math.floor(Math.log(af) / LN2);
		if (exp > 127) return 0x7F800000;

		if (exp <= -127) {
			exp = -127;
			af *= 7.1362384635298e+44; // af * 0.5 * 0x800000 / Math.pow(2, -127)
		} else {
			af = (af / Math.pow(2, exp) - 1.0) * 0x800000;
		}
		return (f < 0 ? 0x80000000 : 0) | ((exp + 127) << 23) | Math.round(af);
	}

	static inline function _doubleToI64(v: Float): Int64 {
		if (v == 0) return Int64.make(0, 0);
		if (!Math.isFinite(v)) return Int64.make(v > 0 ? 0x7FF00000 : 0xFFF00000, 0);

		var av = v < 0 ? -v : v;
		var exp = Math.floor(Math.log(av) / LN2);
		if (exp > 1023) return Int64.make(0x7FEFFFFF, 0xFFFFFFFF);

		if (exp <= -1023) {
			exp = -1023;
			av = av / 2.2250738585072014e-308;
		} else {
			av = av / Math.pow(2, exp) - 1.0;
		}

		var sig = Math.fround(av * 4503599627370496.0); // 2^52
		var sig_l = Std.int(sig);
		var sig_h = Std.int(sig / 4294967296.0);
		var high = (v < 0 ? 0x80000000 : 0) | ((exp + 1023) << 20) | sig_h;
		return Int64.make(high, sig_l);
	}
	#end

	/**
		Reinterprets `v` as a 32-bit float and returns its IEEE-754 bit pattern.
	**/
	public static function floatToI32(v: Float): Int {
		#if rust_output
		return untyped __rust__("({0} as f32).to_bits() as i32", v);
		#else
		return _floatToI32(v);
		#end
	}

	/**
		Reinterprets `v` as an IEEE-754 32-bit float bit-pattern and returns it as a `Float`.
	**/
	public static function i32ToFloat(v: Int): Float {
		#if rust_output
		return untyped __rust__("f32::from_bits({0} as u32) as f64", v);
		#else
		return _i32ToFloat(v);
		#end
	}

	/**
		Reinterprets `v` as a 64-bit float and returns its IEEE-754 bit pattern as an `Int64`.
	**/
	public static function doubleToI64(v: Float): Int64 {
		#if rust_output
		var high = untyped __rust__("(({0}).to_bits() >> 32) as i32", v);
		var low = untyped __rust__("((({0}).to_bits() & 0xFFFF_FFFFu64) as u32) as i32", v);
		return Int64.make(high, low);
		#else
		return _doubleToI64(v);
		#end
	}

	/**
		Reinterprets the `(low, high)` 32-bit words as an IEEE-754 64-bit float.

		This matches Haxe std behavior: `FPHelper` always works in low-endian encoding, and callers
		(e.g. `haxe.io.Input.readDouble`) handle endianness by swapping argument order.
	**/
	public static function i64ToDouble(low: Int, high: Int): Float {
		#if rust_output
		return untyped __rust__(
			"f64::from_bits((({1} as u64) << 32) | (({0} as u32) as u64))",
			low,
			high
		);
		#else
		return _i64ToDouble(low, high);
		#end
	}
}
