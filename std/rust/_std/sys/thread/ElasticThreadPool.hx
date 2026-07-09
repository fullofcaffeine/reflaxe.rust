package sys.thread;

import haxe.Exception;

/**
	Thread pool with a varying amount of threads.

	Why
	- Some workloads are bursty: a fixed pool either wastes idle threads or becomes a bottleneck.
	- An elastic pool grows when all workers are busy and shrinks when workers are idle for long enough.

	What
	- `new(maxThreadsCount, threadTimeout)` configures the pool's maximum size and idle timeout.
	- `run(task)` executes `task` on an idle worker, starts a new worker if allowed, or queues work.
	- `shutdown()` stops workers after current work is completed.

	How
	- Workers wait on a `Lock` with a timeout; if they time out and have no pending work, they mark
	  themselves dead.
	- A shared `Deque<()->Void>` holds overflow work when all workers are busy.
**/
@:coreApi
class ElasticThreadPool implements IThreadPool {
	/** Amount of alive threads in this pool. */
	public var threadsCount(get, null):Int;

	/** Maximum amount of threads in this pool. */
	public var maxThreadsCount:Int;

	/** Indicates if `shutdown` method of this pool has been called. */
	public var isShutdown(get, never):Bool;

	var _isShutdown = false;

	function get_isShutdown():Bool
		return _isShutdown;

	final pool:Array<Worker> = [];
	final queue = new Deque<() -> Void>();
	final mutex = new Mutex();
	final threadTimeout:Float;

	/**
		Create a new thread pool with `maxThreadsCount` threads.

		If a worker thread does not receive a task for `threadTimeout` seconds it is terminated.
	**/
	public function new(maxThreadsCount:Int, threadTimeout:Float = 60):Void {
		if (maxThreadsCount < 1)
			throw new ThreadPoolException("ElasticThreadPool needs maxThreadsCount to be at least 1.");
		this.maxThreadsCount = maxThreadsCount;
		this.threadTimeout = threadTimeout;
	}

	/**
		Submit a task to run in a thread.

		Throws an exception if the pool is shut down.
	**/
	public function run(task:() -> Void):Void {
		if (_isShutdown)
			throw new ThreadPoolException("Task is rejected. Thread pool is shut down.");

		mutex.acquire();
		var submitted = false;
		var deadWorker = null;
		for (worker in pool) {
			if (deadWorker == null && worker.dead)
				deadWorker = worker;
			if (worker.task == null) {
				submitted = true;
				Worker.wakeup(worker, task);
				break;
			}
		}
		if (!submitted) {
			if (deadWorker != null) {
				Worker.wakeup(deadWorker, task);
			} else if (pool.length < maxThreadsCount) {
				var worker = new Worker(queue, threadTimeout);
				pool.push(worker);
				Worker.wakeup(worker, task);
			} else {
				queue.add(task);
			}
		}
		mutex.release();
	}

	/**
		Initiates a shutdown.
		All previously submitted tasks will be executed, but no new tasks will be accepted.

		Multiple calls to this method have no effect.
	**/
	public function shutdown():Void {
		if (_isShutdown)
			return;
		mutex.acquire();
		_isShutdown = true;
		for (worker in pool) {
			Worker.shutdown(worker);
		}
		mutex.release();
	}

	function get_threadsCount():Int {
		var result = 0;
		for (worker in pool)
			if (!worker.dead)
				++result;
		return result;
	}
}

private class Worker {
	public var task(default, null):Null<() -> Void>;
	public var dead(default, null) = false;

	final deathMutex = new Mutex();
	final waiter = new Lock();
	final queue:Deque<() -> Void>;
	final timeout:Float;
	var isShutdown = false;

	public function new(queue:Deque<() -> Void>, timeout:Float) {
		this.queue = queue;
		this.timeout = timeout;
		Worker.start(this);
	}

	public static function wakeup(worker:Worker, task:() -> Void) {
		worker.deathMutex.acquire();
		if (worker.dead)
			Worker.start(worker);
		worker.task = task;
		worker.waiter.release();
		worker.deathMutex.release();
	}

	public static function shutdown(worker:Worker) {
		worker.isShutdown = true;
		worker.waiter.release();
	}

	static function start(worker:Worker) {
		worker.dead = false;
		Thread.create(() -> Worker.loop(worker));
	}

	static function loop(worker:Worker) {
		try {
			while (worker.waiter.wait(worker.timeout)) {
				switch worker.task {
					case null:
						if (worker.isShutdown)
							break;
					case fn:
						fn();
						// If more tasks were added while all threads were busy
						while (true) {
							switch worker.queue.pop(false) {
								case null: break;
								case fn: fn();
							}
						}
						worker.task = null;
				}
			}
			worker.deathMutex.acquire();
			// In case a task was submitted right after the lock timed out
			if (worker.task != null)
				Worker.start(worker)
			else
				worker.dead = true;
			worker.deathMutex.release();
		} catch (e) {
			worker.task = null;
			Worker.start(worker);
			throw e;
		}
	}
}
