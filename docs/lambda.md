# Lambda Helpers (reflaxe.rust)

This target ships a `std/Lambda.cross.hx` implementation that is designed to work well with reflaxe.rust’s current iteration model.

## Key design choice: inline-only, non-emitted

- `Lambda` is treated as a **compile-time helper**: the Rust backend does **not** emit a `lambda.rs` module.
- All functions are written to be **inline-safe** (no early `return` inside loops), so `using Lambda` expands into plain loops at call sites.

Why:
- Keeps the Rust backend from needing a general-purpose runtime representation of `Iterable<T>`.
- Matches how many Haxe targets use `Lambda`: as a convenience layer that optimizes away.

## Performance notes

- Most helpers allocate eagerly (typically returning `Array<T>`). For large data flows, prefer iterator-style Rust-first APIs (`rust.Iter<T>`, `rust.Slice<T>`, etc.) where applicable.

## `Lambda.count` Optional Predicate

`Lambda.count(it, pred)` is supported.

- `Lambda.count(it)` counts all items.
- `Lambda.count(it, pred)` counts only items where `pred(item)` returns `true`.

Why this works:

- The Rust override types the optional predicate as `Null<(item:T) -> Bool>`.
- The backend lowers the omitted/null predicate to Rust `None`.
- The provided predicate path lowers to an `Option`-wrapped function value and calls through the
  non-null branch.

Evidence:

- `test/snapshot/lambda_helpers` covers the no-predicate `count()` path.
- `test/snapshot/null_optional_args` covers `count(x -> ...)` with an optional function argument.
