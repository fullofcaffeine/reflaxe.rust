class Main {
	static function main() {
		var b:Base<String> = new Sub();
		Sys.println(b.id("hi"));
	}
}
