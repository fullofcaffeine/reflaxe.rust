class Main {
	static function replacer(key:Dynamic, value:Dynamic):Dynamic {
		var keyText:String = Std.string(key);
		if (keyText == "")
			return {root: value};
		if (keyText == "title")
			return "SUNSET";
		if (keyText == "age")
			return 5;
		if (keyText == "0")
			return false;
		return value;
	}

	static function render(value:Dynamic):String {
		return haxe.Json.stringify(value, replacer, "  ").split("\n").join("\\n");
	}

	static function main() {
		var flags:Array<Dynamic> = [];
		flags.push(true);
		flags.push(false);
		Sys.println("root=" + render(1));
		Sys.println("title=" + render({title: "sunset"}));
		Sys.println("nested=" + render({outer: {age: 4}}));
		Sys.println("array=" + render(flags));
	}
}
