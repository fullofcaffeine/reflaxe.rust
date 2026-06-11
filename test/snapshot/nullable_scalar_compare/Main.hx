class Main {
	static function assertEq(label:String, actual:Bool, expected:Bool):Void {
		if (actual != expected)
			throw label;
		Sys.println(label + "=ok");
	}

	static function parsed(value:String):Null<Int> {
		return Std.parseInt(value);
	}

	static function maybeFloat(value:Bool):Null<Float> {
		return value ? 1.5 : null;
	}

	static function main():Void {
		var some = parsed("42");
		var none = parsed("nope");
		assertEq("some-lte", some <= 42, true);
		assertEq("some-gt", some > 41, true);
		assertEq("none-lte", none <= 0, false);
		assertEq("plain-lt-some", 41 < some, true);
		assertEq("plain-lt-none", 0 < none, false);
		assertEq("nullable-int-lt-float", some < 42.5, true);
		assertEq("float-lt-nullable-int", 41.5 < some, true);
		assertEq("nullable-float-gt-int", maybeFloat(true) > 1, true);
		assertEq("nullable-float-none", maybeFloat(false) > 1, false);
	}
}
