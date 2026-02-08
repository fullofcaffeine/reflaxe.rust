class A {
	public var x(get, set):Int;
	var _x:Int;

	public function new() {
		_x = 1;
	}

	function get_x():Int {
		return _x;
	}

	function set_x(v:Int):Int {
		_x = v;
		return v;
	}

	public function foo():String {
		return "A.foo";
	}

	public function sound():String {
		return "A.sound";
	}
}
