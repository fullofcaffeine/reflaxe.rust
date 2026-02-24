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

Use fallback only as a migration tool while removing non-metal-clean boundaries.

## String and async defaults

- Default string representation is non-null Rust `String` (unless explicitly overridden).
- `-D rust_async` / `-D rust_async_preview` are supported in metal.

## Performance objective

`metal` is the profile where parity vs pure Rust is tracked most aggressively:

- directional steady-state target around `<= 1.05x` where feasible,
- ongoing effort to shrink runtime overhead and unnecessary fallback usage.

See [HXRT overhead benchmarks](perf-hxrt-overhead.md).
