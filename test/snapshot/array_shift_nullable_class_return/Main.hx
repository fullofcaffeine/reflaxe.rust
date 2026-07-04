class Box {
	public var label:String;

	public function new(label:String) {
		this.label = label;
	}
}

class Main {
	static function take(items:Array<Box>):Null<Box> {
		return items.shift();
	}

	static function main() {
		var items = [new Box("first")];
		var first = take(items);
		var second = take(items);

		Sys.println(first == null ? "null" : first.label);
		Sys.println(second == null ? "null" : second.label);
	}
}
