package haxe;

/**
	`haxe.MainLoop` Rust-target override.

	Why
	- Upstream `haxe.MainLoop` is part of the public portable API surface and is referenced by
	  `haxe.EntryPoint`.
	- `reflaxe.rust` previously typed these modules from upstream std but did not emit them, which
	  meant real target-side `MainLoop` / `EntryPoint` smoke cases could not compile.
	- The Rust target also needs a concrete main-loop implementation that can wake `EntryPoint.run()`
	  when events are added from other threads.

	What
	- A close Rust-target adaptation of the upstream `haxe.MainLoop` linked-list event queue.
	- Keeps the standard API shape: `MainEvent`, `MainLoop.add`, `hasEvents`, `addThread`,
	  `runInMainThread`, and internal `tick()` ordering semantics.

	How
	- Event ordering follows the upstream sort rules (`priority` first, then earliest `nextRun`).
	- Time stamps are based on `Sys.time()` instead of `haxe.Timer.stamp()` so this override stays
	  self-contained under the Rust stdlib emission model.
	- `add()` calls `EntryPoint.wakeup()` so an already-running `EntryPoint.run()` loop notices newly
	  scheduled main-loop work promptly.
**/
class MainEvent {
	/**
		Internal callback payload for this scheduled event.

		Why
		- Function references on this backend lower to Rust trait-object handles.
		- Comparing those handles directly to `null` is not a stable or ergonomic contract for the
		  generated Rust because the handle type does not implement `PartialEq`.

		What
		- The callback is always stored as a live function value.
		- `active` controls whether the event is still runnable.

		How
		- `call()` checks `active` before invoking the callback.
		- `stop()` flips `active` to `false` instead of nulling the callback field.
	**/
	public var callback(default, null):Void->Void;

	/**
		Intrusive linked-list pointers used by `MainLoop`.

		Why
		- The upstream implementation keeps events in a doubly linked list for stable priority and
		  wakeup ordering.
		- The Rust backend must model the "no neighbor" state explicitly instead of relying on
		  implicit default construction.

		What
		- `prev` points to the previous pending event, or `null` at the head.
		- `next` points to the next pending event, or `null` at the tail.

		How
		- These fields are public so the sibling Rust modules emitted for `MainLoop` and `MainEvent`
		  can update the list without private-access codegen traps.
	**/
	public var prev:Null<MainEvent> = null;

	public var next:Null<MainEvent> = null;

	/**
		Whether this event should still fire.
	**/
	public var active:Bool = true;

	/**
		Tells if the event can lock the process from exiting (default: `true`).
	**/
	public var isBlocking:Bool = true;

	public var nextRun(default, null):Float;
	public var priority(default, null):Int;

	function new(f:Void->Void, p:Int) {
		this.callback = f;
		this.priority = p;
		nextRun = Math.NEGATIVE_INFINITY;
	}

	static inline function stamp():Float {
		return Sys.time();
	}

	/**
		Delay the execution of the event for the given time, in seconds.
		If `t` is `null`, then the event will be run at `tick()` time.
	**/
	public function delay(t:Null<Float>):Void {
		nextRun = t == null ? Math.NEGATIVE_INFINITY : stamp() + t;
	}

	/**
		Call the event. Will do nothing if the event has been stopped.
	**/
	public inline function call():Void {
		if (active)
			callback();
	}

	/**
		Stop the event from firing anymore.
	**/
	public function stop():Void {
		if (!active)
			return;
		active = false;
		nextRun = Math.NEGATIVE_INFINITY;
		if (prev == null)
			@:privateAccess MainLoop.pending = next;
		else
			prev.next = next;
		if (next != null)
			next.prev = prev;
	}
}

@:access(haxe.MainEvent)
class MainLoop {
	static var pending:Null<MainEvent>;

	public static var threadCount(get, never):Int;

	inline static function get_threadCount():Int {
		return EntryPoint.threadCount;
	}

	static inline function stamp():Float {
		return Sys.time();
	}

	public static function hasEvents():Bool {
		var p = pending;
		while (p != null) {
			if (p.isBlocking)
				return true;
			p = p.next;
		}
		return false;
	}

	public static function addThread(f:Void->Void):Void {
		EntryPoint.addThread(f);
	}

	public static function runInMainThread(f:Void->Void):Void {
		EntryPoint.runInMainThread(f);
	}

	/**
		Add a pending event to be run in the main loop.
	**/
	public static function add(f:Null<Void->Void>, priority:Int = 0):MainEvent {
		if (f == null)
			throw "Event function is null";
		var e = new MainEvent(f, priority);
		var head = pending;
		if (head != null)
			head.prev = e;
		e.next = head;
		pending = e;
		EntryPoint.wakeup();
		return e;
	}

	static function sortEvents():Void {
		var list = pending;
		if (list == null)
			return;

		var insize = 1;
		var nmerges:Int;
		var p:MainEvent;
		var q:MainEvent;
		var e:MainEvent;
		var tail:MainEvent;
		var psize:Int;
		var qsize:Int;

		while (true) {
			p = list;
			list = null;
			tail = null;
			nmerges = 0;
			while (p != null) {
				nmerges++;
				q = p;
				psize = 0;
				for (_ in 0...insize) {
					psize++;
					q = q.next;
					if (q == null)
						break;
				}
				qsize = insize;
				while (psize > 0 || (qsize > 0 && q != null)) {
					if (psize == 0) {
						e = q;
						q = q.next;
						qsize--;
					} else if (qsize == 0
						|| q == null
						|| (p.priority > q.priority || (p.priority == q.priority && p.nextRun <= q.nextRun))) {
						e = p;
						p = p.next;
						psize--;
					} else {
						e = q;
						q = q.next;
						qsize--;
					}
					if (tail != null)
						tail.next = e;
					else
						list = e;
					e.prev = tail;
					tail = e;
				}
				p = q;
			}
			tail.next = null;
			if (nmerges <= 1)
				break;
			insize *= 2;
		}

		list.prev = null;
		pending = list;
	}

	/**
		Run pending events and return the time until the next event should fire.
		Returns `-1` when no further blocking work remains.
	**/
	static function tick():Float {
		sortEvents();
		var e = pending;
		var now = stamp();
		var wait = 1e9;
		while (e != null) {
			var next = e.next;
			var wt = e.nextRun - now;
			if (wt <= 0) {
				wait = 0;
				e.call();
			} else if (wait > wt) {
				wait = wt;
			}
			e = next;
		}
		return wait;
	}
}
