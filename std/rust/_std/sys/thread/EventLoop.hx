package sys.thread;

import hxrt.thread.NativeThread;

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
	AnyTime(time:Null<Float>);

	/** An event is expected to be ready for execution at `time`. */
	At(time:Float);
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
	- Runtime calls are routed through `hxrt.thread.NativeThread`, keeping this file typed and
	  approachable for new contributors.
	- Repeating events advance their next scheduled time before their callback runs. If a callback
	  throws, the Haxe exception propagates to `progress()` / `loop()` without silently deleting the
	  repeating registration; a callback that cancels itself stays cancelled even when it then throws.
	- `runPromised()` consumes exactly one prior `promise()`. An unmatched call throws a catchable
	  String beginning with `HXRT-EVENTLOOP-PROMISE-UNDERFLOW` and does not enqueue the callback.
**/
@:coreApi
@:allow(sys.thread.Thread)
class EventLoop {
	var __threadId:Int;

	public function new():Void {
		__threadId = NativeThread.currentId();
	}

	/**
		Create an `EventLoop` wrapper bound to a specific thread id.

		This keeps the public `new():Void` signature identical to the upstream core type, while still
		allowing `Thread.events` to return an event loop for arbitrary threads (e.g. the main thread).
	**/
	static function __fromThreadId(threadId:Int):EventLoop {
		var loop = new EventLoop();
		loop.__threadId = threadId;
		return loop;
	}

	/**
		Schedule a repeating callback on this loop.

		Why: timer registration must survive a callback throw without corrupting scheduler state.
		What: returns a handle that can cancel future invocations; intervals below one millisecond are
		clamped to one millisecond to prevent a busy loop.
		How: HXRT advances and reinserts the timer before invoking the callback, outside the scheduler
		lock. The callback may cancel its own already-rescheduled handle.
	**/
	public function repeat(event:() -> Void, intervalMs:Int):EventHandler {
		var id:Int = NativeThread.eventLoopRepeat(__threadId, event, intervalMs);
		return cast id;
	}

	/**
		Cancel future invocations of a repeating callback.

		Why: cancellation must remain valid from inside the callback, including immediately before a
		Haxe throw.
		What: prevents a not-yet-started callback in the current progress pass and all future invocations;
		cancelling an absent/already-cancelled handle is a no-op.
		How: the runtime removes the pre-rescheduled entry under the owning loop's state lock.
	**/
	public function cancel(eventHandler:EventHandler):Void {
		var id:Int = cast eventHandler;
		NativeThread.eventLoopCancel(__threadId, id);
	}

	/**
		Declare that one future callback will arrive through `runPromised()`.

		Why: a loop with no queued work must remain alive while an external producer still owes work.
		What: increments the outstanding promise count by exactly one.
		How: HXRT updates the per-thread count atomically and rejects counter overflow rather than
		wrapping or panicking.
	**/
	public function promise():Void {
		NativeThread.eventLoopPromise(__threadId);
	}

	/**
		Queue a one-shot callback for the owning thread.

		Why: producers on other threads need a typed way to wake this loop without executing application
		code under a scheduler lock.
		What: schedules `event` for the next `progress()` / `loop()` pass.
		How: HXRT enqueues the callback and signals the owning loop's condition variable.
	**/
	public function run(event:() -> Void):Void {
		NativeThread.eventLoopRun(__threadId, event);
	}

	/**
		Queue one previously promised callback.

		Why: silently allowing more deliveries than promises can make loop-liveness state negative and
		hide producer bugs.
		What: consumes exactly one outstanding promise and queues `event`; without a matching promise it
		throws `HXRT-EVENTLOOP-PROMISE-UNDERFLOW` and queues nothing.
		How: validation, decrement, and enqueue happen under one per-thread state lock.
	**/
	public function runPromised(event:() -> Void):Void {
		NativeThread.eventLoopRunPromised(__threadId, event);
	}

	/**
		Execute currently due callbacks once and describe the next expected work.

		Why: callers need explicit scheduler progress without committing to the blocking `loop()` API.
		What: propagates callback Haxe exceptions to the caller after leaving scheduler state consistent.
		How: repeating transitions are committed before callbacks; one-shot callbacks are then drained and
		executed outside the state lock.
	**/
	public function progress():NextEventTime {
		var nextAt:Float = NativeThread.eventLoopProgress(__threadId);
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

	/**
		Wait for queued, scheduled, or promised work.

		Why: a thread should block without polling when work is expected later.
		What: returns false only when no work is expected; otherwise waits indefinitely or up to `timeout`.
		How: HXRT uses the owning loop's condition variable and rechecks state in later progress passes.
	**/
	public function wait(?timeout:Float):Bool {
		return NativeThread.eventLoopWait(__threadId, timeout);
	}

	/**
		Run until no queued, repeating, or promised work remains.

		Why: `Thread.createWithEventLoop` needs an explicit target-side lifecycle for scheduled work.
		What: repeatedly progresses and waits; callback Haxe exceptions propagate to the thread boundary.
		How: the spawned-thread boundary reports an uncaught callback with `HXRT-THREAD-UNCAUGHT`, removes
		the dead thread registration through RAII, and terminates only that child thread.
	**/
	public function loop():Void {
		NativeThread.eventLoopLoop(__threadId);
	}
}

abstract EventHandler(Int) from Int to Int {}
