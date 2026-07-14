package hxrt.thread;

import sys.thread.Types.ThreadMessage;

/**
	`hxrt.thread.NativeThread` (Rust runtime binding)

	Why
	- `sys.thread.Thread` needs a small set of runtime hooks that return boundary-typed
	  message payloads.
	- Calling these hooks through raw `untyped __rust__` can leave unresolved monomorphs in
	  the typed AST and produce noisy backend warnings in user builds.

	What
	- Typed extern binding to `hxrt::thread` helpers used by `sys.thread.Thread`.

	How
	- `@:native("hxrt::thread")` maps this extern class to the runtime module.
	- Each `@:native(...)` static function maps to one Rust function with a concrete Haxe type.
**/
@:native("hxrt::thread")
extern class NativeThread {
	/**
		Returns the runtime id of the current OS thread.

		Why
		- `sys.thread.Thread.current()` and `sys.thread.EventLoop` binding logic must stay typed in
		  Haxe code to avoid raw `__rust__` injection fallbacks.
	**/
	@:native("thread_current_id")
	public static function currentId():Int;

	/**
		Spawns a thread that executes `job` and returns its runtime id.

		Why
		- Keeps `sys.thread.Thread.create(...)` fully typed at the Haxe boundary.

		What
		- The returned id remains live only for the spawned callback scope.
		- An uncaught Haxe throw is reported with `HXRT-THREAD-UNCAUGHT`; later sends fail with
		  `HXRT-THREAD-NOT-ALIVE`.

		How
		- HXRT owns registration through RAII and boxes runtime error strings as portable `HxString`
		  values so `catch (message:String)` works in portable generated code.
	**/
	@:native("thread_spawn")
	public static function spawn(job:() -> Void):Int;

	/**
		Spawns a thread, executes `job`, then runs the thread event loop.

		Why
		- Mirrors `Thread.createWithEventLoop(...)` without emitting raw injection snippets.

		How
		- Job and loop callbacks share the same unwind-safe registration and uncaught-error boundary.
	**/
	@:native("thread_spawn_with_event_loop")
	public static function spawnWithEventLoop(job:() -> Void):Int;

	/**
		Sends a message payload to another thread queue.

		Why: accepting messages for a removed registration would leak data indefinitely.
		What: throws the catchable portable String prefix `HXRT-THREAD-NOT-ALIVE` after termination.
		How: the runtime performs registry lookup and queue insertion as the native ownership boundary.
	**/
	@:native("thread_send_message")
	public static function sendMessage(threadId:Int, message:ThreadMessage):Void;

	@:native("thread_read_message")
	public static function readMessage(block:Bool):ThreadMessage;

	/**
		Event-loop bridge methods used by `sys.thread.EventLoop`.

		Why
		- These methods centralize the Rust runtime boundary in one typed extern API.
		- `sys.thread.EventLoop` can then remain pure Haxe code with no raw `__rust__`.

		What
		- Repeats are rescheduled before callbacks, cancellation removes future runs, and promised work is
		  counted without underflow.

		How
		- Callbacks execute outside the scheduler lock. `eventLoopRunPromised` throws
		  `HXRT-EVENTLOOP-PROMISE-UNDERFLOW` before enqueue when no promise is outstanding.
	**/
	@:native("event_loop_repeat")
	public static function eventLoopRepeat(threadId:Int, event:() -> Void, intervalMs:Int):Int;

	@:native("event_loop_cancel")
	public static function eventLoopCancel(threadId:Int, eventId:Int):Void;

	@:native("event_loop_promise")
	public static function eventLoopPromise(threadId:Int):Void;

	@:native("event_loop_run")
	public static function eventLoopRun(threadId:Int, event:() -> Void):Void;

	@:native("event_loop_run_promised")
	public static function eventLoopRunPromised(threadId:Int, event:() -> Void):Void;

	@:native("event_loop_progress")
	public static function eventLoopProgress(threadId:Int):Float;

	@:native("event_loop_wait")
	public static function eventLoopWait(threadId:Int, timeout:Null<Float>):Bool;

	@:native("event_loop_loop")
	public static function eventLoopLoop(threadId:Int):Void;
}
