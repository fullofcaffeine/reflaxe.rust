# Array Semantics Roadmap (Haxe `Array<T>` → Rust)

This document records the long-term plan for how `reflaxe.rust` should represent **Haxe `Array<T>`**
in Rust output, and why.

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

`Array<T>` currently maps to a Rust `Vec<T>` in portable output. The backend compensates by cloning in
some callsites (to avoid moves), but this is not a complete semantic model of Haxe aliasing.

This is acceptable for early snapshots, but **not** a long-term v1.0 semantic target.

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
- aligns with the existing `HxRef<T> = Rc<RefCell<T>>` approach

Cons:
- extra indirection + runtime borrow checks
- some Rust APIs become less ergonomic without borrow helpers

### Option C — custom runtime type `hxrt::array::Array<T>`

Pros:
- can implement Haxe semantics explicitly (aliasing, bounds checks, iterators)
- can offer both “portable” and “idiomatic” APIs (e.g. safe borrows, slice views)
- hides interior-mutability details from generated code (cleaner output)

Cons:
- more runtime code and more compiler special-cases
- requires a migration across snapshots/examples

## Decision

**We will move to Option C: `hxrt::array::Array<T>` backed by `Rc<RefCell<Vec<T>>>`.**

Goals of the runtime type:

- preserve Haxe aliasing semantics by default
- make “clone to preserve reuse” cheap (`Rc` clone)
- provide borrow helpers for Rusty/profile code when performance matters

### Relationship to profiles

- `Portable` / `Idiomatic`: `Array<T>` means **Haxe array semantics** (shared, mutable, reusable).
- `Rusty`: users should prefer `rust.Vec<T>` when they explicitly want Rust ownership semantics.
  Conversions between `Array<T>` and `rust.Vec<T>` must be explicit and documented.

## Follow-up tasks (implementation plan)

1. Introduce `hxrt::array::Array<T>` runtime type:
   - internal storage: `Rc<RefCell<Vec<T>>>`
   - methods: `len`, `get`, `set`, `push`, `pop`, `iterator`/`iter` helpers
2. Update backend type mapping:
   - `Array<T>` → `hxrt::array::Array<T>`
   - array literals `[...]` → `hxrt::array::Array::from_vec(vec![...])` (or equivalent)
3. Update codegen for common operations:
   - `arr.length`, `arr[idx]`, `arr[idx] = v`
   - `for (x in arr)` lowering (borrow-safely)
4. Add semantic snapshots:
   - aliasing: `b = a; b.push(1); trace(a.length)`
   - passing to functions mutates caller
5. Revisit clone heuristics:
   - most `Array<T>` clones become `Rc::clone` (cheap)
   - reduce deep clones, keep Haxe reuse semantics

