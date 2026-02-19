# Examples Matrix (Profiles + Idioms)

This page maps example coverage by profile and highlights where to learn specific idioms.

## Flagship Cross-Profile App

`examples/chat_loopback` is the primary side-by-side reference app.

Why:
- Same scenario across all profiles (`portable`, `idiomatic`, `rusty`, `metal`).
- Profile differences are implementation-style and API-surface choices, not app-domain drift.
- Interactive modern TUI chat loop with deterministic headless scenes for CI.

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

## Profile Style Micro-App

`examples/profile_storyboard` is the compact profile-idiom reference.

Why:
- Keeps one deterministic board scenario while each runtime implementation is intentionally written
  in the style of its target profile.
- Includes Haxe-authored Rust tests with thorough `@:rustTest` HaxeDoc in `StoryboardTests.hx`.

How to run:

```bash
cd examples/profile_storyboard
npx haxe compile.portable.hxml
(cd out_portable && cargo run -q)

npx haxe compile.idiomatic.hxml
(cd out_idiomatic && cargo run -q)

npx haxe compile.rusty.hxml
(cd out_rusty && cargo run -q)

npx haxe compile.metal.hxml
(cd out_metal && cargo run -q)
```

## Scenario Coverage Matrix

| Scenario / Example | portable | idiomatic | rusty | metal | Notes |
| --- | --- | --- | --- | --- | --- |
| `examples/chat_loopback` | Yes | Yes | Yes | Yes | Flagship comparison app (interactive neon TUI + network loopback + profile runtimes + Haxe-authored Rust tests). |
| `examples/profile_storyboard` | Yes | Yes | Yes | Yes | Compact profile-style reference app (typed board domain, four runtime idioms, Haxe-authored Rust tests with `@:rustTest` metadata forms). |
| `examples/hello` | No | Yes | No | Yes | Minimal sanity check; includes dedicated metal variant. |
| `examples/bytes_ops` | No | Yes | Yes | No | Bytes APIs + Haxe-authored Rust tests (`@:rustTest`) for runtime behavior. |
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
  - `examples/profile_storyboard` (`profile/PortableRuntime.hx`)
  - `examples/chat_loopback` (`PortableRuntime`)
  - `examples/sys_*` and thread smokes
- Bridge (`idiomatic`):
  - `examples/profile_storyboard` (`profile/IdiomaticRuntime.hx`)
  - `examples/chat_loopback` (`IdiomaticRuntime`)
  - `examples/bytes_ops`, `examples/serde_json`
- Rust-first (`rusty`):
  - `examples/profile_storyboard` (`profile/RustyRuntime.hx`)
  - `examples/chat_loopback` (`RustyRuntime`)
  - `examples/async_retry_pipeline`
- Rust-first+ (`metal`):
  - `examples/profile_storyboard` (`profile/MetalRuntime.hx`)
  - `examples/chat_loopback` (`MetalRuntime` with `rust.metal.Code.expr/stmt`)
  - `examples/hello` metal compile variants for minimal smoke

## Test Authoring

- `examples/bytes_ops`, `examples/chat_loopback`, `examples/profile_storyboard`, and `examples/tui_todo` use Haxe-authored Rust tests (`@:rustTest`) instead of `native/*.rs`.
- See `docs/haxe-rust-tests.md` for the metadata contract and generated wrapper behavior.
