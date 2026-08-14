interface Comparable<T> {}

class Box<T:Comparable<T>> {
	public function new() {}
}

class Value implements Comparable<Value> {
	public function new() {}
}

class Main {
	static function main():Void {
		final value = new Box<Value>();
		trace(value);
	}
}
