# Function values (baseline)

## Why this matters

Portable Haxe code uses function values everywhere (callbacks, iterators, “Lambda”-style helpers, etc.).
To reach v1.0 stdlib parity, the Rust target must support *passing*, *storing*, and *calling* functions.

## What we support (baseline)

In this baseline implementation:

- Haxe function types (`A->B`, `(A,B)->C`, etc.) are lowered to:
  - `std::rc::Rc<dyn Fn(A, B, ...) -> R>`
- Haxe function literals (`function(...) ...`) are lowered to:
  - `std::rc::Rc::new(move |...| { ... })`
- When a function *value* is expected but the expression is a Rust function item/path,
  the compiler wraps it into an `Rc` closure automatically.

## Constraints (important)

This is intentionally a **baseline**:

- Closures are emitted as `move` so they can be stored/passed as `'static`.
- That means captured values are captured **by value** (snapshot semantics), not by-reference like some Haxe targets.
  - If you rely on “mutating an outer local from inside a callback”, that is not guaranteed yet.
- We currently use `Fn` (not `FnMut`), so callback mutation patterns may require future work.

Snapshots:

- `test/snapshot/function_values_basic`
- `test/snapshot/function_values_return`

