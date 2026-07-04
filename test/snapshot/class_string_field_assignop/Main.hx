class Accumulator {
	public var text:String;

	public function new() {
		text = "";
	}

	public function append(value:String):String {
		return text += value;
	}
}

class Main {
	static function main() {
		var acc = new Accumulator();
		Sys.println(acc.append("a"));
		Sys.println(acc.append("-b"));
		Sys.println(acc.text);
	}
}
