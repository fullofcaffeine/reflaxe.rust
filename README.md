<p align="center">
  <img src="assets/haxe.rust-logo.png" alt="reflaxe.rust logo" width="360" />
</p>

# reflaxe.rust

[![Version](https://img.shields.io/badge/version-0.63.1-blue)](https://github.com/fullofcaffeine/reflaxe.rust/releases)
[![CI](https://github.com/fullofcaffeine/reflaxe.rust/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/reflaxe.rust/actions/workflows/ci.yml)

Haxe 4.3.7 -> Rust target built on Reflaxe.

This project lets you write Haxe and ship native Rust binaries, with a path for both Haxe-first and Rust-first teams.

Current posture:

- architecture and contract model: strong
- validated implementation baseline: broad and evidence-backed
- public release posture: stable `1.x`, with explicit documented caveats and proof-depth limits (`docs/semver-release-posture.md`)

Production shorthand: use it for controlled production on validated lanes, not as a blanket promise
that every arbitrary Haxe/std/sys edge behaves identically on every platform. If your app touches
networking, TLS, DB, processes, or threading, add app-specific smoke tests around those paths.

## Why reflaxe.rust

- `portable` contract (default): Haxe-first semantics with portability-oriented behavior and predictable stdlib/runtime integration.
- `metal` contract: Rust-first boundary rules, typed interop surfaces, and performance-focused paths.
- Portable abstractions do not have to mean wrapper tax: when semantics line up, shared portable
  surfaces can lower directly to native Rust representations (for example
  `reflaxe.std.Option/Result` -> Rust `Option/Result`).
- `reflaxe.std` is the start of a broader portable idiom layer, not a Rust-only wrapper module.
  V1 is intentionally narrow (`Option` / `Result`) so semantics and migration stay stable before
  the portable API surface grows.
- Portable lowering can still target native Rust representations when semantics match, but that is
  an implementation win inside the `portable` contract, not a silent switch into native-lane code.
  See [Portable near-native guidance](docs/portable-near-native-guidance.md).
- CI evidence: snapshots, negative policy fixtures, runtime/optimizer plan reports, and HXRT overhead tracking are all part of the default workflow.

## Start Here

- New here: [Start Here guide](docs/start-here.md)
- Evaluating production use: [Production Readiness guide](docs/production-readiness.md), then [feature support matrix](docs/feature-support-matrix.md)
- Portable-first path: [Profiles](docs/profiles.md), [Portable near-native guidance](docs/portable-near-native-guidance.md), [Examples Matrix](docs/examples-matrix.md)
- Metal-first path: [Metal profile](docs/metal-profile.md), [Portable near-native guidance](docs/portable-near-native-guidance.md), [profile_storyboard / metal examples](docs/examples-matrix.md)
- Release / operations path: [Production Readiness guide](docs/production-readiness.md), [Semver and release posture](docs/semver-release-posture.md), [Weekly CI Evidence runbook](docs/weekly-ci-evidence.md)
- Tooling / workflow: [Dev Watcher guide](docs/dev-watcher.md), [Async/Await guide](docs/async-await.md), [Documentation Index](docs/index.md)

## Scaffold A New Project (Generator)

Generate a ready-to-run Haxe.rust project:

```bash
npm run dev:new-project -- ./my_haxe_rust_app
cd my_haxe_rust_app
cargo hx --action run
```

The generated project includes the full task plumbing:

- `cargo hx --action run` (compile Haxe->Rust, then run)
- `cargo hx --action test` (compile Haxe->Rust, then test)
- `cargo hx --action build --release` (production build)
- `bash scripts/dev/watch-haxe-rust.sh --hxml compile.hxml` (watch loop)
- `bash scripts/dev/check-guards.sh` (local-path + security wiring checks; gitleaks scan when installed)
- `bash scripts/install-git-hooks.sh` (installs pre-commit local-path + staged gitleaks checks)

Use this scaffold when you want the recommended app layout and local task driver. If you are
installing into an existing app instead, start from [Install via lix](docs/install-via-lix.md).
For the full generated-app loop, see [Workflow](docs/workflow.md#new-project-scaffold--task-hxmls).

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

4. Run the full CI-style local harness:

```bash
npm run test:all
```

GitHub Actions shards this same harness into parallel jobs for wall-clock speed, but the local
command remains the single full-suite entrypoint.

After the first successful run, the recommended next step is a generated starter app:

```bash
npm run dev:new-project -- ./my_haxe_rust_app
cd my_haxe_rust_app
cargo hx --action run
cargo hx --action test
```

That path exercises the same project-local workflow users should keep in application repos.

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

Use `-D reflaxe_rust_profile=portable|metal`.

| Profile | Best for | What you get |
| --- | --- | --- |
| `portable` (default) | Haxe-first teams | Stable Haxe semantics and portability-first behavior |
| `metal` | Rust-aware teams and performance-critical paths | Rust-first APIs, stricter app-side injection boundaries, and primary near-pure-Rust hot-path performance objective |

Rule of thumb:

- Start in `portable`.
- Add `metal` only where the app needs Rust-first APIs, stricter boundaries, or measured hot-path work.
- Use `reflaxe.std` portable idioms when they express the right semantics; on Rust, `Option` and
  `Result` lower to native Rust representations when the contract lines up.

Read more: [Profiles guide](docs/profiles.md), [Rusty migration guide](docs/rusty-profile.md),
[Metal profile details](docs/metal-profile.md), [HXRT overhead benchmarks](docs/perf-hxrt-overhead.md), and [Lifetime encoding design](docs/lifetime-encoding.md).

## Examples

- [chat_loopback](examples/chat_loopback) (cross-profile flagship: portable/metal)
- [profile_storyboard](examples/profile_storyboard) (cross-profile micro-app focused on profile-specific coding style + `@:rustTest`)
- [metal_first_dataflow](examples/metal_first_dataflow) (dedicated metal-style reference: `Result`/`Option`/`Vec` with strict-boundary-safe app code)
- [hello](examples/hello) (portable sanity check)
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
- Scaffold a new starter project: `npm run dev:new-project -- ./my_haxe_rust_app`
- Refresh tracker-backed status docs: `npm run docs:sync:progress`
- Verify tracker-backed status docs are in sync: `npm run docs:check:progress`
- Snapshot tests: `bash test/run-snapshots.sh`
- Upstream stdlib sweep: `bash test/run-upstream-stdlib-sweep.sh`
- Template task-matrix smoke: `bash scripts/ci/template-smoke.sh`
- Windows-safe smoke subset: `bash scripts/ci/windows-smoke.sh`
- HXRT overhead benchmark + soft-budget warnings: `bash scripts/ci/perf-hxrt-overhead.sh`
- Full local CI equivalent: `bash scripts/ci/local.sh`
- Clean generated artifacts: `npm run clean:artifacts:all`

## Status and Readiness

- Current release posture: [Semver and release posture](docs/semver-release-posture.md)
- Production rollout guidance: [Production Readiness](docs/production-readiness.md)
- Current readiness tracker: [Compiler Progress Tracker](docs/progress-tracker.md)
- Ongoing validation cadence: [Weekly CI Evidence](docs/weekly-ci-evidence.md)
- Technical support matrix: [feature support matrix](docs/feature-support-matrix.md)
- Sys regression intake: [Cross-Platform Watchlist](docs/sys-regression-watchlist.md)

Historical closeout records:

- [GA decision record](docs/ga-decision-record.md)
- [GA caveat classification](docs/ga-caveat-classification.md)
- [Road to 1.0](docs/road-to-1.0.md)

## Defines (Common)

- `-D rust_output=out` - output directory for the generated Cargo project
- `-D rust_no_build` / `-D rust_codegen_only` - codegen only, skip Cargo build
- `-D rust_build_release` / `-D rust_release` - release build mode
- `-D rust_target=<triple>` - pass target triple to Cargo
- `-D reflaxe_rust_profile=portable|metal` - select profile contract
- `-D rust_async` - enable Rust-first async/await support (`docs/async-await.md`)
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
