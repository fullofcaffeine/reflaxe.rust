class Main {
	static function makeAdder(k: Int): Int->Int {
		return function(x: Int): Int return x + k;
	}

	static function main(): Void {
		var add10 = makeAdder(10);
		trace(add10(1));
	}
}

