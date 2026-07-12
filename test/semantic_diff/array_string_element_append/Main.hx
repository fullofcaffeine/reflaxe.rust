class Main {
	static var values:Array<String> = ["left", "right"];
	static var arrayCalls = 0;
	static var indexCalls = 0;
	static var rhsCalls = 0;

	static function receiver():Array<String> {
		arrayCalls = arrayCalls + 1;
		return values;
	}

	static function index():Int {
		indexCalls = indexCalls + 1;
		return 1;
	}

	static function suffix():String {
		rhsCalls = rhsCalls + 1;
		values[1] = "rhs-mutated";
		return ":updated";
	}

	static function main() {
		Sys.println("append-result=" + (receiver()[index()] += suffix()));
		Sys.println("expression-value=" + values[1]);
		receiver()[index()] += suffix();
		Sys.println("statement-value=" + values[1]);
		receiver()[index()] += 7;
		Sys.println("mixed-rhs-value=" + values[1]);
		Sys.println("array-calls=" + arrayCalls);
		Sys.println("index-calls=" + indexCalls);
		Sys.println("rhs-calls=" + rhsCalls);
	}
}
