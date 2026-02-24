package rust.concurrent;

import rust.HxRef;
import rust.Ref;

/**
	rust.concurrent.Tasks

	Why
	- `Task<T>` is generic, and static generic methods on generic classes currently map awkwardly
	  in Rust output (extra bound plumbing).

	What
	- Factory namespace for spawning typed tasks.

	How
	- This is an extern binding to `hxrt::concurrent`; no wrapper class is emitted.
**/
@:native("hxrt::concurrent")
extern class Tasks {
	@:native("task_spawn")
	public static function spawn<T>(job:() -> T):HxRef<Task<T>>;

	@:native("task_join")
	public static function join<T>(task:Ref<HxRef<Task<T>>>):T;
}
