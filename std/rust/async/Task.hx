package rust.async;

/**
	rust.async.Task<T>

	Why
	- Async task helpers need a concrete typed handle for spawned work.

	What
	- Typedef alias to `hxrt.concurrent.TaskHandle<T>`.

	How
	- This is a pure type alias, so no wrapper class is emitted in generated Rust.
	- It belongs to the experimental `rust_async` preview; panic propagation, cancellation,
	  join/drop, and resource-release behavior are not admitted stable-major contracts.
**/
typedef Task<T> = hxrt.concurrent.TaskHandle<T>;
