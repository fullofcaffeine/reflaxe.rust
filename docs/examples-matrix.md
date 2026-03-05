# Examples Matrix (portable + metal)

This page maps examples to the two supported profile contracts.

## Flagship cross-profile app

`examples/chat_loopback` is the primary side-by-side reference app.

Run:

```bash
cd examples/chat_loopback
npx haxe compile.hxml
(cd out && cargo run -q)

npx haxe compile.metal.hxml
(cd out_metal && cargo run -q)
```

CI variants:

- `compile.ci.hxml`
- `compile.metal.ci.hxml`

## Scenario coverage

| Scenario / Example | portable | metal | Notes |
| --- | --- | --- | --- |
| `examples/chat_loopback` | Yes | Yes | Flagship comparison app (interactive TUI + network loopback + Haxe-authored Rust tests). |
| `examples/profile_storyboard` | Yes | Yes | Compact portable-vs-metal reference app (best starting point for metal-first source-style comparison). |
| `examples/metal_first_dataflow` | No | Yes | Dedicated metal-style reference (`Result`/`Option`/`Vec`, strict-boundary-safe app code). |
| `examples/hello` | Yes | No | Minimal portable sanity check. |
| `examples/bytes_ops` | Yes | No | Bytes APIs + Haxe-authored Rust tests (`@:rustTest`). |
| `examples/serde_json` | Yes | No | Typed Serde JSON surfaces (portable contract). |
| `examples/async_retry_pipeline` | No | Yes | Async scenario (`rust_async`). |
| `examples/tui_todo` | Yes | No | Large app with deterministic TUI harness tests. |
| `examples/sys_file_io` | Yes | No | Sys file APIs / stat / rename checks. |
| `examples/sys_net_loopback` | Yes | No | Focused socket API smoke test. |
| `examples/sys_process` | Yes | No | Process spawning + I/O checks. |
| `examples/sys_thread_smoke` | Yes | No | Thread primitives smoke. |
| `examples/thread_pool_smoke` | Yes | No | Fixed thread pool smoke scenario. |

## Profile style anchors

- Portable-first style:
  - `examples/profile_storyboard/profile/PortableRuntime.hx`
  - `examples/chat_loopback/profile/PortableRuntime.hx`
- Metal Rust-first style:
  - `examples/metal_first_dataflow/Harness.hx`
  - `examples/profile_storyboard/profile/MetalRuntime.hx`
  - `examples/chat_loopback/profile/MetalRuntime.hx`

## Metal-First Reference Flow

Use `examples/profile_storyboard` for the fastest side-by-side authoring/codegen comparison:

```bash
cd examples/profile_storyboard
cargo hx --profile portable --action run
cargo hx --profile metal --action run
```

Inspect generated Rust:

- `examples/profile_storyboard/out/src/main.rs`
- `examples/profile_storyboard/out_metal/src/main.rs`

Native baseline parity check:

```bash
bash examples/profile_storyboard/scripts/compare-native.sh
```

Baseline crate location: `examples/profile_storyboard/native/`.

Use `examples/metal_first_dataflow` for a dedicated metal-only authoring example:

```bash
cd examples/metal_first_dataflow
npx haxe compile.hxml && (cd out && cargo run -q)
```

Performance parity workflow (portable vs metal vs pure-rust baselines):

```bash
bash scripts/ci/perf-hxrt-overhead.sh --gate-mode soft
```

Artifacts:

- `.cache/perf-hxrt/results/comparison.json`
- `.cache/perf-hxrt/results/summary.md`

## Test authoring

- `examples/bytes_ops`, `examples/chat_loopback`, `examples/metal_first_dataflow`, `examples/profile_storyboard`, and `examples/tui_todo`
  use Haxe-authored Rust tests (`@:rustTest`).
- See `docs/haxe-rust-tests.md` for metadata and generated wrapper behavior.
