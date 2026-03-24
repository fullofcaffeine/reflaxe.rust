# Concurrency Posture

This page is the canonical concurrency status record for `reflaxe.rust`.

Use it when the question is:

- what is already stable,
- what is still preview,
- what remains caveat-heavy,
- and what evidence currently backs each claim?

## Why this exists

Concurrency truth was previously scattered across:

- `docs/threading.md`
- `docs/async-await.md`
- `docs/v1.md`
- `docs/feature-support-matrix.md`

Those pages still matter, but they answer different questions. This page is the single place that
classifies the current async/threading posture.

## Stable today

These are the concurrency surfaces that are part of the current stable posture on validated lanes.

### `sys.thread` core primitives

Stable posture:

- `sys.thread.Thread`
- `sys.thread.Lock`
- `sys.thread.Mutex`
- `sys.thread.Condition`
- `sys.thread.Semaphore`
- `sys.thread.Tls`

What that means:

- real OS-thread execution exists,
- the runtime heap model is thread-safe by construction,
- message passing and synchronization primitives are implemented and used in CI-backed examples.

Primary evidence:

- `examples/sys_thread_smoke`
- `examples/thread_pool_smoke`
- Tier1/Tier2 stdlib sweep coverage
- full harness / Windows smoke coverage

### Direct `sys.thread.EventLoop` operations

Stable posture:

- direct Rust-target `sys.thread.EventLoop` operations are supported and have target-side proof

This specifically covers the direct EventLoop surface used by the Rust runtime-backed implementation,
not blanket `--interp`-style parity claims for every upstream scheduler path.

Primary evidence:

- `test/snapshot/sys_thread_event_loop`
- `test/snapshot/sys_thread_event_loop_repeat_cancel`
- `test/semantic_diff/sys_thread_event_loop`
- `examples/sys_thread_smoke`

What is now included in that stable Rust-target proof:

- direct loop progression and queued work,
- promised work scheduling,
- repeating callback registration,
- self-cancel-from-callback behavior for `repeat(...)/cancel(...)`.

### `sys.thread.Deque` and thread-pool helpers

Stable posture:

- `sys.thread.Deque`
- `sys.thread.FixedThreadPool`
- `sys.thread.ElasticThreadPool`

What that means:

- the Rust target has target-side proof for queue ordering/blocking behavior,
- fixed and elastic pool worker execution now compile and run correctly on the Rust target,
- this is still a Rust-target smoke/snapshot-backed stability claim, not a fairness/perf guarantee.

Primary evidence:

- `test/snapshot/sys_thread_deque_basic`
- `test/snapshot/sys_thread_elastic_thread_pool_smoke`
- `examples/thread_pool_smoke`
- Tier1/Tier2 stdlib sweep coverage

## Stable today

### `rust_async`

Current posture:

- `rust_async` is real, typed, and codegen-backed
- it is supported on an explicitly narrow Rust-first subset

Current constraints called out in repo docs:

- metal-only
- incompatible with `rust_no_hxrt`
- async support exists for static methods and generated-class instance methods
- sync `main` + `Async.blockOn(...)` is the supported entry boundary today
- canonical shape: sync `main()`, async helper returning `Future<T>`, `Async.blockOn(...)` in `main`
- explicit `Future<T>`/await model rather than a blanket async lowering story

Primary evidence:

- `test/snapshot/async_entry_boundary`
- `examples/async_retry_pipeline`
- `test/snapshot/async_retry`
- `test/snapshot/async_select`
- `test/snapshot/rust_async_tasks`
- `test/negative/async_main_boundary`
- `test/negative/async_constructor_preview`
- negative define guard: `test/negative/async_preview_removed`

Stable here should be read as:

- supported on its documented subset,
- not a blanket claim that every async entry/runtime/profile shape is supported.

Canonical contract source:

- `docs/async-contract.md`

## Caveat-heavy today

### `haxe.MainLoop` / `haxe.EntryPoint`

Current posture:

- narrower than direct `sys.thread.EventLoop` confidence
- not claimed as broad `--interp`-backed semantic parity

This is the main remaining public concurrency caveat.

What is true:

- the Rust target has real EventLoop machinery,
- there is target-side smoke evidence for direct EventLoop operations,
- there is now also target-side Rust evidence for the basic `haxe.MainLoop.add(...)` +
  `haxe.EntryPoint.run()` scheduling path,
- there is now target-side Rust evidence for the thread-bridge path using
  `haxe.MainLoop.addThread(...)` + `haxe.MainLoop.runInMainThread(...)` with
  `haxe.EntryPoint.run()` wakeup/exit behavior,
- the repo does not claim blanket parity for higher-level `haxe.MainLoop` / `haxe.EntryPoint`
  scheduler semantics.

Primary evidence and caveat references:

- `test/snapshot/haxe_mainloop_entrypoint_basic`
- `test/snapshot/haxe_mainloop_entrypoint_thread_bridge`
- `docs/threading.md`
- `docs/v1.md`
- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.md`

### Broader scheduler behavior beyond the proven paths

Current posture:

- supported enough to compile and exercise on the Rust target,
- but still best understood through target-side smoke and example evidence rather than a strong
  cross-target semantic oracle claim.

This caveat bucket is now mostly about the wider `haxe.MainLoop` / `haxe.EntryPoint` scheduler surface,
not about `Deque` or the thread-pool helpers themselves.

## How to read the current contract

Use these practical rules:

1. If you need ordinary threaded application behavior today, the stable `sys.thread` core is real.
2. If you need direct `sys.thread.EventLoop` or repeating callback cancellation, the Rust target has
   direct evidence for that surface.
3. If you need `Deque`, `FixedThreadPool`, or `ElasticThreadPool`, the Rust target now has direct
   smoke/snapshot proof for those helpers.
4. If your correctness argument depends on full `haxe.MainLoop` / `haxe.EntryPoint` parity, treat
   that as caveat-heavy and verify against the target-side evidence (`test/snapshot/haxe_mainloop_entrypoint_basic`,
   `test/snapshot/haxe_mainloop_entrypoint_thread_bridge`, `test/snapshot/sys_thread_event_loop`), not `--interp`.
5. If you need async/await, use `rust_async` as a supported Rust-first subset with explicit
   documented constraints from `docs/async-contract.md`.

## What this page does not claim

This page does **not** claim:

- blanket cross-target concurrency parity,
- blanket `--interp` equivalence for threaded scheduler semantics,
- or fully general stable async support outside the documented `rust_async` subset.

## Read next

- `docs/threading.md`
- `docs/async-await.md`
- `docs/async-contract.md`
- `docs/v1.md`
- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.md`
