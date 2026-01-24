class Main {
	static function main() {
		var x = 2;
		var s = switch (x) {
			case 1: "one";
			case 2, 3: "two_or_three";
			default: "other";
		}
		trace(s);
	}
}

