class Main {
	static function main() {
		var xs = [1, 2, 3, 4, 5];

		var s1 = xs.slice(1, 4);
		Sys.println(s1.join(","));

		var removed = xs.splice(-2, 10);
		Sys.println(removed.join(","));
		Sys.println(xs.join(","));

		var ys = xs.concat([9, 10]);
		Sys.println(ys.join(","));
	}
}
