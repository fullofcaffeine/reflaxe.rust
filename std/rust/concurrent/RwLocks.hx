package rust.concurrent;

import rust.HxRef;
import rust.MutRef;
import rust.Ref;

/**
	rust.concurrent.RwLocks

	Why
	- `RwLock<T>` is a typed runtime handle. Methods are provided as namespace functions to keep
	  generated Rust minimal and avoid wrapper-class generic bound noise.

	What
	- `create(...)`, `read(...)`, `write(...)`, `replace(...)`, `update(...)`.
	- `withRead(...)` and `withWrite(...)` expose read/write lock guards as scoped borrow tokens for
	  non-cloning access.
	- `update(...)`, `withRead(...)`, and `withWrite(...)` keep one atomic critical section for the
	  complete callback.

	How
	- This is an extern binding to `hxrt::concurrent`; no wrapper class is emitted.
	- The Rust runtime keeps the actual `RwLockReadGuard` / `RwLockWriteGuard` inside the helper and
	  drops it when the callback returns. The Haxe callback receives `rust.Ref<T>` / `rust.MutRef<T>`,
	  so escaped guard tokens are diagnosed by the borrow-region analyzer before Rust codegen.
	- The compiler cannot know which shared handle arbitrary callback code will touch. The runtime
	  therefore checks the handle identity before every RwLock operation. Reading, writing, upgrading,
	  or otherwise accessing the same handle while its callback owns a guard throws a catchable String
	  beginning with `HXRT-LOCK-REENTRANCY` instead of deadlocking; callback throws clear the scope.
	- Nested access to a different handle is allowed. Code that takes multiple locks across threads
	  must still use one consistent application-owned lock order.
**/
@:native("hxrt::concurrent")
extern class RwLocks {
	@:native("rw_lock_new")
	public static function create<T>(value:T):HxRef<RwLock<T>>;

	@:native("rw_lock_read")
	public static function read<T>(lock:Ref<HxRef<RwLock<T>>>):T;

	@:native("rw_lock_write")
	public static function write<T>(lock:Ref<HxRef<RwLock<T>>>, value:T):Void;

	@:native("rw_lock_replace")
	public static function replace<T>(lock:Ref<HxRef<RwLock<T>>>, value:T):T;

	@:native("rw_lock_update")
	public static function update<T>(lock:Ref<HxRef<RwLock<T>>>, callback:(T) -> T):T;

	@:native("rw_lock_with_read")
	public static function withRead<T, R>(lock:Ref<HxRef<RwLock<T>>>, callback:(Ref<T>) -> R):R;

	@:native("rw_lock_with_write")
	public static function withWrite<T, R>(lock:Ref<HxRef<RwLock<T>>>, callback:(MutRef<T>) -> R):R;
}
