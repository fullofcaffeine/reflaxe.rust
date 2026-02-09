# Threading In `reflaxe.rust` (sys.thread)

## Why This Needs A Dedicated Design

Haxe's `sys.thread.*` API implies **true parallel execution** of Haxe code. In most mature Haxe targets
(HL, C++, JVM, etc), Haxe values can be shared between threads (directly or indirectly), and the runtime
is responsible for making that safe.

`reflaxe.rust` currently models Haxe object identity as:

- `type HxRef<T> = Rc<RefCell<T>>`

This is a good, lightweight model for a single-threaded runtime, but it comes with two hard constraints:

1. `Rc<...>` and `RefCell<...>` are **not `Send`/`Sync`**. Rust will not allow them to cross OS-thread
   boundaries safely.
2. Haxe function values (closures) are compiled into heap values that usually capture `HxRef` data.
   Rust requires the closure passed to `std::thread::spawn` to be `Send + 'static`, so any captured
   non-`Send` data makes spawning impossible.

Because of (1) and (2), **we cannot implement `sys.thread.Thread.create` correctly** without changing
either the runtime representation of Haxe values or the semantics of cross-thread interaction.

This document defines the intended production direction for `sys.thread` in `reflaxe.rust`.

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

## How We Plan To Get There (Recommended Direction)

### Strategy A (Recommended): Thread-Safe Heap (`Arc<...>`)

Make Haxe object identity and dynamic values thread-safe by construction, then implement `sys.thread`
directly on top of Rust OS threads.

High-level changes:

1. Replace `HxRef<T> = Rc<RefCell<T>>` with a thread-safe representation.
   - Candidate: `Arc<parking_lot::Mutex<T>>` for good performance and ergonomics.
   - Alternative: `Arc<std::sync::Mutex<T>>` (no extra deps, but heavier).
2. Update generated code to use short-lived locks rather than `RefCell` borrows:
   - `.borrow()` and `.borrow_mut()` patterns become `.lock()` patterns.
   - Maintain existing "evaluate RHS before taking a mutable guard" rule to avoid self-deadlocks.
3. Ensure dynamic dispatch / trait objects are also thread-safe:
   - Use `Arc<dyn Trait + Send + Sync>` for polymorphic references (or another safe scheme).
   - Emit trait bounds (`trait Trait: Send + Sync`) where needed.
4. Implement `sys.thread.Thread` message queues with `std::sync::mpsc` (or `crossbeam-channel` if we need
   select/timeouts).
5. Keep the API surface the same in Haxe; this is a backend/runtime concern.

Pros:

- Closest to "real" parity with existing sys targets.
- Rust type system enforces safety once the representation is correct.
- Makes future Rust-native frameworks more realistic (TUI/IO + threads).

Cons:

- Large refactor: touches most emitted code patterns and the runtime.
- Locking has runtime cost; needs careful lock scoping to avoid deadlocks.

### Strategy B: Isolates (No Shared Heap Across Threads)

Keep the current single-threaded heap model per-thread and enforce message passing via deep-copy /
serialization.

Pros:

- Avoids making all Haxe values thread-safe.
- Can be faster for some cases (no locks).

Cons:

- Requires a robust deep-clone / serialization mechanism for `Dynamic` and user objects.
- Harder to make fully compatible with Haxe semantics.
- Likely becomes a custom "Rust-only" threading model rather than sys parity.

## Current Status

As of the current POC/runtime architecture:

- `sys.net` exists and is implemented via `hxrt::net`.
- `sys.thread` is **not** implemented because correct threading requires a deliberate runtime choice.

The tracking issue for this work is `haxe.rust-zhs`.

