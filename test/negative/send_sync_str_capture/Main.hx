import rust.StrTools;
import sys.thread.Thread;

class Main {
	static function main():Void {
		StrTools.with("hello", borrowed -> {
			Thread.create(() -> {
				var keep = borrowed;
				Sys.println("spawned");
			});
		});
	}
}
