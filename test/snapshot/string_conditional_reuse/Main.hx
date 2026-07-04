class Main {
	static function render(message:String, useOriginal:Bool, useLast:Bool):String {
		var finalText = if (useOriginal) message else "fallback";
		var lastText = if (useLast) message else "last";
		var notification = if (finalText.length > 0) message else "empty";
		return finalText + "|" + lastText + "|" + notification + "|" + message;
	}

	static function main() {
		Sys.println(render("hello", true, false));
	}
}
