class Main {
	static function main() {
		var c = new C();
		trace(c.sound());
		trace(c.callSuperSound());
		trace(c.callSuperFoo());
		trace(c.incSuperX());
	}
}

