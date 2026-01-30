class Main {
	static function bump(a:Array<Int>):Void {
		a.push(99);
	}

	static function main() {
		var a = [1];

		// Aliasing on assignment: both variables point to the same underlying array.
		var b = a;
		b.push(2);
		Sys.println(a.length); // 2

		// Aliasing through function calls: mutations in the callee are visible to the caller.
		bump(a);
		Sys.println(a.length); // 3
		Sys.println(b.length); // 3
	}
}

