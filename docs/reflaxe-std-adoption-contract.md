# `reflaxe.std` Adoption Contract (Rust)

Status: planned under `haxe.rust-oo3.18` (Milestone 16)

This document defines the Rust-side contract for adopting a shared portable idiom package.

## Why this exists

`reflaxe.rust` already has:

- portable vs metal contracts,
- family governance artifacts (`reflaxe.family.std`),
- Rust-native `rust.Option`/`rust.Result` surfaces.

The missing piece is a user-facing portable idiom package that can be shared across backends
without blurring portable/native boundaries.

`reflaxe.std` should grow into a vessel for portable idioms beyond `Option` / `Result`, but v1 is
intentionally narrow. The first slice is small on purpose so the family can lock semantics,
fixtures, and migration rules before broadening the public surface.

## Two-layer package model

1. `reflaxe.family.std` (governance layer)
   - Owns contract specs, allowlists, conformance mappings, provenance rules, and shared fixtures.
   - Is not a user-facing idiom API.
2. `reflaxe.std` (user-facing portable API layer)
   - Installed by app authors (via lix/haxelib workflow).
   - Exposes portable idioms with backend mappings.
   - Starts with `Option` / `Result` in v1.

Rust keeps both layers explicit and separate.

## Canonical portable API decisions (v1)

- Public types:
  - `Option<T>`
  - `Result<T, E>`
- Public constructors:
  - `Some` / `None`
  - `Ok` / `Err`
- Public helper style:
  - tool/extension modules (for example `OptionTools`, `ResultTools`) instead of large instance APIs.
- Explicitly out for v1:
  - public `Outcome<T, E>` alias surface.

Expected longer-term direction after v1 stabilizes:

- small portable algebraic/result-like helpers,
- portable concurrency or effect shims when they can preserve stable semantics,
- backend adapters that remain explicit and typed rather than silently rewriting meaning.

Non-goal:

- turning `reflaxe.std` into a dumping ground for backend-specific APIs.

## Rust boundary rules

Portable lane:

- portable modules should import `reflaxe.std` surfaces for cross-target idioms.
- importing native target modules (`rust.*`, `go.*`, etc.) is a portability signal:
  - warning by default,
  - error with `-D rust_portable_native_import_strict`.

Native lane:

- `rust.Option`/`rust.Result` remain explicit native APIs.
- native APIs are not silently substituted in portable code.
- conversions between portable and native surfaces must be explicit adapters.
- Rust bridge module: `rust.adapters.ReflaxeStdAdapters`.
- importing `rust.adapters.*` from portable modules is intentionally reported as a native import
  portability signal (warning by default, error with `-D rust_portable_native_import_strict`).

## Rust lowering expectation

When portable code uses `reflaxe.std.Option/Result`, Rust lowering should map to native Rust
`Option/Result` representations without changing portable semantics.

Rule: representation optimization is allowed; semantic mode switching is not.

Concrete expectation:

- `reflaxe.std.Option<T>` -> Rust `Option<T>`
- `reflaxe.std.Result<T, E>` -> Rust `Result<T, E>`

This means portable Rust output should not pay a wrapper-enum tax for these abstractions. The
target state is "portable API, native Rust representation". When performance differs from
Rust-first code, that difference should come from conservative codegen details (for example extra
clones/temporaries), not from using a different underlying Rust type.

This is the same core rule the broader package should follow in the future: portable APIs should
lower to the best-performing native representation available on a backend when semantics match,
while keeping the portable authoring contract stable and explicit.

## Migration contract

- Existing Rust-native code can keep `rust.*` imports.
- Portable code should converge to `reflaxe.std` imports.
- Transition helpers/adapters must be typed and avoid public `Dynamic`/`Reflect` usage.
- Any deprecations must ship with migration notes and CI evidence.

## CI and report requirements

Adoption work must remain contract-first and deterministic:

1. add/update semantic fixtures before lowering changes,
2. keep lane/profile semantics stable for portable code,
3. emit deterministic contract/runtime/optimizer artifacts,
4. include pinned family package/version provenance in reports.

Current contract-first fixture seed:

- `test/semantic_diff/portable_option_result_basics`

## Related docs

- `docs/profiles.md`
- `docs/stdlib-policy.md`
- `docs/portable-semantics-v1.md`
- `docs/portable-module-mapping-contract.md`
- `docs/spikes/reflaxe-std-cross-repo-handoff.md`
