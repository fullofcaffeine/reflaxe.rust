import rust.async.Async;
import rust.async.Future;
#if async_tokio_adapter
import rust.async.TokioRuntime;
#end

class Main {
	@:rustAsync
	static function quick(label:String):Future<String> {
		@:rustAwait Async.sleepMs(1);
		return label;
	}

	@:rustAsync
	static function slow(label:String):Future<String> {
		@:rustAwait Async.sleepMs(20);
		return label;
	}

	@:rustAsync
	static function flow():Future<String> {
		var first = @:rustAwait Async.select(quick("left-fast"), slow("right-slow"));
		var second = @:rustAwait Async.select(slow("left-slow"), quick("right-fast"));
		return first + "|" + second;
	}

	static function main():Void {
		#if async_tokio_adapter
		TokioRuntime.enable();
		#end
		trace(Async.blockOn(flow()));
	}
}
