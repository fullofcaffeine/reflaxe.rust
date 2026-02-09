package sys.thread;

import hxrt.thread.ConditionHandle;
import rust.HxRef;

/**
	Creates a new condition variable.

	Why
	- Condition variables are required by the upstream Haxe std for building higher-level concurrency
	  tools.

	What
	- A wrapper around a runtime primitive (`hxrt::thread::ConditionHandle`) that models an internal
	  mutex plus a condition signal/broadcast channel.

	How
	- `acquire`/`release` manage the internal mutex.
	- `wait()` atomically releases the internal mutex and blocks until signaled, then re-acquires it.
**/
@:coreApi
class Condition {
	final __h: HxRef<ConditionHandle>;

	public function new():Void {
		__h = untyped __rust__("hxrt::thread::condition_new()");
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

	public function wait():Void {
		untyped __rust__("{0}.borrow().wait()", __h);
	}

	public function signal():Void {
		untyped __rust__("{0}.borrow().signal()", __h);
	}

	public function broadcast():Void {
		untyped __rust__("{0}.borrow().broadcast()", __h);
	}
}

