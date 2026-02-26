class Main {
	static function diverge(flag:Bool):Int {
		if (flag)
			throw "boom"
		else
			throw "bang";
		return 1;
	}

	static function main():Void {
		var f = (flag:Bool) -> {
			if (flag)
				throw "boom"
			else
				throw "bang";
			return 7;
		};

		try {
			f(true);
		} catch (e:String) {
			trace(e);
		}

		try {
			diverge(false);
		} catch (e:String) {
			trace(e);
		}
	}
}
