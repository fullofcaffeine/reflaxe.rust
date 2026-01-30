class Main {
	static function main() {
		var xs = ["a", "b", "c"];
		xs.insert(-1, "X");
		Sys.println(xs.join(""));

		xs.insert(-100, "Y");
		Sys.println(xs.join(""));

		xs.insert(999, "Z");
		Sys.println(xs.join(""));
	}
}
