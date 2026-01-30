class Main {
	static function main() {
		var xs = [3, 1, 2, 1];
		Sys.println(xs.indexOf(1));
		Sys.println(xs.indexOf(1, -2));
		Sys.println(xs.lastIndexOf(1));
		Sys.println(xs.lastIndexOf(1, 2));
		Sys.println(xs.contains(2));
		Sys.println(xs.remove(1));
		Sys.println(xs.join(","));

		xs.sort((a, b) -> a - b);
		Sys.println(xs.join(","));
	}
}
