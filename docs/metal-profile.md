# Metal Profile Specification (`-D reflaxe_rust_profile=metal`)

`metal` is an **experimental** Rust-first+ profile for teams that want near-Rust authoring control
from Haxe while still using typed framework boundaries.

## Goals

- Keep Rust-first API design (`Ref`, `MutRef`, `Slice`, `Option`, `Result`, etc.).
- Add a typed low-level interop surface for gaps that are not yet modeled as dedicated `std/` APIs.
- Keep app code analyzable and policy-enforced (no raw escape hatches by default).
- Make `metal` the primary profile for near-pure-Rust hot-path performance.

## Performance objective

`metal` is the profile where performance parity work is focused first.

- Directional target: approach pure Rust runtime throughput in steady-state workloads.
- Practical benchmark target (current soft policy): keep hot-loop runtime very close to pure Rust (around `<= 1.05x` where feasible).
- Size/startup overhead from `hxrt` still exists today; reducing that footprint is an active optimization track.

Benchmark mechanics and current ratios are tracked in [HXRT overhead benchmarks](perf-hxrt-overhead.md).

## Non-goals (current milestone)

- Full parity with handwritten Rust lifetime generics.
- Replacing `rusty`; `metal` is additive and opt-in.
- Forcing all projects into low-level interop patterns.

## Profile Selection

- Primary switch: `-D reflaxe_rust_profile=metal`
- Alias: `-D rust_metal`

Conflict rules:

- `rust_metal` conflicts with `rust_idiomatic` unless an explicit matching profile is provided.
- `reflaxe_rust_profile=<...>` must be one of: `portable|idiomatic|rusty|metal`.

## Boundary Policy

In `metal`, strict app boundary mode is enabled by default (`reflaxe_rust_strict`).

- Raw app-side `untyped __rust__(...)` is rejected.
- Framework-owned typed facades are allowed.

Current typed façade:

- `rust.metal.Code.expr(...)`
- `rust.metal.Code.stmt(...)`

These compile through the framework injection shim and keep the interop surface documented and typed.

Reference example:

- `examples/chat_loopback/profile/MetalRuntime.hx` demonstrates both `Code.expr(...)` and
  `Code.stmt(...)` in a strict-boundary app flow.
- Build with:

```bash
cd examples/chat_loopback
npx haxe compile.metal.hxml
(cd out_metal && cargo run -q)
```

## Relationship To Rusty

- `rusty`: Rust-first APIs and ownership/borrow-oriented standard surfaces.
- `metal`: `rusty` + typed low-level interop façade + stricter default app-boundary enforcement.

Use `rusty` when typed `rust.*` APIs are enough. Use `metal` when you need occasional low-level Rust
constructs that do not yet have a dedicated typed wrapper.

## Async Preview

`rust_async_preview` is available in Rust-first profiles:

- `reflaxe_rust_profile=rusty`
- `reflaxe_rust_profile=metal`
