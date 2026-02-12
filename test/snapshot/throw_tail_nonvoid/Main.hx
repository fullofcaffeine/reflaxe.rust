class Main {
	static function decode(v:Int):Int {
		if (v == 0) return 10;
		throw "bad value";
	}

	static function main():Void {
		Sys.println(decode(0));

		try {
			Sys.println(decode(1));
		} catch (e:Dynamic) {
			Sys.println("caught");
		}
	}
}
