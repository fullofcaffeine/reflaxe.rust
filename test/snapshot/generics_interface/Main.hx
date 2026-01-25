class Main {
	static function main() {
		var b:IGet<String> = new Box("hello");
		Sys.println(b.get());
	}
}

