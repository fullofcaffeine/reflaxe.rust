package demo.domain;

class Widget {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function bump():Void {
		value = value + 1;
	}
}
