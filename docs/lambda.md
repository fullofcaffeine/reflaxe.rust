# Lambda Helpers (reflaxe.rust)

This target ships a `std/Lambda.hx` implementation that is designed to work well with reflaxe.rust’s current iteration model.

## Key design choice: inline-only, non-emitted

- `Lambda` is treated as a **compile-time helper**: the Rust backend does **not** emit a `lambda.rs` module.
- All functions are written to be **inline-safe** (no early `return` inside loops), so `using Lambda` expands into plain loops at call sites.

Why:
- Keeps the Rust backend from needing a general-purpose runtime representation of `Iterable<T>`.
- Matches how many Haxe targets use `Lambda`: as a convenience layer that optimizes away.

## Performance notes

- Most helpers allocate eagerly (typically returning `Array<T>`). For large data flows, prefer iterator-style Rusty APIs (`rust.Iter<T>`, `rust.Slice<T>`, etc.) where applicable.

## Current limitation

- `Lambda.count(it, pred)` (optional predicate) is not provided yet because optional function arguments need better lowering for this target.
  - Use `Lambda.count(it)` for total count.
  - Use `Lambda.filter(it, pred).length` to count with a predicate.

