class Main {
	static function main():Void {
		var value = "abcdef";
		var start = 1;
		var end = 4;

		Sys.println(value.substring(start, end));
		Sys.println(value.substring(2));
		Sys.println(value.substring(4, 1));
		Sys.println(value.substring(3, 3));
		Sys.println(value.substring(0, value.length));
	}
}
