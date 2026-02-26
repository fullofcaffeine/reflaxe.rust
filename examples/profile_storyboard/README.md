# Profile Storyboard

Compact, deterministic reference app that runs the same scenario in both supported contracts:

- `portable` (Haxe-portable semantics first)
- `metal` (Rust-first semantics/performance contract)

This example is the quickest place to compare source style and generated Rust side-by-side.

## Run

From this directory:

```bash
# Portable
cargo hx --profile portable --action run

# Metal
cargo hx --profile metal --action run
```

Equivalent HXML flow:

```bash
npx haxe compile.hxml && (cd out && cargo run -q)
npx haxe compile.metal.hxml && (cd out_metal && cargo run -q)
```

## Style Anchors

- Portable runtime: `examples/profile_storyboard/profile/PortableRuntime.hx`
- Metal runtime: `examples/profile_storyboard/profile/MetalRuntime.hx`

Both implement the same `StoryboardRuntime` contract, so behavior stays comparable while authoring style differs.

## Inspect Generated Rust

After each build:

- portable output: `examples/profile_storyboard/out/src/main.rs`
- metal output: `examples/profile_storyboard/out_metal/src/main.rs`

This is useful for readability/idiomatic-shape reviews when tuning codegen.

## Native Baseline Parity Check

A hand-written Rust baseline for the same scenario lives under:

- `examples/profile_storyboard/native/`

Run a one-command output parity check:

```bash
bash examples/profile_storyboard/scripts/compare-native.sh
```

The script compiles/runs the generated metal crate and the native baseline crate and fails if their outputs differ.

## Parity Workflow

For performance parity tracking against pure Rust baselines (including no-runtime metal lower-bound):

```bash
bash scripts/ci/perf-hxrt-overhead.sh --gate-mode soft
```

Then inspect:

- `.cache/perf-hxrt/results/comparison.json`
- `.cache/perf-hxrt/results/summary.md`
