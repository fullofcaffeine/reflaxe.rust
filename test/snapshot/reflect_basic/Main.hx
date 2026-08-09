class C {
	public var n:Int;
	public var dynamicValue:Dynamic;

	public function new() {
		n = 0;
		dynamicValue = null;
	}
}

class Main {
	static function main() {
		var c = new C();
		trace(Reflect.hasField(c, "n"));
		trace(Reflect.field(c, "n"));
		Reflect.setField(c, "n", 3);
		Reflect.setField(c, "dynamicValue", 143143);
		trace(c.n);

		var o = {x: 1};
		trace(Reflect.hasField(o, "x"));
		trace(Reflect.hasField(o, "y"));
		trace(Reflect.field(o, "x"));
		Reflect.setField(o, "x", 2);
		trace(o.x);
		var functions:{factory:Void->Dynamic} = {factory: () -> 169169};
		Reflect.setField(functions, "factory", () -> 170170);
		trace(functions.factory());
		var optionalForDynamic:Null<Bool> = null;
		var dynamicFields:{value:Dynamic} = {value: true};
		Reflect.setField(dynamicFields, "value", optionalForDynamic);
		trace(Reflect.field(dynamicFields, "value") == null);

		var parsed:Dynamic = haxe.Json.parse('{"label":"ok","n":3}');
		trace(Reflect.hasField(parsed, "label"));
		trace(Reflect.field(parsed, "label"));
		Reflect.setField(parsed, "n", 4);
		trace(Reflect.field(parsed, "n"));
	}
}
