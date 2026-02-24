package rust.concurrent;

/**
	rust.concurrent.Mutex<T>

	Why
	- Rust-first mutex APIs need a concrete typed handle without exposing runtime internals.

	What
	- Typedef alias to `hxrt.concurrent.MutexHandle<T>`.
	- User-facing operations are exposed in `rust.concurrent.Mutexes`.

	How
	- Keeping the handle as a typedef avoids generating an extra wrapper class in Rust output.
**/
typedef Mutex<T> = hxrt.concurrent.MutexHandle<T>;
