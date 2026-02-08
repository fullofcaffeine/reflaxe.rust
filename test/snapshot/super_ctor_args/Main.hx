class Base {
	public var x: Int;
	public var y: String;

	public function new(x: Int, y: String) {
		this.x = x;
		this.y = y;
	}
}

class Sub extends Base {
	public var z: Int;

	public function new(x: Int, y: String, z: Int) {
		super(x + 1, y);
		this.z = z;
	}
}

class Main {
	static function main(): Void {
		var s = new Sub(1, "hi", 3);
		trace(s.x);
		trace(s.y);
		trace(s.z);
	}
}
