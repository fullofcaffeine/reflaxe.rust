class Main {
	static function main() {
		var xs = [1, 2, 3];
		Sys.println(xs.toString());

		var ys = xs.map(x -> x * 2);
		Sys.println(ys.join(","));

		var zs = ys.filter(x -> x > 2);
		Sys.println(zs.join(","));

		var it = zs.iterator();
		var sum = 0;
		while (it.hasNext()) {
			sum = sum + it.next();
		}
		Sys.println(sum);
	}
}
