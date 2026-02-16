package sys.thread;

/**
	A thread pool interface.

	Why
	- Haxe exposes a small shared abstraction for "submit work to be done on background threads".
	- Implementations (`FixedThreadPool`, `ElasticThreadPool`) are used by libraries and user code.

	What
	- `run(task)` submits a task for execution.
	- `shutdown()` initiates a graceful shutdown.
	- `threadsCount` exposes the number of alive threads.

	How
	- Implementations are written in pure Haxe and rely on `sys.thread.Thread` + `sys.thread.Deque`.
**/
interface IThreadPool {
	/** Amount of alive threads in this pool. */
	var threadsCount(get, never):Int;

	/** Indicates if `shutdown` method of this pool has been called. */
	var isShutdown(get, never):Bool;

	/**
		Submit a task to run in a thread.

		Throws an exception if the pool is shut down.
	**/
	function run(task:() -> Void):Void;

	/**
		Initiates a shutdown.
		All previously submitted tasks will be executed, but no new tasks will be accepted.

		Multiple calls to this method have no effect.
	**/
	function shutdown():Void;
}
