class Main {
	static function assertParsed(label:String, value:String, expected:Null<Int>):Void {
		var parsed = Std.parseInt(value);
		if (parsed != expected)
			throw label;
		Sys.println(label + "=ok");
	}

	static function main():Void {
		assertParsed("decimal", "123", 123);
		assertParsed("leading-space", " 123", 123);
		assertParsed("trailing-junk", "123abc", 123);
		assertParsed("negative", "-42", -42);
		assertParsed("positive", "+7", 7);
		assertParsed("hex", "0x10", 16);
		assertParsed("negative-hex", "-0x10", -16);
		assertParsed("upper-hex", "0X10zz", 16);
		assertParsed("leading-zero", "010", 10);
		assertParsed("empty", "", null);
		assertParsed("invalid", "abc", null);
		assertParsed("bare-sign", "-", null);
		assertParsed("whitespace-only", "  ", null);
		assertParsed("float-prefix", "12.9", 12);
		assertParsed("negative-float-prefix", "-12.9", -12);
		assertParsed("overflow-positive", "2147483648", null);
		assertParsed("overflow-negative", "-2147483649", null);
	}
}
