package haxe;

using haxe.Int64;

import StringTools;

/**
 * Helper routines for `haxe.Int64`.
 *
 * Why:
 * - Upstream `haxe.Int64` delegates parsing and float conversion to a helper module so the core
 *   abstract stays focused on arithmetic and operators.
 * - Keeping the same split on the Rust target reduces drift and keeps upstream parity work
 *   reviewable.
 *
 * What:
 * - Portable Haxe implementations of `parseString` and `fromFloat`.
 *
 * How:
 * - These methods intentionally stay in Haxe rather than crossing into Rust runtime helpers.
 *   They rely only on the public `haxe.Int64` API, so they remain backend-portable and exercise the
 *   same semantic surface users rely on.
 */
class Int64Helper {
	public static function parseString(sParam:String):Int64 {
		var base = Int64.ofInt(10);
		var current = Int64.ofInt(0);
		var multiplier = Int64.ofInt(1);
		var sIsNegative = false;

		var s = StringTools.trim(sParam);
		if (StringTools.startsWith(s, "-")) {
			sIsNegative = true;
			s = s.substr(1);
		}
		var len = s.length;

		for (i in 0...len) {
			var digitInt = StringTools.fastCodeAt(s, len - 1 - i) - '0'.code;

			if (digitInt < 0 || digitInt > 9)
				throw "NumberFormatError";

			if (digitInt != 0) {
				var digit:Int64 = Int64.ofInt(digitInt);
				if (sIsNegative) {
					current = Int64.sub(current, Int64.mul(multiplier, digit));
					if (!Int64.isNeg(current))
						throw "NumberFormatError: Underflow";
				} else {
					current = Int64.add(current, Int64.mul(multiplier, digit));
					if (Int64.isNeg(current))
						throw "NumberFormatError: Overflow";
				}
			}

			multiplier = Int64.mul(multiplier, base);
		}
		return current;
	}

	public static function fromFloat(f:Float):Int64 {
		if (Math.isNaN(f) || !Math.isFinite(f))
			throw "Number is NaN or Infinite";

		var noFractions = f - (f % 1);

		if (noFractions > 9007199254740991)
			throw "Conversion overflow";
		if (noFractions < -9007199254740991)
			throw "Conversion underflow";

		var result = Int64.ofInt(0);
		var neg = noFractions < 0;
		var rest = neg ? -noFractions : noFractions;

		var i = 0;
		while (rest >= 1) {
			var curr = rest % 2;
			rest = rest / 2;
			if (curr >= 1)
				result = Int64.add(result, Int64.shl(Int64.ofInt(1), i));
			i++;
		}

		if (neg)
			result = Int64.neg(result);
		return result;
	}
}
