# Async Contract (`rust_async`)

This page is the canonical contract record for Rust-first async support in `reflaxe.rust`.

Use it when the question is:

- what `-D rust_async` actually supports today,
- what is intentionally unsupported,
- what boundary is currently stable,
- and where the supported boundary deliberately stops today?

## Why this exists

Async support is real in this repo, but it only stays honest if the supported subset is stated as
a concrete contract edge.

Without one canonical contract page, async status drifts into two bad forms:

- tutorial-style docs that make the feature look broader than it is, or
- vague preview language that does not say what is actually missing.

This page keeps the async story concrete enough to guide both users and compiler work.

## Stable today

These parts of the Rust-first async surface are already real and intentionally supported.

### Profile/runtime boundary

- `-D rust_async` requires `-D reflaxe_rust_profile=metal`
- `-D rust_async` is incompatible with `-D rust_no_hxrt`
- the runtime boundary is explicit: async lowering currently depends on `hxrt::async_`

### Function shape

- `@:async` / `@:rustAsync` static methods are supported
- `@:async` / `@:rustAsync` instance methods on generated classes are supported
- supported async functions must return `rust.async.Future<T>`
- `@:await` / `@:rustAwait` and `Async.await(...)` are supported inside async functions only

### Sync-to-async entry boundary

- the supported entry boundary is: synchronous caller -> `rust.async.Async.blockOn(...)`
- the canonical program-entry shape is:
  - sync `main()`
  - async helper returning `rust.async.Future<T>`
  - `Async.blockOn(...)` inside `main`
- this is the supported way to run async work from `main` today

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

These constraints are enforced by compiler diagnostics today and should be read as contract edges,
not incidental implementation quirks.

## What this support status means

`rust_async` is supported today as a Rust-first async subset, not as a blanket async contract for
every target/profile/runtime shape.

Concretely, that means:

- real, typed, and codegen-backed,
- stable on the documented `metal` + `hxrt` subset,
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
4. Treat any broader receiver/entrypoint expectation as outside the current supported subset until
   explicit compiler/runtime evidence says otherwise.

## Read next

- `docs/async-await.md`
- `docs/concurrency-posture.md`
- `docs/profiles.md`
- `docs/defines-reference.md`
