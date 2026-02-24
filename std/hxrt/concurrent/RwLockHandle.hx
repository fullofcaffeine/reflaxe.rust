package hxrt.concurrent;

/**
	Opaque runtime read/write lock handle (`hxrt::concurrent::RwLockHandle<T>`).

	Why
	- `rust.concurrent.RwLock<T>` exposes typed read/write closures without leaking guard lifetimes.
	- Runtime Rust code owns locking internals and poison/ownership behavior.
**/
@:native("hxrt::concurrent::RwLockHandle")
extern class RwLockHandle<T> {}
