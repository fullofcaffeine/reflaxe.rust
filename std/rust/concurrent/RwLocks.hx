package rust.concurrent;

import rust.HxRef;
import rust.Ref;

/**
	rust.concurrent.RwLocks

	Why
	- `RwLock<T>` is a typed runtime handle. Methods are provided as namespace functions to keep
	  generated Rust minimal and avoid wrapper-class generic bound noise.

	What
	- `create(...)`, `read(...)`, `write(...)`, `replace(...)`, `update(...)`.

	How
	- This is an extern binding to `hxrt::concurrent`; no wrapper class is emitted.
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
}
