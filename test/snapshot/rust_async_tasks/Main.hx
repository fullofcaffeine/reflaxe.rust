import rust.Option;
import rust.async.Async;
import rust.async.Future;
import rust.async.Tasks;
#if async_tokio_adapter
import rust.async.TokioRuntime;
#end

class Main {
	@:rustAsync
	static function produce(label:String, ms:Int):Future<String> {
		@:rustAwait Async.sleepMs(ms);
		return label;
	}

	@:rustAsync
	static function flow():Future<String> {
		var worker = Tasks.spawn(() -> produce("task-ok", 1));
		var viaTask = Tasks.join(worker);
		var viaSpawn = @:rustAwait Async.spawn(produce("spawn-ok", 1));
		var timed = @:rustAwait Async.timeoutMs(produce("too-slow", 20), 1);

		var timeoutText = switch (timed) {
			case Some(value): value;
			case None: "timeout";
		};

		return viaTask + "|" + viaSpawn + "|" + timeoutText;
	}

	static function main():Void {
		#if async_tokio_adapter
		TokioRuntime.enable();
		#end
		var out = Async.blockOn(flow());
		trace(out);
	}
}
