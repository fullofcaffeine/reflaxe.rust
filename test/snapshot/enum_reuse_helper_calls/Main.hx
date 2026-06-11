class Main {
	static function label(value:TokenValue):String {
		return switch (value) {
			case Text(text): "text:" + text;
			case Number(number): "number:" + number;
			case Missing: "missing";
		}
	}

	static function isPresent(value:TokenValue):Bool {
		return switch (value) {
			case Missing: false;
			case Text(_) | Number(_): true;
		}
	}

	static function describe(value:TokenValue):String {
		final first = label(value);
		final second = if (isPresent(value)) "present" else "absent";
		return first + ":" + second;
	}

	static function main() {
		Sys.println(describe(Text("alpha")));
		Sys.println(describe(Missing));
	}
}
