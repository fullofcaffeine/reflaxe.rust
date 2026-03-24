# Examples Matrix (portable + metal)

This page is the product-tour view of the example set.

Use it to answer:

- which example should I start with,
- which profile does it demonstrate,
- and what question does it help me answer?

Interpretation rule:

- example coverage is useful product evidence and onboarding material,
- it is not, by itself, blanket semantic-closure proof for an entire stdlib or platform family,
- for release-truth posture, pair this page with `docs/semver-release-posture.md` and
  `docs/semantic-confidence-summary.md`.

## Start here by question

### "I just want the first successful portable run"

Start with `examples/hello`.

Why:

- smallest possible portable sanity check,
- shows the basic Haxe -> Rust -> Cargo loop,
- best first stop before larger examples.

Run:

```bash
cd examples/hello
npx haxe compile.hxml
(cd out && cargo run -q)
```

Read next:

- [Start Here](start-here.md)
- [Profiles](profiles.md)

### "Show me portable vs metal on the same app"

Start with `examples/chat_loopback`.

Why:

- flagship side-by-side reference app,
- same scenario under both contracts,
- good answer to "what changes when I switch profiles?"

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

Read next:

- [Portable near-native guidance](portable-near-native-guidance.md)
- [Profiles](profiles.md)
- [Metal profile](metal-profile.md)

### "Show me the fastest portable-vs-metal authoring/codegen comparison"

Start with `examples/profile_storyboard`.

Why:

- fastest side-by-side authoring comparison,
- compact enough to inspect generated Rust directly,
- includes a native baseline comparison script.

Run:

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

Read next:

- [Portable near-native guidance](portable-near-native-guidance.md)
- [HXRT overhead benchmarks](perf-hxrt-overhead.md)

### "Show me the metal-first coding style"

Start with `examples/metal_first_dataflow`.

Why:

- dedicated metal-style reference,
- uses `Result` / `Option` / `Vec` in a Rust-first source style,
- shows what metal demonstrates that the portable examples intentionally do not: explicit native
  lane authoring without pretending it is still portable.

Run:

```bash
cd examples/metal_first_dataflow
npx haxe compile.hxml
(cd out && cargo run -q)
```

Read next:

- [Metal profile](metal-profile.md)
- [Portable near-native guidance](portable-near-native-guidance.md)

### "I need examples for specific subsystems"

Use these:

- bytes and tests: `examples/bytes_ops`
- typed JSON interop: `examples/serde_json`
- async / retry: `examples/async_retry_pipeline`
- deterministic TUI harness: `examples/tui_todo`
- file APIs: `examples/sys_file_io`
- sockets: `examples/sys_net_loopback`
- process spawning: `examples/sys_process`
- threads: `examples/sys_thread_smoke`
- fixed thread pool: `examples/thread_pool_smoke`

### "I need the concurrency evidence path"

Use these in order:

1. `examples/sys_thread_smoke`
   - proves the core portable thread contract:
     - OS-thread creation
     - re-entrant `Mutex`
     - main-thread message delivery
2. `examples/thread_pool_smoke`
   - proves the portable fixed-thread-pool helper path:
     - queued jobs
     - shared-state coordination
     - deterministic completion/shutdown
3. `test/snapshot/sys_thread_elastic_thread_pool_smoke`
   - proves the elastic thread-pool helper really compiles and runs on the Rust target
4. `test/snapshot/sys_thread_deque_basic`
   - proves `Deque` ordering, blocking wakeup, and empty-pop behavior
5. `test/snapshot/sys_thread_event_loop`
   - proves direct `sys.thread.EventLoop` behavior on the Rust target
6. `test/snapshot/sys_thread_event_loop_repeat_cancel`
   - proves self-cancelling repeating callback behavior for `EventLoop.repeat(...)/cancel(...)`
7. `test/snapshot/haxe_mainloop_entrypoint_basic`
   - proves the basic `haxe.MainLoop.add(...)` + `haxe.EntryPoint.run()` scheduling path
8. `test/snapshot/haxe_mainloop_entrypoint_thread_bridge`
   - proves the thread-bridge scheduler path:
     - `haxe.MainLoop.addThread(...)`
     - `haxe.MainLoop.runInMainThread(...)`
     - `haxe.EntryPoint.run()` wakeup/exit behavior

Interpretation rule:

- the examples answer "does this target-side path work end to end?"
- the snapshots answer "what Rust shape and deterministic behavior do we lock for regression?"
- none of these, by themselves, imply blanket `--interp` parity for all scheduler semantics

## Profile style anchors

Portable-first style:

- `examples/profile_storyboard/profile/PortableRuntime.hx`
- `examples/chat_loopback/profile/PortableRuntime.hx`

Metal Rust-first style:

- `examples/metal_first_dataflow/Harness.hx`
- `examples/profile_storyboard/profile/MetalRuntime.hx`
- `examples/chat_loopback/profile/MetalRuntime.hx`

## Scenario matrix

| Scenario / Example | portable | metal | Best answer to | Notes |
| --- | --- | --- | --- | --- |
| `examples/chat_loopback` | Yes | Yes | "What changes when I switch profiles?" | Flagship comparison app with interactive TUI, network loopback, and Haxe-authored Rust tests. |
| `examples/profile_storyboard` | Yes | Yes | "Show me the clearest portable-vs-metal codegen comparison." | Best compact side-by-side profile reference; includes native comparison script. |
| `examples/metal_first_dataflow` | No | Yes | "What does metal-first source actually look like?" | Dedicated metal-style reference (`Result`/`Option`/`Vec`, strict-boundary-safe app code). |
| `examples/hello` | Yes | No | "Can I get a first successful run quickly?" | Minimal portable sanity check. |
| `examples/bytes_ops` | Yes | No | "How do Haxe-authored Rust tests look?" | Bytes APIs + `@:rustTest`. |
| `examples/serde_json` | Yes | No | "How do I use typed JSON surfaces?" | Typed Serde JSON surfaces under the portable contract. |
| `examples/async_retry_pipeline` | No | Yes | "What is the canonical Rust-first async entry pattern?" | Sync `main` -> `Async.blockOn(...)` -> async helper under `rust_async`. |
| `examples/tui_todo` | Yes | No | "How do I test a larger TUI app deterministically?" | Large portable app with deterministic TUI harness tests. |
| `examples/sys_file_io` | Yes | No | "What do sys file APIs look like?" | File APIs / stat / rename checks. |
| `examples/sys_net_loopback` | Yes | No | "How do socket APIs behave?" | Focused socket API smoke test. |
| `examples/sys_process` | Yes | No | "How do I spawn processes and read output?" | Process spawning + I/O checks. |
| `examples/sys_thread_smoke` | Yes | No | "What do basic threads look like?" | Core thread-contract smoke: worker creation, re-entrant `Mutex`, and main-thread message delivery. |
| `examples/thread_pool_smoke` | Yes | No | "What does the fixed thread pool API look like?" | Fixed-thread-pool smoke: queued jobs, shared counter coordination, deterministic completion/shutdown. |
| `test/snapshot/haxe_mainloop_entrypoint_thread_bridge` | No | Yes | "Does the MainLoop thread bridge really work on this target?" | Scheduler bridge proof for `addThread(...)`, `runInMainThread(...)`, and `EntryPoint.run()` wakeup/exit behavior. |

## Performance parity workflow

For portable vs metal vs pure-Rust baseline tracking:

```bash
bash scripts/ci/perf-hxrt-overhead.sh --gate-mode soft
```

Artifacts:

- `.cache/perf-hxrt/results/comparison.json`
- `.cache/perf-hxrt/results/summary.md`

## Test authoring

- `examples/bytes_ops`, `examples/chat_loopback`, `examples/metal_first_dataflow`,
  `examples/profile_storyboard`, and `examples/tui_todo` use Haxe-authored Rust tests
  (`@:rustTest`).
- See `docs/haxe-rust-tests.md` for metadata and generated wrapper behavior.
