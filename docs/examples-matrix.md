# Examples Matrix (Profiles + Idioms)

This page maps example coverage by profile and highlights where to learn specific idioms.

## Flagship Cross-Profile App

`examples/chat_loopback` is the primary side-by-side reference app.

Why:
- Same scenario across all profiles (`portable`, `idiomatic`, `rusty`, `metal`).
- Profile differences are implementation-style and API-surface choices, not app-domain drift.

How to run:

```bash
cd examples/chat_loopback
npx haxe compile.portable.hxml
(cd out_portable && cargo run -q)

npx haxe compile.idiomatic.hxml
(cd out_idiomatic && cargo run -q)

npx haxe compile.rusty.hxml
(cd out_rusty && cargo run -q)

npx haxe compile.metal.hxml
(cd out_metal && cargo run -q)
```

CI variants:
- `compile.portable.ci.hxml`
- `compile.idiomatic.ci.hxml`
- `compile.rusty.ci.hxml`
- `compile.metal.ci.hxml`

## Scenario Coverage Matrix

| Scenario / Example | portable | idiomatic | rusty | metal | Notes |
| --- | --- | --- | --- | --- | --- |
| `examples/chat_loopback` | Yes | Yes | Yes | Yes | Flagship comparison app (network loopback + typed protocol + profile runtimes). |
| `examples/hello` | No | Yes | No | Yes | Minimal sanity check; includes dedicated metal variant. |
| `examples/bytes_ops` | No | Yes | Yes | No | Bytes APIs + native Rust tests for runtime behavior. |
| `examples/serde_json` | No | Yes | Yes | No | Typed Serde JSON surface usage. |
| `examples/async_retry_pipeline` | No | No | Yes | No | Rust-first async preview scenario. |
| `examples/tui_todo` | No | Yes | Yes | No | Large real app with deterministic TUI harness tests. |
| `examples/sys_file_io` | Yes (default compile) | Yes (CI compile) | No | No | Sys file APIs / stat / rename checks. |
| `examples/sys_net_loopback` | Yes (default compile) | Yes (CI compile) | No | No | Focused socket API smoke test. |
| `examples/sys_process` | Yes (default compile) | Yes (CI compile) | No | No | Process spawning + I/O checks. |
| `examples/sys_thread_smoke` | Yes | No | No | No | Basic thread primitives smoke. |
| `examples/thread_pool_smoke` | Yes | No | No | No | Fixed thread pool smoke scenario. |

## Idiom Anchors

Use these examples to study profile-specific style:

- Haxe-first (`portable`):
  - `examples/chat_loopback` (`PortableRuntime`)
  - `examples/sys_*` and thread smokes
- Bridge (`idiomatic`):
  - `examples/chat_loopback` (`IdiomaticRuntime`)
  - `examples/bytes_ops`, `examples/serde_json`
- Rust-first (`rusty`):
  - `examples/chat_loopback` (`RustyRuntime`)
  - `examples/async_retry_pipeline`
- Rust-first+ (`metal`):
  - `examples/chat_loopback` (`MetalRuntime` with `rust.metal.Code.expr/stmt`)
  - `examples/hello` metal compile variants for minimal smoke
