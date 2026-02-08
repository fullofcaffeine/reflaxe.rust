class B extends A {
	public function new() {
		super();
	}

	override function get_x():Int {
		return super.get_x() + 10;
	}

	override function set_x(v:Int):Int {
		return super.set_x(v + 10);
	}

	override public function sound():String {
		return "B.sound";
	}
}
