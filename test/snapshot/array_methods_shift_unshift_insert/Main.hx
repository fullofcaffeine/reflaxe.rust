class Main {
	static function main() {
		var xs = ["b", "c"];
		xs.unshift("a");
		xs.push("d");
		xs.insert(2, "X");
		Sys.println(xs.join(""));

		var first = xs.shift();
		if (first == null) {
			Sys.println("null");
		} else {
			Sys.println((first : String));
		}
		Sys.println(xs.join(""));
	}
}
