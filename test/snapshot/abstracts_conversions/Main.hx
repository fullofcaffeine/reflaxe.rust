class Main {
	static function main(): Void {
		var a: Meters = 5;
		var b: Meters = 2.8;
		var c = a.add(b);
		var asInt: Int = c;
		trace(asInt);

		var col: Color = Red;
		var raw: Int = col;
		trace(raw);

		switch (col) {
			case Red: trace("r");
			case Green: trace("g");
			case Blue: trace("b");
			case _: trace("?");
		}
	}
}

