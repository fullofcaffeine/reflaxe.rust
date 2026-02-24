package rust.concurrent;

/**
	rust.concurrent.Task<T>

	Why
	- Rusty-profile task APIs need a concrete typed handle for spawned work.

	What
	- Typedef alias to `hxrt.concurrent.TaskHandle<T>`.
	- User-facing operations are exposed in `rust.concurrent.Tasks`.

	How
	- Keeping the handle as a typedef avoids generating an extra wrapper class in Rust output.
**/
typedef Task<T> = hxrt.concurrent.TaskHandle<T>;
