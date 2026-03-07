package haxe;

/**
 * `haxe.Int32` (Rust target override)
 *
 * Why:
 * - `haxe.Int64` and adjacent stdlib helpers rely on 32-bit word arithmetic with wraparound
 *   semantics. Plain Rust `i32` operators panic on overflow in debug builds, which breaks those
 *   algorithms even when the intended result is the wrapped two's-complement value.
 * - The Rust target only emits local `std/` overrides, so we need an emitted `haxe.Int32`
 *   surface instead of relying on upstream files that are only used for typing.
 *
 * What:
 * - A transitive abstract over `Int` that exposes the fixed-width operator behavior needed by
 *   `haxe.Int64`.
 * - Typed wrapping operators for add/sub/mul/neg plus unsigned comparison.
 *
 * How:
 * - For Rust output, arithmetic routes through a tiny typed native helper (`Int32Native`) backed by
 *   `haxe/native/int32_tools.rs`.
 * - For non-Rust compile modes (macro/eval), pure-Haxe fallbacks keep the module typeable without
 *   requiring the Rust helper to exist.
 * - The abstract remains `from Int` / `to Int`, so existing Haxe code can keep using `Int`
 *   syntax while the Rust backend gets explicit fixed-width behavior where needed.
 */
@:transitive
abstract Int32(Int) from Int to Int {
	@:op(A + B) private static inline function add(a:Int32, b:Int32):Int32
		return wrappingAdd(a, b);

	@:op(A + B) @:commutative private static inline function addInt(a:Int32, b:Int):Int32
		return wrappingAdd(a, b);

	@:op(A - B) private static inline function sub(a:Int32, b:Int32):Int32
		return wrappingSub(a, b);

	@:op(A - B) private static inline function subInt(a:Int32, b:Int):Int32
		return wrappingSub(a, b);

	@:op(A - B) private static inline function intSub(a:Int, b:Int32):Int32
		return wrappingSub(a, b);

	@:op(A * B) private static inline function mul(a:Int32, b:Int32):Int32
		return wrappingMul(a, b);

	@:op(A * B) @:commutative private static inline function mulInt(a:Int32, b:Int):Int32
		return wrappingMul(a, b);

	@:op(-A) private static inline function neg(a:Int32):Int32
		return wrappingNeg(a);

	@:op(A < B) private static inline function lt(a:Int32, b:Int32):Bool
		return (a : Int) < (b : Int);

	@:op(A < B) private static inline function ltInt(a:Int32, b:Int):Bool
		return (a : Int) < b;

	@:op(A < B) private static inline function intLt(a:Int, b:Int32):Bool
		return a < (b:Int);

	@:op(A <= B) private static inline function lte(a:Int32, b:Int32):Bool
		return (a : Int) <= (b : Int);

	@:op(A <= B) private static inline function lteInt(a:Int32, b:Int):Bool
		return (a : Int) <= b;

	@:op(A <= B) private static inline function intLte(a:Int, b:Int32):Bool
		return a <= (b : Int);

	@:op(A > B) private static inline function gt(a:Int32, b:Int32):Bool
		return (a : Int) > (b : Int);

	@:op(A > B) private static inline function gtInt(a:Int32, b:Int):Bool
		return (a : Int) > b;

	@:op(A > B) private static inline function intGt(a:Int, b:Int32):Bool
		return a > (b : Int);

	@:op(A >= B) private static inline function gte(a:Int32, b:Int32):Bool
		return (a : Int) >= (b : Int);

	@:op(A >= B) private static inline function gteInt(a:Int32, b:Int):Bool
		return (a : Int) >= b;

	@:op(A >= B) private static inline function intGte(a:Int, b:Int32):Bool
		return a >= (b : Int);

	public static inline function wrappingAdd(a:Int32, b:Int32):Int32 {
		#if rust_output
		return Int32Native.wrappingAdd(a, b);
		#else
		return (a : Int) + (b : Int);
		#end
	}

	public static inline function wrappingSub(a:Int32, b:Int32):Int32 {
		#if rust_output
		return Int32Native.wrappingSub(a, b);
		#else
		return (a : Int) - (b : Int);
		#end
	}

	public static inline function wrappingMul(a:Int32, b:Int32):Int32 {
		#if rust_output
		return Int32Native.wrappingMul(a, b);
		#else
		return (a : Int) * (b : Int);
		#end
	}

	public static inline function wrappingNeg(a:Int32):Int32 {
		#if rust_output
		return Int32Native.wrappingNeg(a);
		#else
		return -(a : Int);
		#end
	}

	public static inline function ucompare(a:Int32, b:Int32):Int {
		#if rust_output
		return Int32Native.ucompare(a, b);
		#else
		if (a < 0)
			return b < 0 ? (~b - ~a) : 1;
		return b < 0 ? -1 : ((a : Int) - (b : Int));
		#end
	}
}

/**
 * Typed Rust boundary for fixed-width `Int32` operations.
 *
 * Why:
 * - Rust debug builds check `i32` overflow, while `haxe.Int64` expects 32-bit word arithmetic to
 *   wrap intentionally.
 *
 * What:
 * - A narrow helper surface for wrapping arithmetic and unsigned comparison.
 *
 * How:
 * - Bound to crate module `int32_tools` shipped via `@:rustExtraSrc`.
 * - Kept private so user code continues to depend on `haxe.Int32`, not a Rust-specific helper.
 */
@:native("crate::int32_tools::Int32Tools")
@:rustExtraSrc("haxe/native/int32_tools.rs")
private extern class Int32Native {
	@:native("wrapping_add")
	public static function wrappingAdd(a:Int, b:Int):Int;
	@:native("wrapping_sub")
	public static function wrappingSub(a:Int, b:Int):Int;
	@:native("wrapping_mul")
	public static function wrappingMul(a:Int, b:Int):Int;
	@:native("wrapping_neg")
	public static function wrappingNeg(a:Int):Int;
	public static function ucompare(a:Int, b:Int):Int;
}
