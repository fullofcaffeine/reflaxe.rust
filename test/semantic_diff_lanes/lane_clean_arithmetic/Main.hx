class Main {
	static function main() {
		var token = LaneMathToken.Sum;
		var value = switch (token) {
			case Sum:
				var sum = 0;
				for (i in 0...6) {
					sum += i;
				}
				sum;
			case Zero:
				0;
		};
		Sys.println(Std.string(value));
	}
}
