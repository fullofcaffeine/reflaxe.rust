# Abstracts + `@:from`/`@:to` + numeric casts

## Haxe abstracts (general rule)

For the Rust target, **most Haxe abstracts are treated as their underlying type** in Rust output.

That matches Haxe’s design: abstracts are primarily a **compile-time** feature and typically do not exist as runtime wrappers.

Practical impact:

- `abstract Meters(Int)` compiles to Rust `i32`
- `enum abstract Color(Int)` compiles to Rust `i32`
- `@:from` / `@:to` affect typing, but runtime code usually becomes:
  - a cast (`as`) for numeric conversions, or
  - a static helper call (`*_Impl_`), depending on how Haxe lowers the operation

## Numeric casts

Rust requires explicit casts between numeric types.

When Haxe produces a typed `cast` between `Int` and `Float`, the backend emits a Rust `as` cast:

- `cast (f: Float)` to `Int` → `(f as i32)`
- `cast (i: Int)` to `Float` → `(i as f64)`

This is intended to be “portable enough” for Haxe semantics (truncation toward zero), while staying idiomatic Rust.

