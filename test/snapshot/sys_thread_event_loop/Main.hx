import sys.thread.EventLoop.NextEventTime;
import sys.thread.Thread;

class Main {
	static function describe(time:NextEventTime):String {
		return switch (time) {
			case Now: "now";
			case Never: "never";
			case AnyTime(null): "any";
			case AnyTime(_): "any_at";
			case At(_): "at";
		};
	}

	static function main() {
		var loop = Thread.current().events;
		var entrySeen = false;
		var promisedSeen = false;
		Sys.println('initial=' + describe(loop.progress()));

		loop.run(() -> entrySeen = true);
		Sys.println('after_run=' + describe(loop.progress()));
		Sys.println('entry_seen=' + entrySeen);

		loop.promise();
		Sys.println('after_promise=' + describe(loop.progress()));
		loop.runPromised(() -> promisedSeen = true);
		Sys.println('after_run_promised=' + describe(loop.progress()));
		Sys.println('promised_seen=' + promisedSeen);
		Sys.println('final=' + describe(loop.progress()));
	}
}
