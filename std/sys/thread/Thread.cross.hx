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

	public function sendMessage(msg:ThreadMessage):Void {
		untyped __rust__("hxrt::thread::thread_send_message({0}, {1})", __id, msg);
	}

	public static function current():Thread {
		var id:Int = untyped __rust__("hxrt::thread::thread_current_id()");
		return new Thread(id);
	}

	public static function create(job:() -> Void):Thread {
		var id:Int = untyped __rust__("hxrt::thread::thread_spawn({0})", job);
		return new Thread(id);
	}

	public static function runWithEventLoop(job:() -> Void):Void {
		job();
		var id:Int = untyped __rust__("hxrt::thread::thread_current_id()");
		untyped __rust__("hxrt::thread::event_loop_loop({0})", id);
	}

	public static function createWithEventLoop(job:() -> Void):Thread {
		var id:Int = untyped __rust__("hxrt::thread::thread_spawn_with_event_loop({0})", job);
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
