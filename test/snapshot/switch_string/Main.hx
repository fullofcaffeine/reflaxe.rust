class Main {
	static function main() {
		var s = "b";
		var n = switch (s) {
			case "a": 1;
			case "b": 2;
			default: 0;
		}
		trace(n);
	}
}

