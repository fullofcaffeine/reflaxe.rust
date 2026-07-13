private typedef Pair = {
	var key:String;
	var value:Int;
}

class Main {
	static function makePair():Pair {
		return {
			key: "before",
			value: 1
		};
	}

	static function main() {
		var pair = makePair();
		var alias = pair;
		alias.key = "after";
		alias.value = 2;
		alias.value += 3;
		alias.value++;

		Sys.println("pair=" + pair.key + ":" + pair.value);
		Sys.println("alias=" + alias.key + ":" + alias.value);
		Sys.println("same=" + (pair == alias));
	}
}
