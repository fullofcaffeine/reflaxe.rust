# Async Contract (`rust_async`)

This page is the canonical contract record for the Rust-first async preview in `reflaxe.rust`.

Use it when the question is:

- what `-D rust_async` actually supports today,
- what is intentionally unsupported,
- why the implemented surface is still excluded from the stable-major contract,
- and where the preview boundary deliberately stops today?

## Why this exists

Async support is real in this repo, but it only stays honest if the supported subset is stated as
a concrete contract edge.

Without one canonical contract page, async status drifts into two bad forms:

- tutorial-style docs that make the feature look broader than it is, or
- vague preview language that does not say what is actually missing.

This page keeps the async story concrete enough to guide both users and compiler work.

## Experimental preview today

The following surface is real, typed, codegen-backed, and useful in pinned `0.x` applications. It
is still experimental: snapshot and example coverage proves that these shapes work, but it does not
yet establish an owned task lifecycle suitable for a `1.x` compatibility promise.

### Profile/runtime boundary

- `-D rust_async` requires `-D reflaxe_rust_profile=metal`
- `-D rust_async` is incompatible with `-D rust_no_hxrt`
- the runtime boundary is explicit: async lowering currently depends on `hxrt::async_`

### Working function shape

- `@:async` / `@:rustAsync` static methods are implemented
- `@:async` / `@:rustAsync` instance methods on generated classes are implemented
- async functions in this preview must return `rust.async.Future<T>`
- `@:await` / `@:rustAwait` and `Async.await(...)` are implemented inside async functions only

### Working sync-to-async entry boundary

- the implemented entry boundary is: synchronous caller -> `rust.async.Async.blockOn(...)`
- the canonical program-entry shape is:
  - sync `main()`
  - async helper returning `rust.async.Future<T>`
  - `Async.blockOn(...)` inside `main`
- this is the preview's working way to run async work from `main` today

### Evidence

- `test/snapshot/async_entry_boundary`
- `test/snapshot/async_retry`
- `test/snapshot/async_select`
- `test/snapshot/rust_async_tasks`
- `examples/async_retry_pipeline`

## Unsupported today

These are not "maybe supported". They are intentionally outside the current contract.

- async constructors
- async `main`
- portable-profile async support
- `rust_no_hxrt` async support
- stable task-panic and Haxe-throw propagation
- cancellation, join/drop, shutdown, and resource-release guarantees
- a bounded worker/thread ownership model
- specified nested-runtime behavior
- runtime-adapter isolation; adapter selection is currently process-global
- general async networking

The profile and function-shape constraints are enforced by compiler diagnostics. The lifecycle
items are explicit non-promises: the compiler cannot prove them today, so applications must not
infer them from successful compilation or the happy-path fixtures.

## What this support status means

`rust_async` is an implemented Rust-first async preview, not an admitted stable subset and not a
blanket async contract for every target/profile/runtime shape.

Concretely, that means:

- real, typed, and codegen-backed,
- usable in pinned `0.x` applications that test their own task lifecycle and shutdown behavior,
- allowed to change in a minor `0.x` release with release notes and practical migration guidance,
- excluded from the proposed `1.x` compatibility promise until the lifecycle gaps above are owned,
- still intentionally narrow outside that subset.

This is an explicit contract boundary, not a soft promise that more async shapes might work by
accident.

## How to use the current contract

Use these practical rules:

1. If you want Rust-first async today, use `metal` plus `-D rust_async`.
2. Keep async functions within the currently supported shapes: static methods or generated-class
   instance methods returning `rust.async.Future<T>`.
3. Keep `main` synchronous and cross the boundary with `Async.blockOn(...)`.
   Canonical shape: sync `main()`, async helper, `Async.blockOn(helper(...))`.
4. Treat any broader receiver/entrypoint expectation as outside the current preview boundary until
   explicit compiler/runtime evidence says otherwise.
5. Do not assume that timing out or dropping spawned work cancels or joins its backing execution.
   Add application-specific tests for panic/throw propagation, cancellation, resource release,
   shutdown, and adapter selection anywhere those properties matter.

## Read next

- `docs/async-await.md`
- `docs/concurrency-posture.md`
- `docs/profiles.md`
- `docs/defines-reference.md`
