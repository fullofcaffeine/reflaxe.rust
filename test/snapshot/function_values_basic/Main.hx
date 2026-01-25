class Main {
	static function add1(x: Int): Int return x + 1;

	static function apply(f: Int->Int, x: Int): Int {
		return f(x);
	}

	static function main(): Void {
		var f: Int->Int = add1;
		trace(f(5));

		var g: Int->Int = function(x: Int): Int return x * 2;
		trace(apply(g, 3));
	}
}

