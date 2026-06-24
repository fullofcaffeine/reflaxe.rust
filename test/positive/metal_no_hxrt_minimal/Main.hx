import rust.SystemTime;
import rust.SystemTimeTools;

class Main {
	static inline function add(a:Int, b:Int):Int {
		return a + b;
	}

	static function main() {
		var total = add(20, 22);
		var now = SystemTime.now();
		var millis = SystemTimeTools.unixMillis(now);
		if (total == -1 || millis < 0.0) {
			var impossible = total;
			if (impossible == 0) {}
		}
	}
}
