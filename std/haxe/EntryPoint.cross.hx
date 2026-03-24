package haxe;

import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;

/**
	`haxe.EntryPoint` Rust-target override.

	Why
	- `haxe.EntryPoint` is the public scheduler bridge used by `haxe.MainLoop`.
	- The Rust target needs a real emitted implementation so `MainLoop` / `EntryPoint` smoke cases
	  compile and run on the target instead of only type-checking against upstream std.
	- The current target still treats broader MainLoop/EntryPoint parity as caveat-heavy, so the goal
	  here is a concrete, auditable scheduler loop rather than an overclaimed parity story.

	What
	- A Rust-target implementation of the upstream main-thread pending queue plus wakeup loop.
	- Supports:
	  - `runInMainThread`
	  - `addThread`
	  - `run`
	  - main-loop wakeups driven by `sys.thread.Lock`

	How
	- Uses `sys.thread.Mutex` to protect the pending queue and thread-count bookkeeping.
	- Uses `sys.thread.Lock` as the sleeping/wakeup primitive for the main loop.
	- Processes direct `runInMainThread` callbacks first, then delegates timer/event ordering to
	  `haxe.MainLoop.tick()`.
	- This intentionally provides target-side proof for basic Rust-target behavior without claiming
	  blanket `--interp` scheduler parity.
**/
class EntryPoint {
	static var mutex = new Mutex();
	static var sleepLock = new Lock();
	static var pending = new Deque<Void->Void>();

	public static var threadCount(default, null):Int = 0;

	/**
		Wakeup a sleeping `run()`.
	**/
	public static function wakeup():Void {
		sleepLock.release();
	}

	public static function runInMainThread(f:Void->Void):Void {
		pending.add(f);
		wakeup();
	}

	public static function addThread(f:Void->Void):Void {
		mutex.acquire();
		threadCount = threadCount + 1;
		mutex.release();

		Thread.create(() -> {
			f();
			mutex.acquire();
			threadCount = threadCount - 1;
			var noThreads = threadCount == 0;
			mutex.release();
			if (noThreads)
				wakeup();
		});
	}

	static function processEvents():Float {
		while (true) {
			var f = pending.pop(false);
			if (f == null)
				break;
			f();
		}

		var time = @:privateAccess MainLoop.tick();
		if (!MainLoop.hasEvents() && threadCount == 0)
			return -1;
		return time;
	}

	/**
		Start the main loop. Returns when no blocking main-loop events or worker threads remain.
	**/
	@:keep public static function run() @:privateAccess {
		while (true) {
			var nextTick = processEvents();
			if (nextTick < 0)
				break;
			if (nextTick > 0)
				sleepLock.wait(nextTick);
		}
	}
}
