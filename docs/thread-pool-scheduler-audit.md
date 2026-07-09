# Thread-Pool And Scheduler Audit

This document records the Milestone 39 audit for the remaining caveat-heavy concurrency surface in
`reflaxe.rust`.

Post-implementation status: the implementation slice selected by this audit has since landed. The
canonical current status is in `docs/concurrency-posture.md`; this page preserves the audit trail and
now points at the fixtures that closed the original bugs.

## Why this exists

The repo already has stable proof for:

- direct `sys.thread.EventLoop` operations,
- the basic `haxe.MainLoop.add(...)` + `haxe.EntryPoint.run()` path,
- and the `addThread(...)` / `runInMainThread(...)` bridge path.

What remained under-proven was the higher-level helper layer around that runtime:

- `sys.thread.FixedThreadPool`
- `sys.thread.ElasticThreadPool`
- `sys.thread.Deque`
- deeper scheduler behavior around repeating/cancelled events

This audit answered a narrower question than the public support matrix:

- which parts are already stable enough,
- which parts are still only caveat-heavy but acceptable,
- and which parts were actual correctness bugs that deserved the next implementation slice.

## What was audited

Committed evidence already in the repo:

- `examples/thread_pool_smoke`
- `test/snapshot/sys_thread_event_loop`
- `test/snapshot/sys_thread_event_loop_repeat_cancel`
- `test/snapshot/sys_thread_deque_basic`
- `test/snapshot/sys_thread_elastic_thread_pool_smoke`
- `test/snapshot/haxe_mainloop_entrypoint_basic`
- `test/snapshot/haxe_mainloop_entrypoint_thread_bridge`
- Tier1/Tier2 compile coverage for `sys.thread.*`

Target-side scratch probes run during the audit:

- `Deque.add/push/pop(false)/pop(true)` ordering and blocking behavior
- `ElasticThreadPool` submission/execution on a real Rust-target compile
- `EventLoop.repeat(...)/cancel(...)` behavior on the Rust target

## Classification

| Surface | Classification | Evidence | Notes |
| --- | --- | --- | --- |
| `sys.thread.Deque` | stable now | `test/snapshot/sys_thread_deque_basic`, Tier1/Tier2 sweep coverage | Queue ordering, non-blocking empty-pop behavior, and blocking wakeup behavior now have committed target-side proof. |
| `sys.thread.FixedThreadPool` | stable now | `examples/thread_pool_smoke`, Tier1/Tier2 sweep coverage | Current proof is still smoke-oriented, but the audited behavior matched the intended contract: multiple jobs run, completion can be coordinated, and shutdown drains the queue. |
| `sys.thread.ElasticThreadPool` | fixed and smoke-proven | `test/snapshot/sys_thread_elastic_thread_pool_smoke` | The audit found a real compile/codegen bug. The post-audit fixture now proves elastic worker submission/execution on the Rust target. |
| Deeper `EventLoop` helper behavior (`repeat` / `cancel`) | fixed and smoke-proven | `test/snapshot/sys_thread_event_loop_repeat_cancel` | The audit found a real self-cancel behavior bug. The post-audit fixture now proves repeating callback cancellation on the Rust target. |
| Broader `haxe.MainLoop` / `haxe.EntryPoint` scheduler semantics beyond the already-proven basic and thread-bridge paths | caveat-heavy but acceptable | existing snapshots + docs | The audit did not uncover a new bug here. The repo should keep treating this as narrower target-side evidence rather than broad `--interp` semantic parity. |

## Historical Root Findings

### 1. `ElasticThreadPool` was not just under-proven; it was broken on a real target-side use

The audit compile exposed two distinct failures.

Compiler-side failure:

- repeated per-iteration aliases such as `done1_2` / `mutex1_2` were emitted,
- but nested closures still referenced the original names (`done1` / `mutex1`),
- producing invalid Rust name resolution.

Std/codegen-side failure:

- `ElasticThreadPool.Worker.loop` stores tasks as `HxDynRef<dyn Fn() + Send + Sync>`,
- the generated Rust then tried to build `HxRc<dyn Fn()>` from that already-erased callable handle,
- which Rust rejects because `HxDynRef<dyn Fn()>` is not itself a closure implementing `Fn()`.

This meant `ElasticThreadPool` belonged in the implementation slice, not the "docs only" bucket.

### 2. `EventLoop.repeat(...)/cancel(...)` has a real runtime bug

The audit used a repeating callback that cancels itself after the second tick.

Observed result on the Rust target:

- one `progress()` cycle still produced multiple extra ticks after cancellation,
- then the loop settled to `Never`.

That was stronger than "proof depth is thin". The runtime behavior was wrong for the audited
cancel-from-callback path.

### 3. Nullable local capture around event handlers also exposed a compiler bug

The first direct `repeat/cancel` probe used a captured `Null<EventHandler>` local.

Generated Rust treated the captured value inconsistently and produced invalid borrow-based code for
an `Option<i32>` local. That is not the primary scheduler bug, but it is directly relevant because
it blocked a realistic event-handler cancellation pattern.

## Resolved Implementation Slice

The implementation slice stayed narrow and covered what the audit actually proved:

1. fix compiler closure-capture lowering for repeated loop-submitted closures where per-iteration
   alias rebinding is required;
2. fix `ElasticThreadPool.Worker.loop` so stored callable handles are invoked/reused correctly in
   generated Rust;
3. fix runtime `EventLoop.repeat(...)/cancel(...)` behavior for self-cancelling repeating callbacks;
4. add target-side proof fixtures for:
   - `ElasticThreadPool`,
   - `Deque` ordering/blocking behavior,
   - `EventLoop.repeat/cancel`.

Current committed evidence:

- `test/snapshot/sys_thread_elastic_thread_pool_smoke`
- `test/snapshot/sys_thread_deque_basic`
- `test/snapshot/sys_thread_event_loop_repeat_cancel`

What this audit explicitly does **not** justify:

- a broad concurrency rewrite,
- a new async milestone,
- or a blanket claim that `haxe.MainLoop` / `haxe.EntryPoint` now have full `--interp` parity.
