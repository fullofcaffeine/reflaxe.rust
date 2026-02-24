import rust.Borrow;
import sys.thread.Thread;

class Main {
	static function main():Void {
		var values = [1, 2, 3];
		Borrow.withRef(values, borrowed -> {
			Thread.create(() -> {
				var keep = borrowed;
				Sys.println(Std.string(keep));
			});
		});
	}
}
