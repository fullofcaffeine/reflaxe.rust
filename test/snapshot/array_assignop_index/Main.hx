class Main {
	static function main():Void {
		var a = [1, 2, 3];
		a[1] += 5;
		trace(a.join(","));
		a[0] *= 3;
		trace(a.join(","));

		var b = [1.0, 2.0];
		b[0] *= 2.5;
		trace(b.join(","));
	}
}

