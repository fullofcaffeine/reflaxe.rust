package rust.concurrent;

import rust.HxRef;
import rust.Ref;

/**
	rust.concurrent.Mutexes

	Why
	- `Mutex<T>` is a typed runtime handle. Methods are provided as namespace functions to keep
	  generated Rust minimal and avoid wrapper-class generic bound noise.

	What
	- `create(...)`, `get(...)`, `set(...)`, `replace(...)`, `update(...)`.

	How
	- This is an extern binding to `hxrt::concurrent`; no wrapper class is emitted.
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
}
