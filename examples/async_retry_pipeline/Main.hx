import rust.async.Async;
import rust.async.Future;

class Main {
	@:rustAsync
	static function requestValue(id:Int, attempt:Int):Future<Null<String>> {
		// Deterministic simulation: the remote source is unavailable for the first two attempts.
		if (attempt < 2) {
			return null;
		}
		return "payload-" + id + "-attempt-" + attempt;
	}

	@:rustAsync
	static function fetchWithRetry(id:Int, maxAttempts:Int):Future<String> {
		for (attempt in 0...maxAttempts) {
			var value = @:rustAwait requestValue(id, attempt);
			if (value != null) {
				return value;
			}

			// Simple linear backoff so the output remains deterministic in CI.
			var backoffMs = (attempt + 1) * 10;
			@:rustAwait Async.sleepMs(backoffMs);
		}

		return "fallback-" + id;
	}

	static function main():Void {
		var result = Async.blockOn(fetchWithRetry(7, 4));
		Sys.println("result=" + result);
	}
}
