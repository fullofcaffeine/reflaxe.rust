class Main {
	static function parse(value:String):GenericParse<String> {
		if (value.length == 0) {
			return Missing("empty");
		}
		return Parsed(value);
	}

	static function describe(result:GenericParse<String>):String {
		return switch (result) {
			case Parsed(value): "parsed:" + value;
			case Missing(reason): "missing:" + reason;
		}
	}

	static function main() {
		Sys.println(describe(parse("abc")));
		Sys.println(describe(parse("")));
	}
}
