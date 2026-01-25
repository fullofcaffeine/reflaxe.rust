# `Null<T>` and Optional Arguments (Rust target)

This target represents Haxe `Null<T>` as Rust `Option<T>`.

## What maps to `Option<T>`

- Any explicit `Null<T>` in Haxe code.
- Optional arguments without an explicit default value behave like `null` when omitted, so they are expected to be typed as `Null<T>` for Rust output.

## Key codegen rules

- `null` becomes `None`.
- Assigning a non-null `T` into a `Null<T>` slot stores `Some(value)`.
- Returning a non-null `T` from a `Null<T>` function stores `Some(value)`.
- Comparisons to `null` lower to `is_none()` / `is_some()` so they do **not** require `T: PartialEq`:
  - `x == null` → `x.is_none()`
  - `x != null` → `x.is_some()`
- Calling a nullable function value (`Null<(...)->...>`) unwraps before calling:
  - `pred(x)` → `pred.as_ref().unwrap()(x)` (after a `pred != null` check)

## Snapshot coverage

See `test/snapshot/null_optional_args` for a focused example that exercises:

- omitted optional args
- `Null<T>` assignment + return coercions
- `null` comparisons
- calling `Null<Fn>` values

