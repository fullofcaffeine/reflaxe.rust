class Main {
	static function main():Void {
		var encoded = haxe.Json.stringify(271828);
		var days = DateTools.days(1);
		var mutex = rust.concurrent.Mutexes.create(1);
		var cwd = Sys.getCwd();
		if (encoded.length == -1 || days == -1 || mutex == null || cwd.length == -1) {}
	}
}
