package sys.thread;

/**
	A Deque is a double-ended queue with a `pop` method that can block until an element is available.

	Why
	- The upstream Haxe stdlib uses `sys.thread.Deque<T>` as a synchronization primitive.
	- Thread pools (`FixedThreadPool` / `ElasticThreadPool`) depend on a blocking `pop` to avoid busy loops.

	What
	- `add(i)` enqueues at the back.
	- `push(i)` enqueues at the front.
	- `pop(block)` dequeues from the front, optionally blocking until an element exists.

	How
	- This implementation is pure Haxe and uses `Lock` as a counting semaphore:
	  each enqueue does exactly one `release()`, and each successful `pop` consumes one `wait()`.
	- Queue mutation is guarded by a `Mutex` so it is safe across OS threads.
**/
@:coreApi
class Deque<T> {
	final __mutex:Mutex = new Mutex();
	final __available:Lock = new Lock();
	final __items:Array<T> = [];

	public function new():Void {}

	public function add(i:T):Void {
		// Avoid holding the Deque object's internal borrow across the potentially-blocking acquire.
		final m = __mutex;
		final items = __items;
		final avail = __available;

		m.acquire();
		items.push(i);
		m.release();

		avail.release();
	}

	public function push(i:T):Void {
		final m = __mutex;
		final items = __items;
		final avail = __available;

		m.acquire();
		items.unshift(i);
		m.release();

		avail.release();
	}

	public function pop(block:Bool):Null<T> {
		final m = __mutex;
		final items = __items;
		final avail = __available;

		if (block) {
			avail.wait();
		} else {
			if (!avail.wait(0.0))
				return null;
		}

		m.acquire();
		final v = items.shift();
		m.release();
		return v;
	}
}
