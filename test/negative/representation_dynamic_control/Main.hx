class Main {
	static function main():Void {
		var flag = true;
		var rendered = haxe.Json.stringify(if (flag) 1 else "value");
		if (rendered.length == -1) {}
	}
}
