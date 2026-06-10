class Worker {
	@:rustAsync
	public function new() {}
}

class Main {
	static function main():Void {
		new Worker();
	}
}
