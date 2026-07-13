package fixture;

interface ParentContract {
	public function label():String;
}

enum SampleEnum<T:ParentContract> {
	Empty;
	Value(value:T);
}

typedef SampleShape = {
	@:optional var label:String;
	var count(default, null):Int;
}

class Surface<T:ParentContract> {
	public var value(default, null):T;

	public function new(value:T, label:String = "fixture") {
		this.value = value;
	}

	public function map<U:ParentContract>(callback:(T) -> U):Surface<U> {
		return new Surface(callback(value));
	}

	public function records():Array<{label:String, value:T}> {
		return [];
	}

	public function nested():Array<Array<T>> {
		return [];
	}

	public function afterNested():Void {}

	private function hidden():Void {}
}

class StructuralConstraint<T:{}> {
	public function new() {}
	public function accept(value:T):T return value;
}

class ConditionalSurface {
	#if macro
	public static function value():Int
		return 0;
	#else
	public static function value():Int {
		return 1;
	}
	#end
}
