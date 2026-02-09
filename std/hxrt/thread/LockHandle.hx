package hxrt.thread;

/**
	Opaque runtime handle for `sys.thread.Lock` (`hxrt::thread::LockHandle`).

	Why
	- `sys.thread.Lock` is implemented in Haxe (in `std/sys/thread/Lock.hx`) but the underlying
	  synchronization primitive is implemented in the Rust runtime for correctness and performance.

	What
	- An extern marker type mapped to the Rust struct `hxrt::thread::LockHandle`.

	How
	- The Haxe wrapper stores this as `rust.HxRef<LockHandle>`.
	- Operations are implemented via `__rust__` injections calling methods on the handle.
**/
@:native("hxrt::thread::LockHandle")
extern class LockHandle {}

