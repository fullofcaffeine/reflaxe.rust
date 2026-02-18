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
	static inline function fail(message:String):Void {
		throw new haxe.Exception(message);
	}

	public static function isTrue(value:Bool, message:String):Void {
		if (!value) {
			fail(message);
		}
	}

	public static function isFalse(value:Bool, message:String):Void {
		if (value) {
			fail(message);
		}
	}

	public static function equalsInt(expected:Int, actual:Int, message:String):Void {
		if (expected != actual) {
			fail(message + ": expected `" + expected + "`, got `" + actual + "`");
		}
	}

	public static function equalsString(expected:String, actual:String, message:String):Void {
		if (expected != actual) {
			fail(message + ": expected `" + expected + "`, got `" + actual + "`");
		}
	}

	public static function contains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) == -1) {
			fail(message + ": expected substring `" + needle + "`");
		}
	}

	public static function startsWith(value:String, prefixValue:String, message:String):Void {
		if (value.indexOf(prefixValue) != 0) {
			fail(message + ": expected prefix `" + prefixValue + "`");
		}
	}

	public static function lineCount(value:String, expected:Int, message:String):Void {
		var count = value.split("\n").length;
		if (count != expected) {
			fail(message + ": expected " + expected + " lines, got " + count);
		}
	}
}
