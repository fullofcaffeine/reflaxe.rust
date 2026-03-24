import haxe.EntryPoint;
import haxe.MainLoop;
import haxe.MainLoop.MainEvent;

class Main {
	static function main() {
		var seen:Array<String> = [];
		var seenFirst = seen;
		var seenSecond = seen;
		var first:Null<MainEvent> = null;
		var second:Null<MainEvent> = null;

		first = MainLoop.add(() -> {
			seenFirst.push("first");
			first.stop();
		});
		second = MainLoop.add(() -> {
			seenSecond.push("second");
			second.stop();
		});

		EntryPoint.run();
		Sys.println(seen.join(","));
	}
}
