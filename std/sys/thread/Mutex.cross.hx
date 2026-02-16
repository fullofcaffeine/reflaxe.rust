package sys.thread;

import hxrt.thread.MutexHandle;
import rust.HxRef;

/**
	Creates a mutex, which can be used to acquire a temporary lock
	to access some resource.

	Why
	- The upstream Haxe std requires `sys.thread.Mutex` and specifies that it is re-entrant:
	  the owning thread may acquire it multiple times and must release the same number of times.

	What
	- A thin Haxe wrapper around a Rust runtime primitive (`hxrt::thread::MutexHandle`).

	How
	- `acquire()` blocks until the mutex is available (or re-enters if already owned by this thread).
	- `tryAcquire()` returns immediately.
	- `release()` throws if called by a non-owner thread.
**/
class Mutex {
	final __h:HxRef<MutexHandle>;

	public function new():Void {
		__h = untyped __rust__("hxrt::thread::mutex_new()");
	}

	public function acquire():Void {
		untyped __rust__("{0}.borrow().acquire()", __h);
	}

	public function tryAcquire():Bool {
		return untyped __rust__("{0}.borrow().try_acquire()", __h);
	}

	public function release():Void {
		untyped __rust__("{0}.borrow().release()", __h);
	}
}
