class Main {
	static function main():Void {
		var payload:haxe.DynamicAccess<Int> = {};
		payload.set("value", 42);
		if (payload.get("value") == -1) {}
	}
}
