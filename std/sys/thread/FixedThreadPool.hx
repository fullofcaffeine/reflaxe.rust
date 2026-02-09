package sys.thread;

import haxe.Exception;

/**
	Thread pool with a constant amount of threads.

	Why
	- A fixed-size pool is a common building block for deterministic background work: the maximum
	  concurrency is known, and threads stay alive until shutdown.

	What
	- `new(threadsCount)` creates a pool with `threadsCount` OS threads.
	- `run(task)` enqueues `task` to be executed by an available worker.
	- `shutdown()` prevents new tasks and causes workers to terminate after draining the queue.

	How
	- Uses a shared `Deque<()->Void>` to distribute tasks.
	- Each worker thread blocks on `queue.pop(true)` to avoid busy loops.
	- Shutdown is implemented by enqueueing a special task that throws a private exception caught by
	  the worker loop.
**/
@:coreApi
class FixedThreadPool implements IThreadPool {
	/** Amount of threads in this pool. */
	public var threadsCount(get, null): Int;
	function get_threadsCount(): Int return threadsCount;

	/** Indicates if `shutdown` method of this pool has been called. */
	public var isShutdown(get, never): Bool;
	var _isShutdown = false;
	function get_isShutdown(): Bool return _isShutdown;

	final pool: Array<Worker>;
	final queue = new Deque<() -> Void>();

	/**
		Create a new thread pool with `threadsCount` threads.
	**/
	public function new(threadsCount: Int): Void {
		if (threadsCount < 1) throw new ThreadPoolException("FixedThreadPool needs threadsCount to be at least 1.");
		this.threadsCount = threadsCount;
		final p = new Array<Worker>();
		for (_i in 0...threadsCount) {
			p.push(new Worker(queue));
		}
		pool = p;
	}

	/**
		Submit a task to run in a thread.

		Throws an exception if the pool is shut down.
	**/
	public function run(task: () -> Void): Void {
		if (_isShutdown) throw new ThreadPoolException("Task is rejected. Thread pool is shut down.");
		queue.add(task);
	}

	/**
		Initiates a shutdown.
		All previously submitted tasks will be executed, but no new tasks will be accepted.

		Multiple calls to this method have no effect.
	**/
	public function shutdown(): Void {
		if (_isShutdown) return;
		_isShutdown = true;
		for (_ in pool) {
			queue.add(() -> shutdownTask());
		}
	}

	static function shutdownTask(): Void {
		throw new ShutdownException("");
	}
}

private class ShutdownException extends Exception {}

private class Worker {
	final queue: Deque<() -> Void>;

	public function new(queue: Deque<() -> Void>) {
		this.queue = queue;
		Thread.create(() -> Worker.loop(queue));
	}

	static function loop(queue: Deque<() -> Void>) {
		try {
			while (true) {
				var task = queue.pop(true);
				if (task != null) task();
			}
		} catch (_: ShutdownException) {
		}
	}
}
