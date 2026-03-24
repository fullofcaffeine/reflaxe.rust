class Main {
	static function main() {
		var run = 3;
		var inner = 7;
		var label = "json-" + Std.string(run) + "-" + Std.string(inner);
		if (label == "__never__") {
			Sys.println(label);
		}
	}
}
