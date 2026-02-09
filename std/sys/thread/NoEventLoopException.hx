package sys.thread;

import haxe.Exception;

/**
	Thrown when a thread does not have an event loop.

	Why
	- Some stdlib functionality expects `sys.thread.Thread.events` to exist and be progressed.
	- On some targets, not all threads have an event loop unless explicitly enabled.

	What
	- Signals the caller to use `Thread.runWithEventLoop(...)` when an event loop is required.

	How
	- The Rust target provides an event loop implementation backed by `hxrt::thread`.
	- This exception remains for stdlib parity and for future integrations where event loops may be
	  opt-in for specific threads.
**/
class NoEventLoopException extends Exception {
	public function new(msg: String = "Event loop is not available. Refer to sys.thread.Thread.runWithEventLoop.", ?previous: Exception) {
		super(msg, previous);
	}
}

