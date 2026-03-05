class Main {
	static function main():Void {
		MetalFirstTests.__link();
		for (line in Harness.runValid()) {
			Sys.println(line);
		}
		Sys.println(Harness.runInvalid());
	}
}
