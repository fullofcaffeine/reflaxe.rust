import sys.thread.FixedThreadPool;
import sys.thread.Lock;
import sys.thread.Mutex;

/**
	Fixed thread-pool smoke for the portable `sys.thread` helpers.

	Why
	- This example exists to answer a different question than `examples/sys_thread_smoke`.
	- `sys_thread_smoke` proves raw thread creation/message passing.
	- This example proves the higher-level `FixedThreadPool` helper can schedule multiple jobs,
	  coordinate completion, and shut down cleanly on the Rust target.

	What
	- Queue three tasks onto a fixed pool of size two.
	- Protect a shared completion counter with `Mutex`.
	- Use `Lock` as the completion signal and print `ok:3` when all work finished.

	How
	- The explicit cloned handles keep closure moves obvious in generated Rust.
	- `doneLock.wait()` turns the example into a deterministic regression signal instead of a
	  timing-sensitive sleep-based smoke test.
**/
class Main {
	static function main() {
		final pool = new FixedThreadPool(2);
		final doneLock = new Lock();
		final mutex = new Mutex();
		final doneBox = [0];

		// Clone the shared references so each closure moves its own handle.
		final doneLock1 = doneLock;
		final mutex1 = mutex;
		final doneBox1 = doneBox;
		pool.run(() -> task(doneLock1, mutex1, doneBox1));

		final doneLock2 = doneLock;
		final mutex2 = mutex;
		final doneBox2 = doneBox;
		pool.run(() -> task(doneLock2, mutex2, doneBox2));

		final doneLock3 = doneLock;
		final mutex3 = mutex;
		final doneBox3 = doneBox;
		pool.run(() -> task(doneLock3, mutex3, doneBox3));

		doneLock.wait();
		pool.shutdown();

		Sys.println("ok:" + doneBox[0]);
	}

	static function task(doneLock:Lock, mutex:Mutex, doneBox:Array<Int>) {
		mutex.acquire();
		doneBox[0] = doneBox[0] + 1;
		final d = doneBox[0];
		mutex.release();

		if (d == 3)
			doneLock.release();
	}
}
