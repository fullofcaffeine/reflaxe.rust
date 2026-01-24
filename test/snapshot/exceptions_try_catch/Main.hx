class Main {
	static function main(): Void {
		var x = try {
			if (true) throw "boom";
			1;
		} catch (e: String) {
			2;
		}

		trace(x);

		var y = try {
			try {
				if (true) throw 7;
				0;
			} catch (e: Int) {
				throw "inner";
			}
		} catch (e: String) {
			42;
		}

		trace(y);
	}
}

