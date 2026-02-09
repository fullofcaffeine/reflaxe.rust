package sys.thread;

import hxrt.thread.LockHandle;
import rust.HxRef;

/**
	A Lock allows blocking execution until it has been unlocked. It keeps track
	of how often `release` has been called, and blocks exactly as many `wait`
	calls.

	Why
	- `sys.thread.Lock` is used pervasively in the upstream Haxe stdlib to coordinate background work.
	- Rust needs a real OS-thread blocking primitive (no busy loops) to be production-usable.

	What
	- A thin Haxe wrapper around a Rust runtime primitive (`hxrt::thread::LockHandle`).

	How
	- `new()` creates a handle in the runtime.
	- `wait()` blocks until at least one `release()` happened (or until timeout).
	- `release()` increments a counter and wakes exactly one waiter.
**/
class Lock {
	final __h: HxRef<LockHandle>;

	public function new():Void {
		__h = untyped __rust__("hxrt::thread::lock_new()");
	}

	public function wait(?timeout:Float):Bool {
		return untyped __rust__("{0}.borrow().wait({1})", __h, timeout);
	}

	public function release():Void {
		untyped __rust__("{0}.borrow().release()", __h);
	}
}

