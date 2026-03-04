class Base {
	public function new() {}

	public function who():String {
		return "base";
	}

	public function render():String {
		return "render:" + who();
	}
}

class Child extends Base {
	public function new() {
		super();
	}

	override public function who():String {
		return "child";
	}
}

class Main {
	static function main() {
		var value:Base = new Child();
		Sys.println(value.who());
		Sys.println(value.render());
	}
}
