# Async/Await (`-D rust_async`)

This page explains the current async/await support in plain language.

Canonical status note:

- for the current stable/preview/caveat classification, read [Concurrency Posture](concurrency-posture.md)
- for the exact supported/unsupported async contract, read [Async Contract](async-contract.md)

## Who this is for

Use this when:

- you are using a Rust-first profile (`-D reflaxe_rust_profile=metal`), and
- you want Haxe code that compiles into idiomatic Rust async (`async` / `.await`).

## Quick start

1. Enable a Rust-first profile + async support:

```bash
-D reflaxe_rust_profile=metal
-D rust_async
```

Removed define:
- `-D rust_async_preview` is no longer supported; use `-D rust_async`.

2. Use `rust.async.Future<T>` return types for async functions.
3. Mark async functions with `@:rustAsync` (or `@:async`).
4. Await values with `@:rustAwait expr` (or `@:await expr`), or call `Async.await(expr)`.

## Minimal example

```haxe
import rust.async.Async;
import rust.async.Future;

class Main {
  @:rustAsync
  static function plusOne(n:Int):Future<Int> {
    @:rustAwait Async.sleepMs(10);
    return n + 1;
  }

  static function main() {
    var result = Async.blockOn(plusOne(41));
    Sys.println(result); // 42
  }
}
```

This example is also the canonical entry-boundary shape:

- keep `main()` synchronous
- put async work in a helper returning `Future<T>`
- call `Async.blockOn(...)` from `main()`

## API surface

- `rust.async.Future<T>`
  - Opaque async value type.
  - Rust representation: `Pin<Box<dyn Future<Output = T> + Send + 'static>>`.
- `rust.async.Async.await(future)`
  - Lowered by the compiler to Rust `.await`.
- `rust.async.Async.blockOn(future)`
  - Explicit sync -> async boundary helper.
- `rust.async.Async.ready(value)`
  - Creates an already-resolved future.
- `rust.async.Async.sleepMs(ms)` / `rust.async.Async.sleep(duration)`
  - Awaitable delay helpers.
- `rust.async.Async.spawn(future)`
  - Spawn async work and await output as another `Future<T>`.
- `rust.async.Async.select(left, right)`
  - Race two `Future<T>` values and resolve with the first completed output.
- `rust.async.Async.timeoutMs(future, ms)` / `rust.async.Async.timeout(future, duration)`
  - Returns `Future<Option<T>>`; `Some(value)` on success, `None` on timeout.
- `rust.async.Tasks.spawn(...)` / `rust.async.Tasks.join(...)`
  - Task handle helper surface that bridges futures into `rust.concurrent` tasks.

## Important rules

- `@:rustAsync` / `@:async` is supported on static methods and generated-class instance methods.
- Constructors cannot be marked async.
- Async functions must return `rust.async.Future<T>`.
- `@:rustAwait` / `Async.await(...)` is only valid inside async functions.
- Keep `main` synchronous and use `Async.blockOn(...)` at the boundary.
- The supported entry shape is sync `main()` -> async helper -> `Async.blockOn(...)`.
- `Async.blockOn(...)` is forbidden inside async functions.

## Mental model

- Think of `Future<T>` as “a task that will eventually produce `T`”.
- `await` means “pause this async function until the task finishes”.
- `blockOn` means “run async work from a synchronous boundary” (for example sync `main`).

## Blocking vs non-blocking delays

- `Async.sleep(...)` and `Async.sleepMs(...)` are awaitable async delays.
- `DurationTools.sleep(...)` is a blocking sleep and should not be used as an async await substitute.

## Current status

This is a supported Rust-first async subset for metal-profile projects. It is fully typed and
codegen-backed, but still intentionally constrained so behavior remains predictable.

For the canonical current posture and evidence summary, see [Concurrency Posture](concurrency-posture.md).
For the exact current contract edges, see [Async Contract](async-contract.md).

## Optional tokio adapter

Default behavior uses lightweight runtime dependencies (`pollster` + `futures-timer`).

If you need tokio-backed behavior:

```haxe
import rust.async.TokioRuntime;

TokioRuntime.enable();
```

This keeps app code typed while letting Cargo/dependency planning include tokio through metadata and feature inference.

## Related docs

- [Metal profile](metal-profile.md)
- [Async contract](async-contract.md)
- [Profile migration guide](rusty-profile.md)
- [Defines reference](defines-reference.md)
- [Workflow](workflow.md)
- [Example: async_entry_boundary](../test/snapshot/async_entry_boundary)
- [Example: async_retry_pipeline](../examples/async_retry_pipeline)
