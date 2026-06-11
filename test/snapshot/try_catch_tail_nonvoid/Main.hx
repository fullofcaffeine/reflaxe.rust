class Main {
	static function decode(raw:String):Int {
		try {
			if (raw == "bad")
				throw "invalid";
			return raw.length;
		} catch (_:Dynamic) {
			return -1;
		}
	}

	static function main():Void {
		Sys.println(decode("rust"));
		Sys.println(decode("bad"));
	}
}
