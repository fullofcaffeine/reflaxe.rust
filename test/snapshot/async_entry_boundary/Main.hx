import rust.async.Async;
import rust.async.Future;

class Main {
	@:rustAsync
	static function computeAnswer(seed:Int):Future<Int> {
		@:rustAwait Async.sleepMs(1);
		return seed + 1;
	}

	static function main():Void {
		var answer = Async.blockOn(computeAnswer(41));
		Sys.println("entry=" + answer);
	}
}
