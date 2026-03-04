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
  - Behavior lives in Haxe std sources (`std/**/*.cross.hx` overrides or upstream std implementation).
2. `runtime_binding`
  - Haxe surface delegates behavior to runtime package functions in `runtime/hxrt`.
3. `compiler_intrinsic`
  - Behavior is emitted directly by compiler lowering/shim generation.
4. `mixed`
  - Surface spans more than one class above; split is explicit and test-gated.

## Tier1 mapping table

| Module | Ownership class | Primary implementation location | Runtime dependency | Tier1 conformance cases |
| --- | --- | --- | --- | --- |
| `Std` | `mixed` (`compiler_intrinsic` + `runtime_binding`) | `src/reflaxe/rust/RustCompiler.hx` + `std/Std.cross.hx` | `runtime/hxrt/string.rs`, `runtime/hxrt/exception.rs`, core helpers | `exceptions_typed_dynamic`, `null_string_concat`, `virtual_dispatch` |
| `Sys` | `mixed` (`haxe_source` + `runtime_binding`) | `std/Sys.cross.hx` | `runtime/hxrt/sys.rs` | `sys_getenv_null` |

## Governance rule

Any ownership change for a Tier1 module must update all of:

1. this mapping document,
2. `test/portable_conformance_tier1.json`,
3. relevant conformance fixtures in `test/semantic_diff`.
