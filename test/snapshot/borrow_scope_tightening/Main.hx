class Counter {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	static function readValue(counter:Counter):Int {
		return counter.value;
	}

	static function main() {
		var counter = new Counter(7);
		trace(readValue(counter));
	}
}
