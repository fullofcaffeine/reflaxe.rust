package sys.thread;

/**
	Thread-local storage implemented in pure Haxe on the Rust target.

	Why
	- `sys.thread.Tls<T>` is generic, and the Rust backend currently represents "null" via `Option<T>`.
	- Modeling a fully type-safe, nullable `Tls<T>.value:T` directly in Rust would require deeper
	  compiler/runtime work around untyped-null payload compatibility.

	What
	- A per-instance mapping from thread id to a stored value.

	How
	- Uses a per-instance `Mutex` to guard a `Map<Int, T>`.
	- Uses the Rust runtime thread id (`hxrt::thread::thread_current_id()`) as the key.
	- Setting to `null` removes the entry (matches the upstream advice to clear TLS before thread exit).
**/
class Tls<T> {
	final __mutex:Mutex = new Mutex();
	final __values:Map<Int, T> = [];

	public var value(get, set):T;

	public function new():Void {}

	inline function currentId():Int {
		return untyped __rust__("hxrt::thread::thread_current_id()");
	}

	function get_value():T {
		var id = currentId();
		__mutex.acquire();
		var v = __values.get(id);
		__mutex.release();
		return v;
	}

	function set_value(v:T):T {
		var id = currentId();
		__mutex.acquire();
		if (v == null) {
			__values.remove(id);
		} else {
			__values.set(id, v);
		}
		__mutex.release();
		return v;
	}
}
