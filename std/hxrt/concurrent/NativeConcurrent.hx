package hxrt.concurrent;

import rust.HxRef;
import rust.Option;
import rust.Ref;

/**
	`hxrt.concurrent.NativeConcurrent` (typed runtime boundary)

	Why
	- `rust.concurrent.*` needs Rust-native primitives (channels/tasks/locks) while preserving a
	  typed Haxe API surface.
	- Direct app-level `untyped __rust__` calls are intentionally disallowed in strict modes.

	What
	- Typed extern bindings for `hxrt::concurrent` runtime helpers.

	How
	- All API boundaries are concrete generic signatures.
	- Lock APIs use value-copy/update operations so the borrow/guard lifetime stays internal to
	  runtime Rust code.
**/
@:native("hxrt::concurrent")
extern class NativeConcurrent {
	@:native("channel_new")
	public static function channelNew<T>():HxRef<ChannelHandle<T>>;

	@:native("channel_send")
	public static function channelSend<T>(channel:Ref<HxRef<ChannelHandle<T>>>, value:T):Void;

	@:native("channel_recv")
	public static function channelRecv<T>(channel:Ref<HxRef<ChannelHandle<T>>>):T;

	@:native("channel_try_recv")
	public static function channelTryRecv<T>(channel:Ref<HxRef<ChannelHandle<T>>>):Option<T>;

	@:native("task_spawn")
	public static function taskSpawn<T>(job:() -> T):HxRef<TaskHandle<T>>;

	@:native("task_join")
	public static function taskJoin<T>(task:Ref<HxRef<TaskHandle<T>>>):T;

	@:native("mutex_new")
	public static function mutexNew<T>(value:T):HxRef<MutexHandle<T>>;

	@:native("mutex_get")
	public static function mutexGet<T>(mutex:Ref<HxRef<MutexHandle<T>>>):T;

	@:native("mutex_set")
	public static function mutexSet<T>(mutex:Ref<HxRef<MutexHandle<T>>>, value:T):Void;

	@:native("mutex_replace")
	public static function mutexReplace<T>(mutex:Ref<HxRef<MutexHandle<T>>>, value:T):T;

	@:native("mutex_update")
	public static function mutexUpdate<T>(mutex:Ref<HxRef<MutexHandle<T>>>, callback:(T) -> T):T;

	@:native("rw_lock_new")
	public static function rwLockNew<T>(value:T):HxRef<RwLockHandle<T>>;

	@:native("rw_lock_read")
	public static function rwLockRead<T>(lock:Ref<HxRef<RwLockHandle<T>>>):T;

	@:native("rw_lock_write")
	public static function rwLockWrite<T>(lock:Ref<HxRef<RwLockHandle<T>>>, value:T):Void;

	@:native("rw_lock_replace")
	public static function rwLockReplace<T>(lock:Ref<HxRef<RwLockHandle<T>>>, value:T):T;

	@:native("rw_lock_update")
	public static function rwLockUpdate<T>(lock:Ref<HxRef<RwLockHandle<T>>>, callback:(T) -> T):T;
}
