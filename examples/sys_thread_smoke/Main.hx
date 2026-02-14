import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;

class Main {
	static function main() {
		final mainThread = Thread.current();
		final mutex = new Mutex();

		Thread.create(() -> {
			// Verify re-entrant semantics (required by Haxe docs).
			mutex.acquire();
			mutex.acquire();
			mutex.release();
			mutex.release();

			// Send to the main thread's queue (not the current thread).
			mainThread.sendMessage("child_ready");
		});

		final msg = Thread.readMessageString(true);
		if (msg == null) {
			throw "expected a string message from child thread";
		}
		Sys.println(msg);
	}
}
