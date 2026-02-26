import rust.async.Async;
import rust.async.Future;

class Main {
	@:rustAsync
	static function nextValue(value:Int):Future<Int> {
		@:rustAwait Async.sleepMs(1);
		return value + 1;
	}

	@:rustAsync
	static function compute():Future<String> {
		var a = @:rustAwait nextValue(40);
		var b = @:rustAwait nextValue(a);
		return "value=" + b;
	}

	static function main():Void {
		Sys.println(Async.blockOn(compute()));
	}
}
