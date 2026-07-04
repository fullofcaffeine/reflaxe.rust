# Array Semantics (Haxe `Array<T>` → Rust)

This document records how `reflaxe.rust` represents **Haxe `Array<T>`** in Rust output, why that
representation exists, and which tests currently guard the contract.

## Why this matters

In Haxe, `Array<T>` is a **mutable reference type**:

- assignment aliases (`var b = a; b.push(x)` mutates `a` too)
- passing to functions aliases (mutations in callee are visible to caller)
- values are reusable after calls (no “moved value” concept)

In Rust, `Vec<T>` is an **owned value** that moves by default. If we map `Array<T>` directly to `Vec<T>`,
we immediately hit:

- move/borrow friction (lots of `.clone()` to preserve reuse)
- semantic mismatches (aliasing is not automatic)

## Current state (today)

`Array<T>` now maps to `hxrt::array::Array<T>` (a small runtime wrapper around `HxRef<Vec<T>>`).
In the default runtime, `HxRef<T>` is implemented as `Arc<HxCell<T>>`, and `HxCell<T>` uses
lock-backed interior mutability so arrays and other Haxe reference values can cross `sys.thread`
boundaries safely.

In generated Rust:

- array literals (`[...]`) are emitted as `hxrt::array::Array::from_vec(vec![...])`
- index reads use `get_unchecked(...)` (or `get(...)` when typed as `Null<T>`)
- index writes use `set(...)`
- `arr.length` lowers to `arr.len() as i32`
- common methods are implemented on the runtime type and called directly:
  - mutation: `push`, `pop`, `shift`, `unshift`, `insert`, `splice`, `reverse`
  - copies: `copy`, `slice`, `concat`
  - search:
    - value semantics (requires `T: PartialEq`): `contains`, `remove`, `indexOf`, `lastIndexOf`
    - object semantics (identity; no `PartialEq` required): `containsRef`, `removeRef`, `indexOfRef`, `lastIndexOfRef`
  - helpers: `sort`, `join`
- `shift()`/`pop()` return nullable Haxe values. For value-like element types this stays as
  `Option<T>` in Rust; for reference-like element types such as classes, empty arrays map back to the
  type's explicit null handle at typed callsites.

Some methods impose Rust trait bounds on `T`:

- methods returning a new `Array<T>` generally require `T: Clone`
- search methods:
  - `contains/remove/indexOf/lastIndexOf` require `T: PartialEq`
  - for object arrays (`Array<Foo>`, interfaces, polymorphic base classes), the compiler routes
    calls to the `*Ref` variants which use runtime-handle identity instead
- `resize` requires `T: Default` (for `Array<Null<T>>` this maps nicely to `None`)
- `join` requires `T: ToString`

## Borrowing as slices (metal profile)

For Rust-first integrations, the metal profile provides slice-borrow helpers that work on
`Array<T>` without cloning:

- `rust.SliceTools.with(array, s -> ...)` borrows as `&[T]`
- `rust.MutSliceTools.with(array, s -> ...)` borrows as `&mut [T]`

These are implemented via runtime helpers (`hxrt::array::with_slice` / `with_mut_slice`) that keep the
runtime borrow/lock guard scoped to the callback.
The metal policy guard compiles `test/snapshot/rust_array_slice_views` and checks that generated Rust
routes through `ArrayBorrow::with_slice` / `with_mut_slice`, that HXRT uses `borrow().as_slice()` /
`borrow_mut().as_mut_slice()`, and that those helper bodies do not call `clone()` or `to_vec()`.

Important rules:

- Do not store or return `Slice`/`MutSlice` outside the callback.
- Avoid nested conflicting borrows of the same array; the runtime lock can block or reject invalid
  access depending on the exact call path.

This fixes the core semantic mismatch: **assignment and passing alias**, and cloning an array is cheap
(shared-handle clone, not a deep clone).

Remaining work is mostly about API coverage + ergonomics (more Array methods, better iteration patterns,
explicit bridging with `rust.Vec<T>` in the metal profile).

## Note on `.clone()` noise

Because Haxe values are generally “reusable”, the backend sometimes needs to emit `.clone()` in Rust to
avoid move errors when the *same local* is used multiple times.

To keep output idiomatic, the compiler performs a small “clone elision” heuristic: when a local is only
used once in the current function body, it prefers moving the value instead of cloning it.

## Options considered

### Option A — `Vec<T>` (owned, by value)

Pros:
- simplest to emit
- fast and idiomatic Rust storage

Cons:
- incorrect aliasing semantics vs Haxe
- requires aggressive cloning to keep locals usable
- encourages APIs that “move” arrays, which Haxe users won’t expect

### Option B — `Rc<RefCell<Vec<T>>>` (shared + interior mutability)

Pros:
- correct aliasing semantics (cloning is `Rc::clone`, not deep clone)
- no “moved” errors for typical Haxe patterns
- matched the original single-thread `HxRef<T> = Rc<RefCell<T>>` approach

Cons:
- extra indirection + runtime borrow checks
- some Rust APIs become less ergonomic without borrow helpers
- not suitable once `sys.thread` support requires Haxe reference values to cross OS thread boundaries

### Option C — custom runtime type `hxrt::array::Array<T>`

Pros:
- can implement Haxe semantics explicitly (aliasing, bounds checks, iterators)
- can offer both “portable” and “idiomatic” APIs (e.g. safe borrows, slice views)
- hides interior-mutability details from generated code (cleaner output)

Cons:
- more runtime code and more compiler special-cases
- requires a migration across snapshots/examples

## Decision

**We moved to Option C: `hxrt::array::Array<T>` backed by `HxRef<Vec<T>>`.**

Goals of the runtime type:

- preserve Haxe aliasing semantics by default
- make “clone to preserve reuse” cheap (shared-handle clone)
- provide borrow helpers for metal/profile code when performance matters
- share the same thread-safe reference model used by classes, handles, and other HXRT values

### Relationship to profiles

- `Portable`: `Array<T>` means **Haxe array semantics** (shared, mutable, reusable).
- `Metal`: users should prefer `rust.Vec<T>` when they explicitly want Rust ownership semantics.
  Conversions between `Array<T>` and `rust.Vec<T>` must be explicit and documented.

## Evidence

The current contract is covered by:

- `test/snapshot/for_array_alias_mutating` for alias-preserving mutation during iteration.
- `test/snapshot/array_methods_slice_splice` for common `Array<T>` operations.
- `test/snapshot/array_shift_nullable_class_return` for `Array<Class>.shift()` returned as `Null<Class>`.
- `test/snapshot/rust_array_slice_views` plus the metal policy slice-view output-shape gate for
  zero-clone slice-borrow helpers.
- `runtime/hxrt/src/array.rs` for the concrete `hxrt::array::Array<T>` implementation.
