package rust.concurrent;

/**
	rust.concurrent.RwLock<T>

	Why
	- Rust-first read/write lock APIs need a concrete typed handle without exposing runtime internals.

	What
	- Typedef alias to `hxrt.concurrent.RwLockHandle<T>`.
	- User-facing operations are exposed in `rust.concurrent.RwLocks`.

	How
	- Keeping the handle as a typedef avoids generating an extra wrapper class in Rust output.
**/
typedef RwLock<T> = hxrt.concurrent.RwLockHandle<T>;
