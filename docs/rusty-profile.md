# Rusty Profile Specification (`-D reflaxe_rust_profile=rusty`)

The Rust target supports **three profiles**:

- `Portable` (default): prioritize Haxe semantics + portability, even if output is less idiomatic Rust.
- `Idiomatic`: keep Haxe semantics, but bias the emitter toward cleaner, more idiomatic Rust output.
- `Rusty`: opt into a Rust-first surface for developers who want Haxe syntax with Rust idioms.

This document defines what **Rusty** means, what it is *not*, and how user code should structure
interop so final apps remain injection-free.

## Goals

- Let developers write code that *feels close to Rust* (ownership-aware APIs, explicit options/results,
  slices/refs, iterators) while still using Haxe syntax and tooling.
- Keep application code “pure Haxe”: **no raw `__rust__` in apps/examples**. Rust is an escape hatch,
  but it belongs in framework code (`std/`, `runtime/`) behind typed APIs.
- Make the boundary between “portable Haxe” and “Rusty Haxe” explicit and ergonomic:
  - portable code should remain easy to write
  - Rusty code should be explicit about where Rust concepts are used

## Non-goals (v1.0)

- Perfect lifetime modeling. Haxe has no lifetime parameters; Rusty APIs should either:
  - return owned values, or
  - use `rust.Ref<T>` / `rust.MutRef<T>` / `rust.Slice<T>` as *borrow tokens* with best-effort safety.
- Full replacement of the Rust borrow checker. Rust will still enforce borrowing rules on generated code.
- Exposing every Rust feature. Rusty is an opinionated subset focused on “apps that feel Rusty”.

## Selecting the profile

- `Portable` (default): no define needed
- `Idiomatic`: `-D rust_idiomatic` or `-D reflaxe_rust_profile=idiomatic`
- `Rusty`: `-D reflaxe_rust_profile=rusty`

## Core surfaces (Rusty)

Rusty code should prefer the explicit Rust-like surfaces under `std/rust/*` over Haxe “portable”
surfaces when the developer wants Rust semantics.

## Borrow-checker ergonomics (Rusty)

Rusty cannot model lifetimes directly (Haxe has no lifetime parameters), but it can still make borrowing
feel natural by providing **borrow-first APIs** and by making “ownership boundaries” explicit.

Guidelines for Rusty APIs:

- Prefer `rust.Ref<T>` / `rust.Slice<T>` / `rust.Str` for parameters when the callee only needs to read.
- Prefer `rust.MutRef<T>` / `rust.MutSlice<T>` (when available) when the callee mutates data.
- Prefer returning owned values unless the performance win from borrowing is clear and safe.
- Avoid silent cloning in Rusty APIs; when cloning is needed, prefer an explicit conversion (`toOwned`,
  `clone`, `intoOwned`, etc.) so users can reason about allocations and moves.

This keeps the “Rust feel” while still allowing users to write portable code in the default profile.

### Borrowing + referencing

Use these types to communicate “borrow intent” to the compiler and codegen:

- `rust.Ref<T>`: borrowed shared reference (`&T`)
- `rust.MutRef<T>`: borrowed mutable reference (`&mut T`)
- `rust.Str`: borrowed string slice (`&str`)
- `rust.Slice<T>`: borrowed slice (`&[T]`)
- `rust.MutSlice<T>`: borrowed mutable slice (`&mut [T]`)

Guideline:
- Prefer `rust.Ref<T>`/`rust.Slice<T>` parameters in Rusty APIs to avoid cloning/moving.
- Prefer returning owned values unless borrowing is clearly beneficial.

### Collections

Rusty code should prefer Rust-native collections (extern wrappers) when the intent is “Rust-like”:

- `rust.Vec<T>` for growable vectors
- `rust.HashMap<K,V>` for maps

Portable `Array<T>` remains valid, but it is *not* the Rusty-first choice.

### Option / Result

Rusty code should prefer explicit `Option<T>` / `Result<T, E>` surfaces:

- `rust.Option<T>` / `haxe.ds.Option<T>` mapping to Rust `Option<T>`
- `rust.Result<T, E>` / `haxe.functional.Result<T, E>` mapping to Rust `Result<T, E>`

Guideline:
- Use `Null<T>` only when modeling Haxe-idiomatic optionality is the goal.
- Use `Option<T>` / `Result<T, E>` when writing Rusty APIs.

### Strings

Rusty code should bias toward borrowed strings for inputs:

- inputs: `rust.Str` (`&str`)
- outputs: owned `String` (Haxe `String`) unless borrowing is explicit and safe

## Interop boundary (no injections in apps)

### Rule

- Application code must not call `__rust__` directly.
- Framework code may use `__rust__` as an escape hatch, but should prefer:
  - `extern` bindings + `@:native("...")`
  - small, typed wrappers that hide raw Rust code

### Recommended pattern

1. Add/extend a typed API in `std/` (or a dedicated framework module).
2. Implement it using either:
   - `extern` + `@:native(...)` (preferred), or
   - `untyped __rust__(...)` internally (fallback)
3. Keep examples “pure Haxe” using only the typed API.

## Compatibility notes

- Rusty is **opt-in** and must not silently change Portable semantics.
- When Rusty enables a different representation (e.g., `rust.Vec<T>` vs `Array<T>`), conversions must
  be explicit (`intoVec`, `toArray`, etc.) and documented.
