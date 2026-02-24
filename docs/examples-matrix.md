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
| `examples/profile_storyboard` | Yes | Yes | Compact profile-style reference app with typed runtime variants. |
| `examples/hello` | Yes | Yes | Minimal sanity check with portable and metal compile targets. |
| `examples/bytes_ops` | Yes | Yes | Bytes APIs + Haxe-authored Rust tests (`@:rustTest`). |
| `examples/serde_json` | Yes | Yes | Typed Serde JSON surfaces. |
| `examples/async_retry_pipeline` | No | Yes | Async preview scenario (`rust_async`). |
| `examples/tui_todo` | Yes | Yes | Large app with deterministic TUI harness tests. |
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
  - `examples/profile_storyboard/profile/MetalRuntime.hx`
  - `examples/chat_loopback/profile/MetalRuntime.hx`

## Test authoring

- `examples/bytes_ops`, `examples/chat_loopback`, `examples/profile_storyboard`, and `examples/tui_todo` use Haxe-authored Rust tests (`@:rustTest`).
- See `docs/haxe-rust-tests.md` for metadata and generated wrapper behavior.
