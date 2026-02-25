package rust.test;

/**
	Typed assertion helpers for Haxe-authored Rust tests (`@:rustTest`).

	Why
	- `@:rustTest` lets us keep test logic in Haxe while emitting Rust `#[test]` wrappers.
	- Callers still need concise assertion helpers that fail with explicit messages.

	What
	- Provides small, strongly-typed assertion primitives (`isTrue`, `equalsInt`, `equalsString`, `contains`, etc.).
	- Throws `haxe.Exception` on failure so generated Rust tests fail through the normal panic path.

	How
	- Methods are static and side-effect free apart from failures.
	- No `Dynamic` usage: assertions stay fully typed and can be used in strict examples/tests.
**/
class Assert {
	public static function isTrue(value:Bool, message:String):Void {
		AssertNative.isTrue(value, message);
	}

	public static function isFalse(value:Bool, message:String):Void {
		AssertNative.isFalse(value, message);
	}

	public static function equalsInt(expected:Int, actual:Int, message:String):Void {
		AssertNative.equalsInt(expected, actual, message);
	}

	public static function equalsString(expected:String, actual:String, message:String):Void {
		AssertNative.equalsString(expected, actual, message);
	}

	public static function contains(haystack:String, needle:String, message:String):Void {
		AssertNative.contains(haystack, needle, message);
	}

	public static function startsWith(value:String, prefixValue:String, message:String):Void {
		AssertNative.startsWith(value, prefixValue, message);
	}

	public static function lineCount(value:String, expected:Int, message:String):Void {
		AssertNative.lineCount(value, expected, message);
	}
}

/**
	Typed native boundary for assertion failures.

	Why
	- Formatting rich assertion failure messages in Haxe generated avoidable raw fallback
	  expressions in metal profile outputs.
	- Tests only need deterministic pass/fail behavior and readable panic messages.

	How
	- Routes checks to a tiny Rust helper module that performs comparisons and panics with
	  descriptive messages.
	- Helper signatures are generic over `AsRef<str>` on the Rust side so this boundary stays
	  profile-safe (`String` in metal, `hxrt::string::HxString` in portable) without casts or
	  `Dynamic` fallback.
	- This keeps Haxe callsites typed and removes inline assertion formatting fallback.
**/
@:native("crate::assert_native")
@:rustExtraSrc("rust/test/native/assert_native.rs")
private extern class AssertNative {
	@:native("is_true")
	public static function isTrue(value:Bool, message:String):Void;
	@:native("is_false")
	public static function isFalse(value:Bool, message:String):Void;
	@:native("equals_int")
	public static function equalsInt(expected:Int, actual:Int, message:String):Void;
	@:native("equals_string")
	public static function equalsString(expected:String, actual:String, message:String):Void;
	public static function contains(haystack:String, needle:String, message:String):Void;
	@:native("starts_with")
	public static function startsWith(value:String, prefixValue:String, message:String):Void;
	@:native("line_count")
	public static function lineCount(value:String, expected:Int, message:String):Void;
}
