package sys.thread;

/**
	When an event loop has an available event to execute.
**/
enum NextEventTime {
	/** There's already an event waiting to be executed */
	Now;
	/** No new events are expected. */
	Never;
	/**
		An event is expected to arrive at any time.
		If `time` is specified, then the event will be ready at that time for sure.
	**/
	AnyTime(time: Null<Float>);
	/** An event is expected to be ready for execution at `time`. */
	At(time: Float);
}

/**
	An event loop implementation used for `sys.thread.Thread`.

	Why
	- Threaded Haxe targets route `haxe.EntryPoint` scheduling through `sys.thread.EventLoop`.
	- The Rust target needs a deterministic, OS-thread-safe implementation.

	What
	- One-shot events (`run` / `runPromised`) executed on the owning thread.
	- Promises (`promise`) to keep loops alive until events are delivered.
	- Minimal repeating timers (`repeat` / `cancel`) based on seconds since program start.

	How
	- This is backed by the Rust runtime (`hxrt::thread`) per-thread state.
	- The Haxe class is a thin wrapper that preserves the standard API shape.
**/
@:coreApi
@:allow(sys.thread.Thread)
class EventLoop {
	var __threadId: Int;

	public function new(): Void {
		__threadId = untyped __rust__("hxrt::thread::thread_current_id()");
	}

	/**
		Create an `EventLoop` wrapper bound to a specific thread id.

		This keeps the public `new():Void` signature identical to the upstream core type, while still
		allowing `Thread.events` to return an event loop for arbitrary threads (e.g. the main thread).
	**/
	static function __fromThreadId(threadId: Int): EventLoop {
		var loop = new EventLoop();
		loop.__threadId = threadId;
		return loop;
	}

	public function repeat(event: () -> Void, intervalMs: Int): EventHandler {
		var id: Int = untyped __rust__("hxrt::thread::event_loop_repeat({0}, {1}, {2})", __threadId, event, intervalMs);
		return cast id;
	}

	public function cancel(eventHandler: EventHandler): Void {
		var id: Int = cast eventHandler;
		untyped __rust__("hxrt::thread::event_loop_cancel({0}, {1})", __threadId, id);
	}

	public function promise(): Void {
		untyped __rust__("hxrt::thread::event_loop_promise({0})", __threadId);
	}

	public function run(event: () -> Void): Void {
		untyped __rust__("hxrt::thread::event_loop_run({0}, {1})", __threadId, event);
	}

	public function runPromised(event: () -> Void): Void {
		untyped __rust__("hxrt::thread::event_loop_run_promised({0}, {1})", __threadId, event);
	}

	public function progress(): NextEventTime {
		var nextAt: Float = untyped __rust__("hxrt::thread::event_loop_progress({0})", __threadId);
		return if (nextAt == -2.0) {
			Now;
		} else if (nextAt == -1.0) {
			Never;
		} else if (nextAt == -3.0) {
			AnyTime(null);
		} else {
			At(nextAt);
		}
	}

	public function wait(?timeout: Float): Bool {
		return untyped __rust__("hxrt::thread::event_loop_wait({0}, {1})", __threadId, timeout);
	}

	public function loop(): Void {
		untyped __rust__("hxrt::thread::event_loop_loop({0})", __threadId);
	}
}

abstract EventHandler(Int) from Int to Int {}
