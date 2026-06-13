class Main {
	static function verdict(value:Bool):String {
		return value ? "yes" : "no";
	}

	static function main() {
		final shared = new Payload("alpha");
		final sameRefA = RefCommand.Use(shared);
		final sameRefB = RefCommand.Use(shared);
		final sameShape = RefCommand.Use(new Payload("alpha"));

		Sys.println(verdict(sameRefA == sameRefB));
		Sys.println(verdict(sameRefA == sameShape));
		Sys.println(verdict(RefCommand.Skip == RefCommand.Skip));
	}
}
