import sys.thread.EventLoop.EventHandler;
import sys.thread.EventLoop.NextEventTime;
import sys.thread.Thread;

class Main {
	static function describe(t:NextEventTime):String {
		return switch (t) {
			case Now: "now";
			case Never: "never";
			case AnyTime(null): "any";
			case AnyTime(_): "any_at";
			case At(_): "at";
		};
	}

	static function main() {
		var loop = Thread.current().events;
		var seen:Array<String> = [];
		var h:Null<EventHandler> = null;
		h = loop.repeat(() -> {
			seen.push("tick" + seen.length);
			if (seen.length == 2)
				loop.cancel(h);
		}, 10);
		Sys.sleep(0.05);
		Sys.println("before=" + describe(loop.progress()));
		Sys.sleep(0.02);
		Sys.println("after=" + describe(loop.progress()));
		Sys.sleep(0.02);
		Sys.println("final=" + describe(loop.progress()));
		Sys.println(seen.join(","));
	}
}
