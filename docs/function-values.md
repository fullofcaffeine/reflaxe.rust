# Function values

## Why this matters

Portable Haxe code uses function values everywhere (callbacks, iterators, “Lambda”-style helpers, etc.).
To reach v1.0 stdlib parity, the Rust target must support *passing*, *storing*, and *calling* functions.

## What we support

Current support includes:

- Haxe function types (`A->B`, `(A,B)->C`, etc.) are lowered to:
  - `std::rc::Rc<dyn Fn(A, B, ...) -> R>`
- Haxe function literals (`function(...) ...`) are lowered to:
  - `std::rc::Rc::new(move |...| { ... })`
- When a function *value* is expected but the expression is a Rust function item/path,
  the compiler wraps it into an `Rc` closure automatically.
- `this.method` function values are supported.
  - The compiler captures an owned receiver handle and emits a callable closure with the correct
    Rust receiver dispatch.
- Upstream-style Haxe `dynamic function` members are supported.
  - The compiler lowers them to stored function-value backing fields plus wrapper methods, so both
    `obj.onData = fn` assignment and subclass overrides work.
  - This is the mechanism used by `std/haxe/http/HttpBase.cross.hx`.

## Constraints (important)

The remaining limitations are mostly about closure capture semantics, not basic callable shape:

- Closures are emitted as `move` so they can be stored/passed as `'static`.
- That means captured values are captured **by value** (snapshot semantics), not by-reference like some Haxe targets.
  - If you rely on “mutating an outer local from inside a callback”, that is not guaranteed yet.
- We currently use `Fn` (not `FnMut`), so callback mutation patterns may require future work.

Snapshots:

- `test/snapshot/function_values_basic`
- `test/snapshot/function_values_return`
