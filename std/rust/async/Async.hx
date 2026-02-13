package rust.async;

import rust.Duration;

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
}
