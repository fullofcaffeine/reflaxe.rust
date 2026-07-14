class Example {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	static function main():Void {
		Type.createEmptyInstance(Example);
	}
}
