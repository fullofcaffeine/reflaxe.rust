# Portable Module Mapping Contract (Tier1 Seed)

This document defines ownership mapping for Tier1 portable modules:

- Haxe-source implementation
- runtime binding (`hxrt`)
- compiler intrinsic/shim
- mixed ownership (explicitly split)

Contract inputs:

- `test/portable_allowlist.json`
- `test/portable_conformance_tier1.json`
- `docs/portable-semantics-v1.md`

## Ownership class definitions

1. `haxe_source`
  - Behavior lives in Haxe std sources (`std/rust/_std/**/*.hx` overrides or upstream std implementation).
2. `runtime_binding`
  - Haxe surface delegates behavior to runtime package functions in `runtime/hxrt`.
3. `compiler_intrinsic`
  - Behavior is emitted directly by compiler lowering/shim generation.
4. `mixed`
  - Surface spans more than one class above; split is explicit and test-gated.

## Tier1 mapping table

| Module | Ownership class | Primary implementation location | Runtime dependency | Tier1 conformance cases |
| --- | --- | --- | --- | --- |
| `Std` | `mixed` (`compiler_intrinsic` + `runtime_binding`) | `src/reflaxe/rust/RustCompiler.hx`; no tracked `std/rust/_std/Std.hx` override | `runtime/hxrt/string.rs`, `runtime/hxrt/exception.rs`, core helpers | `exceptions_typed_dynamic`, `null_string_concat`, `virtual_dispatch` |
| `Sys` | `mixed` (`haxe_source` + `runtime_binding`) | `std/rust/_std/Sys.hx` | `runtime/hxrt/sys.rs` | `sys_getenv_null` |

`Std` is intentionally called out because it is not part of the `std/rust/_std/**/*.hx` override
ledger. Its current Rust-target behavior is owned by compiler lowering plus runtime helpers, while
upstream-colliding Haxe-source std overrides live under `std/rust/_std/`.

## Governance rule

Any ownership change for a Tier1 module must update all of:

1. this mapping document,
2. `test/portable_conformance_tier1.json`,
3. relevant conformance fixtures in `test/semantic_diff`.
