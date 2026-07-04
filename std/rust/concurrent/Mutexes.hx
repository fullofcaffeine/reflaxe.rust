package rust.concurrent;

import rust.HxRef;
import rust.MutRef;
import rust.Ref;

/**
	rust.concurrent.Mutexes

	Why
	- `Mutex<T>` is a typed runtime handle. Methods are provided as namespace functions to keep
	  generated Rust minimal and avoid wrapper-class generic bound noise.

	What
	- `create(...)`, `get(...)`, `set(...)`, `replace(...)`, `update(...)`.
	- `withRef(...)` and `withMut(...)` expose the lock as a scoped borrow token for code that
	  needs read/write access without cloning the protected value.

	How
	- This is an extern binding to `hxrt::concurrent`; no wrapper class is emitted.
	- The Rust runtime keeps the actual `MutexGuard` inside the helper and drops it when the callback
	  returns. The Haxe callback receives `rust.Ref<T>` / `rust.MutRef<T>`, so the typed borrow-region
	  analyzer rejects attempts to return, store, or wrap the guard token.
**/
@:native("hxrt::concurrent")
extern class Mutexes {
	@:native("mutex_new")
	public static function create<T>(value:T):HxRef<Mutex<T>>;

	@:native("mutex_get")
	public static function get<T>(mutex:Ref<HxRef<Mutex<T>>>):T;

	@:native("mutex_set")
	public static function set<T>(mutex:Ref<HxRef<Mutex<T>>>, value:T):Void;

	@:native("mutex_replace")
	public static function replace<T>(mutex:Ref<HxRef<Mutex<T>>>, value:T):T;

	@:native("mutex_update")
	public static function update<T>(mutex:Ref<HxRef<Mutex<T>>>, callback:(T) -> T):T;

	@:native("mutex_with_ref")
	public static function withRef<T, R>(mutex:Ref<HxRef<Mutex<T>>>, callback:(Ref<T>) -> R):R;

	@:native("mutex_with_mut")
	public static function withMut<T, R>(mutex:Ref<HxRef<Mutex<T>>>, callback:(MutRef<T>) -> R):R;
}
