package sys.thread;

import hxrt.thread.SemaphoreHandle;
import rust.HxRef;

/**
	Counting semaphore.

	Why
	- Used by some Haxe sys libraries and common in user code.

	What
	- Wrapper around `hxrt::thread::SemaphoreHandle`.

	How
	- `acquire()` blocks until the count is > 0 and decrements it.
	- `tryAcquire(timeout)` returns immediately (if `timeout` is omitted) or blocks for at most
	  `timeout` seconds.
**/
@:coreApi
class Semaphore {
	final __h: HxRef<SemaphoreHandle>;

	public function new(value:Int):Void {
		__h = untyped __rust__("hxrt::thread::semaphore_new({0})", value);
	}

	public function acquire():Void {
		untyped __rust__("{0}.borrow().acquire()", __h);
	}

	public function tryAcquire(?timeout:Float):Bool {
		return untyped __rust__("{0}.borrow().try_acquire({1})", __h, timeout);
	}

	public function release():Void {
		untyped __rust__("{0}.borrow().release()", __h);
	}
}

