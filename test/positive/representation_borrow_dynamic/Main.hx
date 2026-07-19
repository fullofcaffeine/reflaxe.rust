import rust.Borrow;

class Main {
	static function inspect(value:Dynamic):String {
		return Std.string(value);
	}

	static function main():Void {
		var count = 7;
		var label = "hello";
		var copied = Borrow.withRef(count, borrowed -> inspect(borrowed));
		var cloned = Borrow.withRef(label, borrowed -> inspect(borrowed));
		Sys.println(copied + "|" + cloned);
	}
}
