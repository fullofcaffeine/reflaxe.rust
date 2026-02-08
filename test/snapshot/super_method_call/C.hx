class C extends B {
	public function new() {
		super();
	}

	override function get_x():Int {
		return super.get_x() + 100;
	}

	override function set_x(v:Int):Int {
		return super.set_x(v + 100);
	}

	override public function sound():String {
		return "C.sound";
	}

	public function callSuperSound():String {
		return super.sound();
	}

	public function callSuperFoo():String {
		return super.foo();
	}

	public function incSuperX():Int {
		super.x = super.x + 1;
		return super.x;
	}
}
