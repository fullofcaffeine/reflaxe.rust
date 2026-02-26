class Main {
	static function make():Void->Int {
		return () -> return {
			var x = 1;
			x + 2;
		};
	}

	static function main():Void {
		var f = make();
		trace(f());
	}
}
