import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;

/**
	Basic OS-thread smoke for the portable `sys.thread` contract.

	Why
	- This example is the smallest end-to-end proof that Rust-target threads are real OS threads,
	  not a stubbed single-thread simulation.
	- It also exercises two easy-to-regress semantics that matter for user trust:
	  re-entrant `Mutex` behavior and cross-thread message delivery back to the main thread.

	What
	- Spawn one worker thread.
	- Re-enter the same mutex twice on that worker.
	- Send a string message back to the main thread and print it.

	How
	- `Thread.create` proves worker-thread creation.
	- `mainThread.sendMessage(...)` + `Thread.readMessageString(true)` proves queue-based delivery.
	- The printed `child_ready` line is the regression signal used by docs/CI smoke flows.
**/
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
