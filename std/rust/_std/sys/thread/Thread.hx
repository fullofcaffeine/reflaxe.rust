package sys.thread;

import hxrt.thread.NativeThread;
import sys.thread.Types.ThreadMessage;

/**
	OS thread API for the Rust target.

	Why
	- Haxe's `sys.thread.*` implies real OS threads with message queues and synchronization.
	- The Rust target provides a native runtime (`hxrt`) and implements this API on top of it.

	What
	- `Thread.create(job)` spawns an OS thread that executes `job`.
	- `Thread.current()` identifies the current OS thread (0 = main thread).
	- `sendMessage` / `readMessage` implement per-thread message queues with boundary payloads
	  (`ThreadMessage`).
	- `events` exposes a per-thread `EventLoop` compatible with `haxe.EntryPoint` expectations.

	How
	- Each thread has a small integer id stored in Rust thread-local storage.
	- `sys.thread.EventLoop` is backed by runtime queues and timers, so it can be used without
	  relying on Haxe static-field codegen (keeps the POC smaller).
	- All runtime calls go through `hxrt.thread.NativeThread` extern bindings, so this class stays
	  beginner-friendly Haxe code (no raw `__rust__` snippets in method bodies).
	- A spawned thread owns its runtime registration through an unwind-safe scope. Normal return,
	  an uncaught Haxe throw, or a Rust panic removes that registration before the thread ends.
	- Because this API has no join/result channel, an uncaught Haxe exception terminates only the child
	  and writes a best-effort diagnostic beginning with `HXRT-THREAD-UNCAUGHT`. Its exact payload prose
	  is not a compatibility contract.
**/
class Thread {
	final __id:Int;

	function new(id:Int) {
		__id = id;
	}

	/**
		Event loop of this thread.

		Note: the current implementation is backed by the runtime and does not integrate Haxe's
		`haxe.MainLoop` yet. It's sufficient for `haxe.EntryPoint` usage (`run`, `promise`,
		`runPromised`, `loop`).
	**/
	public var events(get, never):EventLoop;

	function get_events():EventLoop {
		return EventLoop.__fromThreadId(__id);
	}

	/**
		Send a boundary payload to this thread.

		Why: a dead thread must not accept data into a queue that no execution context can drain.
		What: queues `msg` while the thread registration is live; afterward it throws a catchable String
		beginning with `HXRT-THREAD-NOT-ALIVE`.
		How: HXRT resolves the thread id under the registry lock before acquiring its message queue.
	**/
	public function sendMessage(msg:ThreadMessage):Void {
		NativeThread.sendMessage(__id, msg);
	}

	/** Return a typed wrapper for the current runtime thread id. **/
	public static function current():Thread {
		var id:Int = NativeThread.currentId();
		return new Thread(id);
	}

	/**
		Spawn an OS thread for `job`.

		Why: Haxe `sys.thread` promises real parallel execution rather than cooperative task emulation.
		What: returns immediately with a message-capable handle. An uncaught Haxe exception ends only the
		child, emits `HXRT-THREAD-UNCAUGHT`, and makes future sends fail with
		`HXRT-THREAD-NOT-ALIVE`.
		How: HXRT installs thread-local identity and an RAII registration guard around the callback.
	**/
	public static function create(job:() -> Void):Thread {
		var id:Int = NativeThread.spawn(job);
		return new Thread(id);
	}

	/**
		Run `job` and then drain the current thread's event loop.

		This is a direct Rust-target scheduler path; it does not imply blanket `haxe.MainLoop` parity.
		Callback exceptions propagate to this caller because no new OS-thread boundary is created.
	**/
	public static function runWithEventLoop(job:() -> Void):Void {
		job();
		var id:Int = NativeThread.currentId();
		NativeThread.eventLoopLoop(id);
	}

	/**
		Spawn an OS thread that runs `job` and then its EventLoop.

		Why: queued/promised/repeating work must share the spawned thread's liveness boundary.
		What: an uncaught exception from either `job` or an EventLoop callback terminates only that child,
		reports `HXRT-THREAD-UNCAUGHT`, and removes the registration.
		How: both phases execute inside the same HXRT RAII registration scope.
	**/
	public static function createWithEventLoop(job:() -> Void):Thread {
		var id:Int = NativeThread.spawnWithEventLoop(job);
		return new Thread(id);
	}

	/**
		Read a message from the *current* thread's queue.
		Returns `null` if `block` is `false` and no message is available.
	**/
	public static function readMessage(block:Bool):ThreadMessage {
		return NativeThread.readMessage(block);
	}

	/**
		Read a message and decode it to a typed value immediately.

		`decode` receives the raw payload as `Any` and should return `null` when the payload
		does not match the expected shape.
	**/
	public static function readMessageAs<T>(block:Bool, decode:Any->Null<T>):Null<T> {
		var raw:Any = cast readMessage(block);
		if (raw == null)
			return null;
		return decode(raw);
	}

	/**
		Convenience typed read for string payloads.
	**/
	public static function readMessageString(block:Bool):Null<String> {
		var raw:Any = cast readMessage(block);
		if (raw == null)
			return null;
		if (Std.isOfType(raw, String))
			return cast raw;
		return null;
	}

	private static function processEvents():Void {
		// Minimal integration point for upstream APIs. Future work: connect to `haxe.MainLoop`.
		Thread.current().events.progress();
	}
}
