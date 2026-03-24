class C {
	public var n:Int;

	public function new() {
		n = 0;
	}
}

class Main {
	static function main() {
		var c = new C();
		trace(Reflect.hasField(c, "n"));
		trace(Reflect.field(c, "n"));
		Reflect.setField(c, "n", 3);
		trace(c.n);

		var o = {x: 1};
		trace(Reflect.hasField(o, "x"));
		trace(Reflect.hasField(o, "y"));
		trace(Reflect.field(o, "x"));
		Reflect.setField(o, "x", 2);
		trace(o.x);

		var parsed:Dynamic = haxe.Json.parse('{"label":"ok","n":3}');
		trace(Reflect.hasField(parsed, "label"));
		trace(Reflect.field(parsed, "label"));
		Reflect.setField(parsed, "n", 4);
		trace(Reflect.field(parsed, "n"));
	}
}
