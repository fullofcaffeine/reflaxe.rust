class NotWidget {
	static function main():Void {
		var primary = haxe.Json.stringify(110011);
		Widget.touch();
		if (primary.length == -1) {}
	}
}

class Widget {
	public static function touch():Void {
		var secondary = haxe.Json.stringify(220022);
		if (secondary.length == -1) {}
	}
}
