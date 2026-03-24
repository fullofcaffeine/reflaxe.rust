# `async_retry_pipeline`

Rust-first async example using the currently supported entry boundary.

## What this example proves

- `-D rust_async` works on the supported `metal` contract.
- Async helpers can return `rust.async.Future<T>` and use `@:rustAwait`.
- The supported entry boundary is practical in real code:
  - `main()` stays synchronous
  - async work lives in helper functions
  - `rust.async.Async.blockOn(...)` bridges sync `main` to async work

## What this example does not prove

- async `main`
- portable-profile async
- `rust_no_hxrt` async
- broader scheduler/runtime claims beyond the documented Rust async subset

## Expected output

```text
result=payload-7-attempt-2
```

Use this when the question is: "What is the canonical supported async entry pattern on the Rust target?"
