package hxrt.concurrent;

/**
	Opaque runtime mutex handle (`hxrt::concurrent::MutexHandle<T>`).

	Why
	- `rust.concurrent.Mutex<T>` exposes closure-scoped mutable access in Haxe.
	- Lock storage and guard lifetimes are enforced by runtime Rust code.
**/
@:native("hxrt::concurrent::MutexHandle")
extern class MutexHandle<T> {}
