class Main {
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
		if (narrow(7) != 7) throw "non-null narrowing failed";
		if (narrow(null) != -1) throw "null narrowing failed";
		if (narrowFloat(2.5) != 2.5) throw "non-null Float narrowing failed";
		if (narrowFloat(null) != -1.5) throw "null Float narrowing failed";
	}
}
