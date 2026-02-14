# Rusty Profile Specification (`-D reflaxe_rust_profile=rusty`)

The Rust target supports **four profiles**:

- `Portable` (default): prioritize Haxe semantics + portability, even if output is less idiomatic Rust.
- `Idiomatic`: keep Haxe semantics, but bias the emitter toward cleaner, more idiomatic Rust output.
- `Rusty`: opt into a Rust-first surface for developers who want Haxe syntax with Rust idioms.
- `Metal` (experimental): Rusty+ profile for typed low-level interop and stricter default app boundaries.

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

## Why Rusty Is Worth It

Rusty is the profile that gives Haxe code the strongest access to high-value Rust ideas:

- **Explicit ownership boundaries** in API design (owned values vs borrowed views).
- **Borrow-shaped signatures** (`Ref`, `MutRef`, slices, `&str`-like inputs) instead of implicit clone-heavy flows.
- **Rust-native error/data modeling** (`Option` / `Result`) as a default style, not a compatibility afterthought.
- **Predictable interop contracts** where low-level Rust concerns are visible in Haxe types rather than hidden in `Dynamic` or raw injections.

This is the main reason to choose Rusty: it lets teams keep Haxe tooling while writing APIs that map
more directly to Rust performance and correctness habits.

## Non-goals (v1.0)

- Perfect lifetime modeling. Haxe has no lifetime parameters; Rusty APIs should either:
  - return owned values, or
  - use `rust.Ref<T>` / `rust.MutRef<T>` / `rust.Slice<T>` as *borrow tokens* with best-effort safety.
- Full replacement of the Rust borrow checker. Rust will still enforce borrowing rules on generated code.
- Exposing every Rust feature. Rusty is an opinionated subset focused on “apps that feel Rusty”.

## What Rusty Is Not

- It is **not** "handwritten Rust with Haxe syntax."
- It is **not** a full lifetime-parameter language.
- It is **not** a guarantee that every generated function is zero-cost or clone-free.

Rusty is a pragmatic Rust-first authoring mode, not a complete reimplementation of the Rust type system.

## Selecting the profile

- `Portable` (default): no define needed
- `Idiomatic`: `-D rust_idiomatic` or `-D reflaxe_rust_profile=idiomatic`
- `Rusty`: `-D reflaxe_rust_profile=rusty`
- `Metal` (experimental): `-D rust_metal` or `-D reflaxe_rust_profile=metal`

## Core surfaces (Rusty)

Rusty code should prefer the explicit Rust-like surfaces under `std/rust/*` over Haxe “portable”
surfaces when the developer wants Rust semantics.

### Async/await preview (Rusty)

Rust-first profiles currently include an async/await preview surface behind:

- `-D reflaxe_rust_profile=rusty|metal`
- `-D rust_async_preview`

Core types/APIs:

- `rust.async.Future<T>`
- `rust.async.Async.await(...)` or `@:rustAwait ...`
- `rust.async.Async.blockOn(...)`

See: [Async/Await preview guide](async-await.md).
For the low-level typed façade available in metal, see [Metal profile](metal-profile.md).

## Borrow-checker ergonomics (Rusty)

Rusty cannot model lifetimes directly (Haxe has no lifetime parameters), but it can still make borrowing
feel natural by providing **borrow-first APIs** and by making “ownership boundaries” explicit.

### How this relates to the real borrow checker

- Borrow intent is expressed in Haxe via `rust.Ref<T>`, `rust.MutRef<T>`, `rust.Slice<T>`, etc.
- The Rust compiler still performs the final authority check on the emitted code.
- Where Haxe cannot express a Rust lifetime relationship, Rusty APIs should stay scoped (callback-style)
  or return owned values.
- If an API truly needs complex lifetime generics, use typed extern boundaries and handwritten Rust.

See also: [Lifetime Encoding Design](lifetime-encoding.md).

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

Note:
- Many helper APIs are borrow-first. For example, `rust.VecTools.len/get` take `rust.Ref<Vec<T>>`, so
  calling `VecTools.len(v)` compiles to `VecTools::len(&v)` and does not move the `Vec`.

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

### Example: Borrow-scoped Rusty APIs

The core idea is to keep borrows short-lived and explicit, while remaining "pure Haxe".

```haxe
using rust.OptionTools;

import rust.Borrow;
import rust.SliceTools;
import rust.StrTools;
import rust.Vec;
import rust.VecTools;

class Main {
  static function main(): Void {
    var v = new Vec<Int>();
    v.push(1); v.push(2);

    // Borrow a Vec as `&Vec<T>` (typed as `rust.Ref<Vec<T>>`) and return a value from the callback.
    var n = Borrow.withRef(v, vr -> VecTools.len(vr));

    // Borrow as a slice (`&[T]`) for the duration of the callback.
    var firstIsSome = SliceTools.with(v, s -> SliceTools.get(s, 0).isSome());

    // Borrow a String as `&str` for the duration of the callback.
    var contains = Borrow.withRef("bootstrap reflaxe.rust", hs -> {
      StrTools.with("reflaxe", needle -> rust.StringTools.contains(hs, needle));
    });

    trace([n, firstIsSome, contains].join(","));
  }
}
```

Notes:
- Prefer returning a value from the callback rather than assigning to a captured outer variable.
- This is required for the `Array<T>` slice path today (it passes a real Rust `Fn` closure into the runtime).

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
