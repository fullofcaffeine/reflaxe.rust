package haxe;

/**
 * `haxe.Int64` (Rust target override, minimal)
 *
 * Why:
 * - Several std APIs (e.g. `haxe.io.BytesBuffer.addInt64` / `addDouble`) require a cross-platform
 *   "pair-of-i32" 64-bit integer representation.
 * - Haxe’s `haxe.Int64` is a `@:coreApi` type (declared as an `abstract` in the eval stdlib). Any
 *   target override must keep the same shape/signature so other std modules typecheck.
 *
 * What:
 * - A minimal `abstract Int64(__Int64)` with a backing `__Int64` class storing `(high, low)` words.
 *
 * How:
 * - Most operations are intentionally not implemented yet; add them as needed by the runtime/std.
 * - The backing class is a regular Haxe class and will be lowered to an `HxRef<__Int64>` on this
 *   target.
 */
@:transitive
abstract Int64(__Int64) from __Int64 to __Int64 {
	private inline function new(x: __Int64) {
		this = x;
	}

	public var high(get, never): Int;
	public var low(get, never): Int;

	private inline function get_high(): Int return this.high;
	private inline function get_low(): Int return this.low;

	/**
		Construct an Int64 from its high/low 32-bit parts.
	**/
	public static inline function make(high: Int, low: Int): Int64 {
		return new Int64(new __Int64(high, low));
	}

	/**
		Returns an `Int64` with the value of the Int `x` (sign-extended to 64 bits).
	**/
	@:from public static inline function ofInt(x: Int): Int64 {
		return make(x >> 31, x);
	}

	/**
		Makes a copy of `this` Int64.
	**/
	public inline function copy(): Int64 {
		return make(high, low);
	}
}

private class __Int64 {
	public var high: Int;
	public var low: Int;

	public inline function new(high: Int, low: Int) {
		this.high = high;
		this.low = low;
	}
}
