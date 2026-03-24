import rust.async.Async;
import rust.async.Future;

class Worker {
	public var base:Int;

	public function new(base:Int) {
		this.base = base;
	}

	@:rustAsync
	public function plus(delta:Int):Future<Int> {
		@:rustAwait Async.sleepMs(1);
		return base + delta;
	}

	@:rustAsync
	public function bumpAndRead():Future<Int> {
		base += 1;
		@:rustAwait Async.sleepMs(1);
		return base;
	}
}

class Main {
	static function main():Void {
		var worker = new Worker(41);
		var sum = Async.blockOn(worker.plus(1));
		var bumped = Async.blockOn(worker.bumpAndRead());
		Sys.println("sum=" + sum);
		Sys.println("bump=" + bumped);
		Sys.println("stored=" + worker.base);
	}
}
