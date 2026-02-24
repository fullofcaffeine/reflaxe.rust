package rust.async;

import rust.Duration;
import rust.Option;

/**
 * rust.async.Async
 *
 * Why:
 * - Async code needs explicit boundary operations:
 *   - await a future inside async code
 *   - bridge async back to sync at process/application edges
 *
 * What:
 * - `await(...)`: compiler-lowered await marker.
 * - `blockOn(...)`: explicit sync -> async boundary.
 * - `ready(...)`: create an already-resolved `Future<T>`.
 * - `sleepMs(...)` / `sleep(...)`: awaitable delays.
 * - `spawn(...)`: run a future on separate execution and await its output.
 * - `timeoutMs(...)` / `timeout(...)`: race a future against a timeout and receive `Option<T>`.
 *
 * How:
 * - Most methods bind directly to `hxrt::async_::*`.
 * - `await(...)` is treated as a compiler intrinsic and lowered to Rust `.await`.
 */
@:native("hxrt::async_")
extern class Async {
	/**
	 * Await a future and produce its value.
	 *
	 * Compiler note:
	 * - This method is intrinsic in `reflaxe.rust` and lowered to Rust `.await`.
	 */
	@:native("await_haxe")
	public static function await<T>(future:Future<T>):T;

	/**
	 * Run a future to completion from synchronous code.
	 *
	 * Intended for boundary points like sync `main()` wrappers.
	 */
	@:native("block_on")
	public static function blockOn<T>(future:Future<T>):T;

	/**
	 * Build an already-resolved future value.
	 */
	public static function ready<T>(value:T):Future<T>;

	/**
	 * Awaitable delay using milliseconds.
	 */
	@:native("sleep_ms")
	public static function sleepMs(ms:Int):Future<Void>;

	/**
	 * Awaitable delay using `rust.Duration`.
	 */
	public static function sleep(duration:Duration):Future<Void>;

	/**
	 * Spawn a future and return a future for its eventual output.
	 *
	 * Why:
	 * - Rust-first async code often needs task-style concurrency without dropping to
	 *   low-level runtime APIs.
	 *
	 * How:
	 * - Binds to `hxrt::async_::spawn`.
	 * - Runtime behavior depends on adapter configuration:
	 *   - default: lightweight thread-backed bridge
	 *   - tokio adapter enabled: tokio-backed execution path
	 */
	public static function spawn<T>(future:Future<T>):Future<T>;

	/**
	 * Race two futures of the same output type and return the first value that resolves.
	 *
	 * Why:
	 * - Rust-first async code often needs "first responder wins" control-flow without dropping to
	 *   raw runtime calls.
	 * - Keeping this typed at the Haxe layer avoids ad-hoc injection and keeps adapter switching
	 *   (`pollster`/`futures` vs tokio) behind one stable API boundary.
	 *
	 * How:
	 * - Binds to `hxrt::async_::select_first`.
	 * - In tokio-adapter mode this lowers to `tokio::select!`.
	 * - In default mode this lowers to `futures::future::select`.
	 */
	@:native("select_first")
	public static function select<T>(left:Future<T>, right:Future<T>):Future<T>;

	/**
	 * Timeout helper using milliseconds.
	 *
	 * Returns:
	 * - `Some(value)` if `future` resolves before timeout.
	 * - `None` if timeout elapses first.
	 */
	@:native("timeout_ms")
	public static function timeoutMs<T>(future:Future<T>, ms:Int):Future<Option<T>>;

	/**
	 * Timeout helper using `rust.Duration`.
	 *
	 * Returns:
	 * - `Some(value)` if `future` resolves before timeout.
	 * - `None` if timeout elapses first.
	 */
	public static function timeout<T>(future:Future<T>, duration:Duration):Future<Option<T>>;
}
