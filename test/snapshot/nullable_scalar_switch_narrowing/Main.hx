class Main {
	static function readExit(value:Null<Int>):Null<Int> {
		return value;
	}

	static function closeSource():Void {}

	static function narrowRead(value:Null<Int>):Int {
		try {
			final exit = readExit(value);
			closeSource();
			final concreteExit:Int = switch (exit) {
				case null: -1;
				case concrete: concrete;
			}
			return concreteExit;
		} catch (_:haxe.Exception) {
			return -2;
		}
	}

	static function narrow(value:Null<Int>):Int {
		return switch (value) {
			case null: -1;
			case concrete: concrete;
		};
	}

	static function narrowFloat(value:Null<Float>):Float {
		return switch (value) {
			case null: -1.5;
			case concrete: concrete;
		};
	}

	static function main():Void {
		if (narrowRead(9) != 9) throw "read narrowing failed";
		if (narrowRead(null) != -1) throw "null read narrowing failed";
		if (narrow(7) != 7) throw "non-null narrowing failed";
		if (narrow(null) != -1) throw "null narrowing failed";
		if (narrowFloat(2.5) != 2.5) throw "non-null Float narrowing failed";
		if (narrowFloat(null) != -1.5) throw "null Float narrowing failed";
	}
}
