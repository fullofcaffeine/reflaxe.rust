# Metal-First Dataflow

Focused `metal`-only example that demonstrates Rust-first Haxe authoring patterns.

## What this shows

- explicit `rust.Result` / `rust.Option` control flow,
- `rust.Vec<T>` usage for Rust-native collection intent,
- strict-boundary-safe app code (no app-side `__rust__` / injection).

## Run

```bash
cd examples/metal_first_dataflow
npx haxe compile.hxml
(cd out && cargo run -q)
```

## Test

```bash
cd examples/metal_first_dataflow
npx haxe compile.ci.hxml
(cd out_ci && cargo test -q)
```

Or through the project task driver:

```bash
cargo hx --project examples/metal_first_dataflow --action run
cargo hx --project examples/metal_first_dataflow --ci --action test
```

## Why no portable variant

This scenario is intentionally authored as a metal-style reference, so it keeps only metal compile targets.
