# Profiles (`-D reflaxe_rust_profile=...`)

`reflaxe.rust` supports three output profiles. Profiles are compile-time flags that trade off Haxe
portability vs Rust idioms.

Select a profile via:

- `-D reflaxe_rust_profile=portable|idiomatic|rusty`

Compatibility note:

- `-D rust_idiomatic` is an alias for `-D reflaxe_rust_profile=idiomatic`.

## Portable (default)

Goal: compile “normal Haxe” with predictable Haxe semantics.

- Prioritizes Haxe aliasing and reuse semantics over Rust ownership purity.
- Uses runtime wrappers when needed (for example `Array<T>` is `hxrt::array::Array<T>`).
- Default choice for portable libraries and cross-target code.

## Idiomatic

Goal: keep Portable semantics, but emit cleaner Rust.

- Same runtime representation as Portable.
- Tries to reduce noise and warnings (clone elision, cleaner blocks, avoid unreachable code, etc.).
- Intended to be rustfmt-clean and warning-free for core examples/snapshots.

## Rusty

Goal: opt into a Rust-first surface while still writing Haxe syntax.

- Enables the Rust-facing APIs under `std/rust/*` (Vec/Slice/Str/Option/Result, borrow helpers).
- Prefers borrow-first APIs (`rust.Ref`, `rust.MutRef`, slices) so Rust output can be more idiomatic
  without silently cloning/moving.
- Still aims to keep app code “pure Haxe” (see injection policy below).

Details: `docs/rusty-profile.md`.

## Injection policy (apps stay pure)

Rule:

- Apps/examples should not call `__rust__` directly.
- Rust injections belong in framework code (`std/`, runtime, or dedicated interop modules) behind
  typed APIs (externs/abstracts/macros).

Enforcement:

- Examples and snapshot tests compile with `-D reflaxe_rust_strict_examples`.

## Where profile differences are tested

- Rusty-specific snapshots live under `test/snapshot/rusty_*`.
- Some cases (for example `test/snapshot/tui_todo`) include `compile.rusty.hxml` variants.

See also:

- `docs/v1.md` for the v1.0 support matrix and build workflow.

