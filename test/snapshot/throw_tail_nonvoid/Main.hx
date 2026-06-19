class Main {
	static function decode(v:Int):Int {
		if (v == 0)
			return 10;
		throw "bad value";
	}

	static function label(v:Int):String {
		return switch (v) {
			case 1: "one";
			case _: throw "bad label";
		}
	}

	static function main():Void {
		Sys.println(decode(0));
		Sys.println(label(1));

		try {
			Sys.println(decode(1));
		} catch (e:String) {
			Sys.println("caught");
		}

		try {
			Sys.println(label(2));
		} catch (e:String) {
			Sys.println("caught label");
		}
	}
}
