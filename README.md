<p align="center">
  <img src="assets/haxe.rust-logo.png" alt="reflaxe.rust logo" width="360" />
</p>

# reflaxe.rust

[![Version](https://img.shields.io/badge/version-0.56.0-blue)](https://github.com/fullofcaffeine/reflaxe.rust/releases)
[![CI](https://github.com/fullofcaffeine/reflaxe.rust/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/reflaxe.rust/actions/workflows/ci.yml)

Haxe 4.3.7 -> Rust target built on Reflaxe.

This project lets you write Haxe and ship native Rust binaries, with a path for both Haxe-first and Rust-first teams.

## Start Here

- New here: [Start Here guide](docs/start-here.md)
- Building async apps: [Async/Await preview guide](docs/async-await.md)
- Production rollout: [Production Readiness guide](docs/production-readiness.md)
- Post-1.0 quality cadence: [Weekly CI Evidence runbook](docs/weekly-ci-evidence.md)
- Cross-platform sys risk tracking: [Sys Regression Watchlist](docs/sys-regression-watchlist.md)
- Fast edit-compile-run loop: [Dev Watcher guide](docs/dev-watcher.md)
- Full docs map: [Documentation Index](docs/index.md)
- Profile/scenario examples map: [Examples Matrix](docs/examples-matrix.md)

## Quick Start (First Successful Run)

1. Install dependencies (toolchain is pinned via lix):

```bash
npm install
```

2. Compile and run the hello example:

```bash
cd examples/hello
npx haxe compile.hxml
(cd out && cargo run -q)
```

3. Run snapshot tests:

```bash
npm test
```

4. Run the CI-style local harness (snapshots + examples):

```bash
npm run test:all
```

## Fast Dev Loop (Watcher)

Install watcher engine once:

- Homebrew: [`brew install watchexec`](https://formulae.brew.sh/formula/watchexec)
- Cargo: [`cargo install watchexec-cli`](https://crates.io/crates/watchexec-cli)

Then run:

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml
```

Watch mode uses a session-owned Haxe compile server by default, so compiles are faster after warm-up.
Use `--no-haxe-server` if you want direct compile-only behavior.

More usage options: [Dev Watcher guide](docs/dev-watcher.md).

## Pick Your Profile

Use `-D reflaxe_rust_profile=portable|idiomatic|rusty|metal`.

| Profile | Best for | What you get |
| --- | --- | --- |
| `portable` (default) | Haxe-first teams | Stable Haxe semantics and portability-first behavior |
| `idiomatic` | Teams that want cleaner Rust output without semantic shifts | Same behavior as portable, cleaner emitted Rust |
| `rusty` | Rust-aware teams | Rust-first APIs and borrow/ownership-oriented surface |
| `metal` (experimental) | Rust-heavy teams that need typed low-level interop | Rusty+ profile with typed metal injection façade and stricter app-side injection boundaries |

Read more: [Profiles guide](docs/profiles.md), [Rusty profile details](docs/rusty-profile.md),
[Metal profile details](docs/metal-profile.md), and [Lifetime encoding design](docs/lifetime-encoding.md).

## Examples

- [chat_loopback](examples/chat_loopback) (cross-profile flagship: portable/idiomatic/rusty/metal)
- [hello](examples/hello)
- [async_retry_pipeline](examples/async_retry_pipeline)
- [classes](examples/classes)
- [serde_json](examples/serde_json)
- [sys_file_io](examples/sys_file_io)
- [sys_net_loopback](examples/sys_net_loopback)
- [sys_process](examples/sys_process)
- [sys_thread_smoke](examples/sys_thread_smoke)
- [thread_pool_smoke](examples/thread_pool_smoke)
- [tui_todo](examples/tui_todo)

Coverage map: [docs/examples-matrix.md](docs/examples-matrix.md).

## Most Useful Commands

- Watch mode for local development: `npm run dev:watch -- --hxml examples/hello/compile.hxml`
- Refresh tracker-backed status docs: `npm run docs:sync:progress`
- Verify tracker-backed status docs are in sync: `npm run docs:check:progress`
- Snapshot tests: `bash test/run-snapshots.sh`
- Upstream stdlib sweep: `bash test/run-upstream-stdlib-sweep.sh`
- Windows-safe smoke subset: `bash scripts/ci/windows-smoke.sh`
- Full local CI equivalent: `bash scripts/ci/local.sh`
- Clean generated artifacts: `npm run clean:artifacts:all`

## 1.0 Status and Roadmap

- Live tracker: [Compiler Progress Tracker](docs/progress-tracker.md)
- Vision vs implementation: [Reality check](docs/vision-vs-implementation.md)
- Execution playbook: [Road to 1.0](docs/road-to-1.0.md)
- Weekly post-1.0 operations: [Weekly CI Evidence](docs/weekly-ci-evidence.md)
- Sys regression intake: [Cross-Platform Watchlist](docs/sys-regression-watchlist.md)
- Technical support matrix: [v1 scope](docs/v1.md)

## Defines (Common)

- `-D rust_output=out` - output directory for the generated Cargo project
- `-D rust_no_build` / `-D rust_codegen_only` - codegen only, skip Cargo build
- `-D rust_build_release` / `-D rust_release` - release build mode
- `-D rust_target=<triple>` - pass target triple to Cargo
- `-D rust_idiomatic` - alias for `-D reflaxe_rust_profile=idiomatic`
- `-D rust_metal` - alias for `-D reflaxe_rust_profile=metal`
- `-D reflaxe_rust_profile=rusty|metal` - enable Rust-first profile surfaces
- `-D rust_async_preview` - enable Rust-first async/await preview (`docs/async-await.md`)
- `-D rustfmt` - run `cargo fmt` on generated output (best effort)

Full list: [Defines reference](docs/defines-reference.md).

## Rust Interop

Preferred order:

1. Pure Haxe + runtime/std APIs
2. Typed externs and metadata (`@:native`, `@:rustCargo`, `@:rustExtraSrc`)
3. Framework wrappers around hand-written Rust modules
4. Raw `__rust__` only when necessary

Read: [Interop guide](docs/interop.md) and [Workflow guide](docs/workflow.md).

## Installation and Release Docs

- Toolchain install details: [Install via lix](docs/install-via-lix.md)
- Release process: [Release docs](docs/release.md)
