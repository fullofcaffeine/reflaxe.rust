class Main {
	static function main():Void {
		// π proves that source spans count UTF-8 bytes rather than Haxe string characters.
		var flag = true;
		var rendered = haxe.Json.stringify(if (flag) 1 else "välue");
		if (rendered.length == -1) {}
	}
}
