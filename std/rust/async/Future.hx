package rust.async;

/**
 * rust.async.Future<T>
 *
 * Why:
 * - Rust `async` functions return futures, not immediate values.
 * - We need a concrete, user-visible Haxe type so async APIs can be typed clearly.
 *
 * What:
 * - `Future<T>` is the Rusty-profile async value type.
 * - It is intentionally opaque at the Haxe level: you typically `await` it or pass it to `blockOn`.
 *
 * How:
 * - This extern maps to `hxrt::async_::HxFuture<T>` in runtime Rust code.
 * - The runtime representation is boxed/pinned so all `Future<T>` values share one concrete Rust type.
 *
 * Usage:
 * - Return `Future<T>` from `@:rustAsync` / `@:async` functions.
 * - Consume with `@:rustAwait` / `@:await` or `Async.await(...)`.
 */
@:native("hxrt::async_::HxFuture")
extern class Future<T> {}
