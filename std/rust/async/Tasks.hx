package rust.async;

import rust.HxRef;
import rust.Ref;

/**
	rust.async.Tasks

	Why
	- Rust-first async code needs typed task helpers without emitting wrapper glue that can
	  lose Rust trait bounds on generic parameters.

	What
	- Extern surface for async task spawning and joining.

	How
	- Binds directly to `hxrt::async_` helper functions (`task_spawn` / `task_join`).
	- Runtime bridge performs `Future<T> -> T` boundary via `block_on` inside the spawned task.
**/
@:native("hxrt::async_")
extern class Tasks {
	@:native("task_spawn")
	public static function spawn<T>(job:() -> Future<T>):HxRef<Task<T>>;

	@:native("task_join")
	public static function join<T>(task:Ref<HxRef<Task<T>>>):T;
}
