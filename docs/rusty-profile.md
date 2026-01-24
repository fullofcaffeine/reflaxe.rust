# Rusty Profile (reflaxe.rust)

This document defines the **third** compilation profile for reflaxe.rust: `rusty`.

The goal is to let developers write **Haxe** while opting into a surface that feels closer to **Rust idioms** and ecosystem types, without requiring app code to use raw Rust injection.

## Profiles (summary)

- **portable** (default)
  - Priority: preserve Haxe semantics + portability.
  - Runtime model: hxrt + `HxRef<T> = Rc<RefCell<T>>` for class instances.
  - Output Rust may be less idiomatic (by design).

- **idiomatic**
  - Priority: improve readability and reduce noise/warnings while preserving portable semantics.
  - Examples: `let` vs `let mut` inference, cleaner formatting, avoid unreachable match arms.

- **rusty** (`-D reflaxe_rust_profile=rusty`)
  - Priority: opt into Rust’s *types and patterns* via explicit `rust.*` APIs.
  - Still preserves the “framework-first escape hatch” rule (no raw `__rust__` in apps).
  - Mixes well with portable code: you only get “Rustiness” where you use `rust.*`.

## Hard rule: framework-first escape hatch

- **Application code** (examples/snapshots/user projects) should not call `untyped __rust__()`.
- Rust injection is allowed in **framework code** only (`std/`), behind Haxe APIs.
- The repo enforces this for examples/snapshots via `-D reflaxe_rust_strict_examples`.

## Rusty surface: `rust.*` types (initial v1 scope)

The `rust.*` package is an explicit opt-in. If you don’t use it, you keep portable Haxe behavior.

### `rust.Vec<T>` (maps to Rust `Vec<T>`)

Intent:
- Provide an owned, contiguous, growable vector with Rust semantics.

Expected code shapes:
- Haxe:
  - `var v = rust.Vec.fromArray([1,2,3]);`
  - `v.push(4);`
  - `for (x in v.iter()) trace(x);`
- Rust output (conceptual):
  - `let mut v: Vec<i32> = vec![1, 2, 3];`
  - `v.push(4);`
  - `for x in v.iter() { ... }`

### `rust.Str` (maps to Rust `&str`)

Intent:
- Allow Rust-idiomatic borrowed string parameters without cloning at callsites.

Guidance:
- Construct `rust.Str` via borrow scope (avoid storing it):
  - `StrTools.with(needle, s -> { ... })`
  - Or `Borrow.withRef(needle, r -> { var s: rust.Str = cast r; ... })`

### `rust.Slice<T>` (maps to Rust `&[T]`)

Intent:
- Borrowed views over contiguous data (initially via `Vec<T>.as_slice()`).

Helpers:
- `SliceTools.fromVec(Borrow.withRef(vec, ...))` produces a `Slice<T>`.
- `SliceTools.toArray(slice)` clones into a Haxe `Array<T>` for convenient iteration.

### `rust.Iter<T>` (maps to Rust `std::vec::IntoIter<T>`)

Intent:
- Enable iterator-first interop for APIs that traffic in owned iterators.

Helpers:
- `IterTools.fromVec(v)` converts a `rust.Vec<T>` into an owned iterator (consumes `v`; use `v.clone()` if needed).

### `rust.Option<T>` (maps to Rust `Option<T>`)

Intent:
- Expose Option explicitly, without overloading Haxe `Null<T>`.

Helpers:
- `using rust.OptionTools;` adds helpers like `isSome`, `unwrapOr`, plus macro-powered `map`/`andThen`.
- Common Rust pattern helpers:
  - `okOr("message")` / `okOrElse(() -> "message")` to convert `Option<T>` to `Result<T, String>`.

Current limitation (POC):
- For macro helpers that take callbacks (`map`, `andThen`, `unwrapOrElse`), prefer explicit callback typing to help the compiler:
  - `function(v: Int): rust.Option<Int> return ...`
- `OptionTools.isSome/isNone/unwrapOr` require `T: Clone` in Rust output (because the compiler currently clones the matched `Option<T>`).

Expected code shapes:
- Haxe:
  - `var o: rust.Option<Int> = rust.Option.Some(123);`
  - `switch (o) { case Some(v): ...; case None: ...; }`
- Rust output:
  - `let o: Option<i32> = Some(123);`
  - `match o { Some(v) => ..., None => ... }`

### `rust.Result<T,E>` (maps to Rust `Result<T,E>`)

Intent:
- Use Rust-style error modeling where you want it; keep exceptions portable elsewhere.

Helpers:
- `using rust.ResultTools;` adds helpers like `isOk`, `unwrapOr`, plus macro-powered `mapOk`/`mapErr`/`andThen`.
- `ResultTools.catchAny/catchString` convert portable exceptions into `Result` at boundaries.
- Common Rust pattern helpers:
  - `context("prefix")` for `Result<T, String>` to add readable error context.

Current limitation (POC):
- For macro helpers that take callbacks (`mapOk`, `mapErr`, `andThen`, `unwrapOrElse`), prefer explicit callback typing to help the compiler:
  - `function(v: Int): rust.Result<Int, String> return ...`
- `ResultTools.isOk/isErr/unwrapOr` require `T: Clone, E: Clone` in Rust output (because the compiler currently clones the matched `Result<T,E>`).

Expected code shapes:
- Haxe:
  - `return rust.Result.Ok(value);`
  - `return rust.Result.Err("oops");`
- Rust output:
  - `Ok(value)` / `Err("oops".to_string())` (or `String`, depending on E mapping)

### `rust.HashMap<K,V>` (maps to `std::collections::HashMap<K,V>`)

Intent:
- Use Rust’s standard hash map for rusty code paths.

### `rust.PathBuf` (maps to `std::path::PathBuf`)

Intent:
- Use Rust’s owned path buffer type for CLI/apps that want Rust-like path handling.

Helpers:
- `PathBufTools.fromString("path")` constructs a `PathBuf`.
- `PathBufTools.join(p, "child")` returns a new `PathBuf` without moving `p`.
- `PathBufTools.push(p, "child")` clones `p`, appends, and returns the new `PathBuf`.
- `PathBufTools.toStringLossy(p)` converts to `String` via `to_string_lossy()`.

Note:
- Most helpers take `rust.Ref<PathBuf>` so you can keep using the original path value (no implicit moves).

### `rust.OsString` (maps to `std::ffi::OsString`)

Intent:
- Expose OS-native strings for interop at the framework boundary.

Helpers:
- `OsStringTools.fromString(s)` / `OsStringTools.toStringLossy(os)`.

### `rust.Duration` / `rust.Instant` (maps to `std::time::*`)

Intent:
- Use Rust’s monotonic clock and durations for timing, throttling, and simple benchmarks.

Helpers:
- `InstantTools.now()` / `InstantTools.elapsedMillis(i)`.
- `DurationTools.fromMillis(ms)` / `DurationTools.sleep(d)`.

## Borrow-scoped helpers (closure-based)

Haxe has no lifetime syntax, so **borrowed references must be expressed via scope**.

Design direction:
- Provide APIs like:
  - `rust.Borrow.withRef(value, ref -> { ... })`
  - `rust.Borrow.withMut(value, mut -> { ... })`
- The callback receives a “borrow view” type (likely an `abstract`) that:
  - has no public constructors
  - cannot be stored meaningfully outside the callback (best-effort, enforced by macros where possible)

Target Rust shape:
- `Borrow.withRef(x, f)` → `f(&x)` (or `f(x.borrow())` if the backing type is interior-mutable)
- `Borrow.withMut(x, f)` → `f(&mut x)`

## Mutability inference in rusty/idiomatic profiles

Haxe method signatures do not encode `&self` vs `&mut self`.

For rusty APIs we introduce explicit metadata on extern methods (future direction):
- `@:rustMutating` on methods that require `&mut self` (e.g., `push`, `insert`, `remove`).

Compiler behavior:
- **idiomatic**: uses a conservative mutability inference (`let` vs `let mut`) based on detected mutations.
- **rusty (current)**: defaults locals to `let mut` to avoid borrow-checker friction while the `@:rustMutating` surface is still evolving.

## Conversions and portability

Conversions between portable Haxe containers and rusty containers are explicit:
- `rust.Vec.fromArray(Array<T>)` / `toArray()` (clone/convert elements as needed)
- Avoid hidden moves: rusty code should not silently invalidate a Haxe variable due to Rust ownership rules.

Iteration note:
- `for (x in v)` works for `rust.Vec<T>` and `rust.Slice<T>` by providing an `iterator()` method for Haxe typing.
- The compiler lowers `iterator()` on these types to Rust’s `iter().cloned()` to avoid moving the container.
  - This requires `T: Clone` in Rust output (works well for typical Haxe values like `HxRef<T>`).
- If you need non-`Clone` iteration, fall back to explicit helpers (clone/convert as needed):
  - `for (x in VecTools.toArray(v.clone())) ...`
  - `for (x in SliceTools.toArray(slice)) ...`

## Non-goals (v1)

- Full Rust lifetime/borrow checker UX at the Haxe surface.
- Implicitly turning every `Array<T>` into `Vec<T>` (portable code should stay portable).
