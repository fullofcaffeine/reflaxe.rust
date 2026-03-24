import haxe.EntryPoint;
import haxe.MainLoop;
import sys.thread.Lock;

class Main {
	static function main() {
		var seen:Array<String> = [];
		var gate = new Lock();

		MainLoop.runInMainThread(() -> {
			seen.push("main");
			gate.release();
		});

		MainLoop.addThread(() -> {
			gate.wait();
			MainLoop.runInMainThread(() -> seen.push("thread"));
		});

		EntryPoint.run();
		Sys.println(seen.join(","));
	}
}
