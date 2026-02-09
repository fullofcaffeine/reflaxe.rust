package sys.thread;

/**
	OS thread API for the Rust target.

	Why
	- The upstream Haxe std defines `sys.thread.Thread` as an extern abstract, implemented per-target.
	- For Rust we want true OS threads, message queues, and compatibility with Haxe std patterns.

	What
	- A small wrapper around `hxrt::thread`:
	  - `create(job)` spawns an OS thread.
	  - `sendMessage` sends a `Dynamic` to another thread's queue.
	  - `readMessage(block)` reads from the current thread's queue.

	How
	- Each thread has a small integer id (0 = main thread) stored in Rust thread-local storage.
	- Event loop support is implemented in Haxe using `sys.thread.EventLoop` (upstream), and is
	  intentionally minimal here: only `runWithEventLoop` / `createWithEventLoop` are provided.
**/
class Thread {
	final __id: Int;

	// Event loop is optional per-thread. We track it in a global map guarded by a mutex.
	static final __loopsMutex: Mutex = new Mutex();
	static final __loops: Map<Int, EventLoop> = [];

	function new(id: Int) {
		__id = id;
	}

	public var events(get, never): EventLoop;
	function get_events(): EventLoop {
		var id = __id;
		__loopsMutex.acquire();
		var loop = __loops.get(id);
		__loopsMutex.release();
		return loop;
	}

	public function sendMessage(msg: Dynamic): Void {
		untyped __rust__("hxrt::thread::thread_send_message({0}, {1})", __id, msg);
	}

	public static function current(): Thread {
		var id: Int = untyped __rust__("hxrt::thread::thread_current_id()");
		return new Thread(id);
	}

	public static function create(job: () -> Void): Thread {
		var id: Int = untyped __rust__("hxrt::thread::thread_spawn({0})", job);
		return new Thread(id);
	}

	public static function runWithEventLoop(job: () -> Void): Void {
		var id: Int = untyped __rust__("hxrt::thread::thread_current_id()");

		__loopsMutex.acquire();
		var existing = __loops.exists(id);
		if (!existing) __loops.set(id, new EventLoop());
		var loop = __loops.get(id);
		__loopsMutex.release();

		job();

		if (!existing) {
			loop.loop();
			__loopsMutex.acquire();
			__loops.remove(id);
			__loopsMutex.release();
		}
	}

	public static function createWithEventLoop(job: () -> Void): Thread {
		return create(() -> runWithEventLoop(job));
	}

	/**
		Read a message from the *current* thread's queue.
		Returns `null` if `block` is `false` and no message is available.
	**/
	public static function readMessage(block: Bool): Dynamic {
		return untyped __rust__("hxrt::thread::thread_read_message({0})", block);
	}

	private static function processEvents(): Void {
		var loop = Thread.current().events;
		if (loop != null) loop.progress();
	}
}
