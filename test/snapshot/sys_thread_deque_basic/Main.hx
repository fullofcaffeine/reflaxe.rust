import sys.thread.Deque;
import sys.thread.Thread;

class Main {
	static function main() {
		var q = new Deque<String>();
		q.add("a");
		q.push("b");
		var first = q.pop(false);
		var second = q.pop(false);
		var third = q.pop(false);
		Thread.create(() -> {
			Sys.sleep(0.05);
			q.add("later");
		});
		var fourth = q.pop(true);
		Sys.println([first, second, third, fourth].join(","));
	}
}
