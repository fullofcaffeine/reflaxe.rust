# Metal Profile Specification (`-D reflaxe_rust_profile=metal`)

`metal` is the Rust-first profile for performance-sensitive code.

## Goals

- Keep Rust-first API design (`Ref`, `MutRef`, `Slice`, `Option`, `Result`, etc.).
- Keep strict typed boundaries in app code by default.
- Make performance parity work measurable and enforceable.

## Selection

```bash
-D reflaxe_rust_profile=metal
```

No profile aliases are supported.

## Boundary policy

In `metal`, strict app boundary mode is enabled by default (`reflaxe_rust_strict`).

- Raw app-side `untyped __rust__(...)` is rejected.
- Framework-owned typed façades remain allowed.
- Low-level typed façade for controlled escapes:
  - `rust.metal.Code.expr(...)`
  - `rust.metal.Code.stmt(...)`

## Metal clean vs fallback

- **Default (metal clean):** contract violations are errors.
- **Fallback mode:** add `-D rust_metal_allow_fallback` to downgrade contract violations to warnings.
- Fallback diagnostics are emitted once per compile with an aggregate summary:
  - total `ERaw` fallback count,
  - affected module count,
  - top modules by fallback count.

Use fallback only as a migration tool while removing non-metal-clean boundaries.

### Viability summary (milestone 22.1 baseline)

For migration planning, metal can emit an aggregate viability signal:

```bash
-D rust_metal_viability_warn
```

This prints one summary warning with:

- overall viability score (0-100),
- module count and metal-ready module count,
- blocker count,
- top fallback-risk modules and global policy blockers.

The compiler stores this typed snapshot internally for deterministic report emission in milestone 22.2.

Current contract checks include:

- reflection/runtime-introspection modules (`Reflect`, `Type`, `haxe.rtti.*`),
- dynamic map semantics via `haxe.DynamicAccess`,
- dynamic-fallback opt-in defines (`rust_allow_unresolved_monomorph_dynamic`, `rust_allow_unmapped_coretype_dynamic`),
- nullable-string override (`rust_string_nullable`) in metal-clean mode.

## String and async defaults

- Default string representation is non-null Rust `String` (unless explicitly overridden).
- `-D rust_async` / `-D rust_async_preview` are supported in metal.

## Minimal Runtime Mode (`rust_no_hxrt`)

Metal can opt into a stricter runtime contract:

```bash
-D rust_no_hxrt
```

What this does:

- omits the bundled `hxrt` crate from generated output,
- omits `hxrt` from generated `Cargo.toml` dependencies,
- enforces a no-`hxrt` generated-code boundary (compile error on any `hxrt` reference).

Important constraints:

- requires `-D reflaxe_rust_profile=metal`,
- cannot be combined with `-D rust_string_nullable`,
- cannot be combined with `-D rust_async` / `-D rust_async_preview`,
- cannot be combined with `rust_hxrt_*` feature-selection defines.

Use this mode for Rust-first subsets that intentionally avoid portable runtime semantics.

## Performance objective

`metal` is the profile where parity vs pure Rust is tracked most aggressively:

- directional steady-state target around `<= 1.05x` where feasible,
- ongoing effort to shrink runtime overhead and unnecessary fallback usage.

See [HXRT overhead benchmarks](perf-hxrt-overhead.md).
