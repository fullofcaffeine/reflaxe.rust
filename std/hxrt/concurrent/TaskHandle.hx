package hxrt.concurrent;

/**
	Opaque runtime task handle (`hxrt::concurrent::TaskHandle<T>`).

	Why
	- `rust.concurrent.Task<T>` wraps a join handle that can be consumed exactly once.
	- The opaque handle keeps ownership rules in runtime Rust code.
**/
@:native("hxrt::concurrent::TaskHandle")
extern class TaskHandle<T> {}
