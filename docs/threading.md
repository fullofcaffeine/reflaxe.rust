# Threading In `reflaxe.rust` (sys.thread)

## Why This Needs A Dedicated Design

Haxe's `sys.thread.*` API implies **true parallel execution** of Haxe code. In most mature Haxe targets
(HL, C++, JVM, etc), Haxe values can be shared between threads (directly or indirectly), and the runtime
is responsible for making that safe.

`reflaxe.rust` now models Haxe object identity with a thread-safe heap:

- `HxRef<T>` is backed by `Arc<...>` + locking (`runtime/hxrt/src/cell.rs`).

This keeps Haxe class/reference semantics while allowing values to cross OS-thread boundaries safely.

This document defines the intended production direction for `sys.thread` in `reflaxe.rust`.

Canonical status note:

- for the current stable/preview/caveat classification, read [Concurrency Posture](concurrency-posture.md)

## What "Production-Ready Threads" Mean Here

For `sys.thread` to be considered correct and production-ready, the target should:

1. Support `sys.thread.Thread.create` executing Haxe code on an OS thread.
2. Support `Thread.sendMessage` / `Thread.readMessage` with Haxe values that are safe to transfer.
3. Provide the core synchronization primitives:
   - `sys.thread.Lock`
   - `sys.thread.Mutex` (re-entrant per Haxe docs)
   - `sys.thread.Condition`
   - `sys.thread.Semaphore`
   - `sys.thread.Tls<T>`
4. Keep existing codegen stable: do not introduce deadlocks, UB, or data races.
5. Keep CI deterministic: add a stable example that spawns threads and synchronizes with `Lock`/`Mutex`.

## Rust-First Concurrency Layer

`sys.thread.*` remains the portable API. For Rust-first code (`reflaxe_rust_profile=metal`),
`std/rust/concurrent/*` adds typed wrappers over Rust-native primitives:

- `rust.concurrent.Channel<T>` + `rust.concurrent.Channels`: typed `create/send/recv/tryRecv`.
- `rust.concurrent.Task<T>` + `rust.concurrent.Tasks`: typed `spawn/join`.
- `rust.concurrent.Mutex<T>` + `rust.concurrent.Mutexes`: `create/get/set/replace/update`.
- `rust.concurrent.RwLock<T>` + `rust.concurrent.RwLocks`: `create/read/write/replace/update`.

These APIs route through `hxrt::concurrent` so application/example code stays injection-free and typed.

### Send/Sync boundary diagnostics

The compiler now scans spawn closures at typed AST time and warns when a job captures borrow-only or
runtime-dynamic values that cannot be proven `Send + Sync` safely at thread boundaries:

- `rust.Ref<T>`, `rust.MutRef<T>`
- `rust.Slice<T>`, `rust.MutSlice<T>`
- `Dynamic`

Use `-D rust_send_sync_strict` to turn those diagnostics into hard compile errors in CI or release gates.

## Current Status

As of 2026-02-09, `reflaxe.rust` has a minimal-but-correct threaded runtime model:

- The heap model is thread-safe by construction (`HxRef<T>` is backed by `Arc<...>` + locking).
- `sys.thread.Thread.create` spawns real OS threads.
- `Thread.sendMessage` / `Thread.readMessage` are implemented via per-thread message queues in `hxrt`.
- The core synchronization primitives exist (`Lock`, `Mutex` (re-entrant), `Condition`, `Semaphore`, `Tls`).
- `sys.thread.EventLoop` exists and is backed by `hxrt::thread` per-thread event state.
- CI includes a deterministic smoke example: `examples/sys_thread_smoke`.

Known gaps (not yet parity with upstream targets):

1. `haxe.MainLoop` / `haxe.EntryPoint` integration is still narrower than full parity. Direct
   `sys.thread.EventLoop` operations (`run` / `promise` / `runPromised` / `progress` / `loop`) now have
   target-side smoke coverage (`test/snapshot/sys_thread_event_loop`), direct repeating-callback
   `repeat(...)/cancel(...)` behavior is now locked by
   `test/snapshot/sys_thread_event_loop_repeat_cancel`, and higher-level scheduler proof now covers both:
   - the basic `haxe.MainLoop.add(...)` + `haxe.EntryPoint.run()` path
     (`test/snapshot/haxe_mainloop_entrypoint_basic`, expected output `second,first`)
   - the thread-bridge path using `haxe.MainLoop.addThread(...)` +
     `haxe.MainLoop.runInMainThread(...)` with `haxe.EntryPoint.run()` wakeup/exit behavior
     (`test/snapshot/haxe_mainloop_entrypoint_thread_bridge`)
   This is still narrower than broad `--interp` scheduler parity, so wider MainLoop semantics remain
   caveat-heavy until a stronger oracle exists.

Tracking summary:

- Thread-safe heap baseline is complete and validated in CI.
- Core threading primitives are implemented.
- Direct `sys.thread.EventLoop` plus `repeat(...)/cancel(...)` now have target-side proof.
- `sys.thread.Deque`, `FixedThreadPool`, and `ElasticThreadPool` now have Rust-target smoke proof.
- Broader `haxe.MainLoop` / `haxe.EntryPoint` scheduler semantics remain the main caveat-heavy follow-up.
