class OptionalPrimitiveDefaults {
	public var flag:Bool;
	public var count:Int;
	public var name:String;

	public function new(?flag:Bool = false, ?count:Int = 0, ?name:String = "") {
		this.flag = flag;
		this.count = count;
		this.name = name;
	}

	public function describe():String {
		return (flag ? "yes" : "no") + ":" + count + ":" + name;
	}
}

class Main {
	static function main() {
		var defaults = new OptionalPrimitiveDefaults();
		var explicit = new OptionalPrimitiveDefaults(true, 7, "fast");

		Sys.println(defaults.describe());
		Sys.println(explicit.describe());
	}
}
