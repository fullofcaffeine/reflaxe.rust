# `Null<T>` and Optional Arguments (Rust target)

This target represents Haxe `Null<T>` as Rust `Option<T>` when the Rust value type has no native null
sentinel. Reference-like runtime types that already carry Haxe nullability stay in their native Rust
shape instead.

## What maps to `Option<T>`

- Explicit `Null<T>` in Haxe code when `T` lowers to a Rust value type with no null sentinel.
- Optional arguments without an explicit default value behave like `null` when omitted, so they are expected to be typed as `Null<T>` for Rust output.

## What does not need an extra `Option<T>`

Some Rust representations already carry their own Haxe null value:

- class handles (`HxRef<Class>`)
- arrays (`hxrt::array::Array<T>`)
- nullable strings (`hxrt::string::HxString`)
- interface/function-style dynamic references (`HxDynRef<dyn ...>`)
- `Dynamic`

For generic std APIs that must return `Null<T>` for any `T`, the runtime may still produce
`Option<T>` internally. At a typed callsite, the compiler maps `None` back to the explicit null
sentinel when `T` instantiates to one of these reference-like shapes. For example,
`Array<Class>.shift()` can be returned from a `Null<Class>` function as `HxRef::null()` on the empty
case rather than leaking `Option<HxRef<Class>>` into the function signature.

## Key codegen rules

- `null` becomes `None`.
- Assigning a non-null `T` into a `Null<T>` slot stores `Some(value)`.
- Returning a non-null `T` from a `Null<T>` function stores `Some(value)`.
- Returning a generic `Null<T>` helper result into a nullable reference-like type maps `None` to the
  type's explicit null sentinel.
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

See also `test/snapshot/array_shift_nullable_class_return` for the `Array<Class>.shift()` nullable
reference case.
