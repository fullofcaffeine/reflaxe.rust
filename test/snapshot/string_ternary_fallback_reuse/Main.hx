class Main {
	static function pick(enabled:Bool, primary:String, fallback:String):String {
		var selected = enabled ? primary : fallback;
		var preserved = fallback;
		return selected + ":" + preserved;
	}

	static function main():Void {
		trace(pick(false, "live", "backup"));
	}
}
