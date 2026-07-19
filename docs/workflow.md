# Workflow (Haxe -> Rust -> native)

`reflaxe.rust` generates a Cargo crate under `-D rust_output=...`.

By default it then runs Cargo (debug build). You can opt out to generate Rust only.

## Default build behavior

- Default: `cargo build` after codegen
- Opt-out (codegen only): `-D rust_no_build` (alias: `-D rust_codegen_only`)
- Release: `-D rust_build_release` (alias: `-D rust_release`)
- Optional rustfmt: `-D rustfmt` (best-effort `cargo fmt` after output generation)

Configured Cargo build/check/test failures are Haxe compilation failures. Use `-D rust_no_build`
only when a wrapper script or external task runner will invoke Cargo itself.

## Fast local loop (watch mode)

Use the watcher when you want fast feedback while editing:

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml
```

By default, watch mode uses a session-owned Haxe compile server (`--wait`/`--connect`) so incremental compiles are faster after warm-up.

Common variants:

- Compile + run on change (default): `--mode run`
- Compile + test on change: `--mode test`
- Compile only on change: `--mode build`
- One cycle without watcher: `--once`
- Disable compile server in watch mode: `--no-haxe-server`

Full guide: [Dev Watcher](dev-watcher.md).

Watcher mode semantics are normalized so task-style HXML defaults do not conflict:

- `--mode run|test`: Haxe compile is forced to codegen-only (`-D rust_no_build`) and watcher runs Cargo itself.
- `--mode build`: compile step is forced to `rust_cargo_subcommand=build` (never accidental `cargo run/test`).

## Cargo knobs (defines)

These map to Cargo arguments/env vars at the end of compilation:

- `-D rust_cargo_subcommand=build|check|test|clippy|run` (default: `build`)
- `-D rust_cargo_quiet` (adds `-q`)
- `-D rust_cargo_locked` (adds `--locked`)
- `-D rust_cargo_offline` (adds `--offline`)
- `-D rust_cargo_features=feat1,feat2` (adds `--features feat1,feat2`)
- `-D rust_cargo_no_default_features` (adds `--no-default-features`)
- `-D rust_cargo_all_features` (adds `--all-features`)
- `-D rust_cargo_jobs=8` (adds `-j 8`)
- `-D rust_target=<triple>` (adds `--target <triple>`)
- `-D rust_cargo_target_dir=path/to/target` (sets `CARGO_TARGET_DIR`)

If the configured Cargo command returns non-zero, the parent `haxe` process also exits non-zero.

## Cargo-First Project Driver

Use the cargo alias as a project-local task runner (instead of adding task-specific HXML variants):

```bash
cargo hx --project examples/chat_loopback --profile portable --action run
cargo hx --project examples/chat_loopback --profile portable --ci --action test
cargo hx --project examples/chat_loopback --profile metal --action build --release

# from inside examples/chat_loopback you can omit --project:
# cargo hx --profile portable --action run
```

## Recommended project workflow

- Use Rust `1.96.0` or newer. Default generated Cargo manifests declare this floor; see
  [Rust Toolchain Policy](rust-toolchain-policy.md) for the release pin and update cadence.
- Keep the generated application's `Cargo.lock` committed. The compiler preserves it across
  regeneration; use `-D rust_cargo_locked` in CI and release builds so dependency drift fails rather
  than silently rewriting the reviewed graph.
- Generated manifests use Cargo resolver 3 for MSRV-aware dependency selection. For an intentional
  dependency update, resolve with the supported minimum Rust, review the lock diff, rerun application
  checks/tests, and commit the new lock. Do not reuse compiler test-baseline locks in an application.
- Prefer declaring Rust deps via Haxe metadata (framework-first):
  - `@:rustCargo({ name: "dep", version: "1.2", features: ["x"] })`
  - avoid requiring users to pass `-D rust_cargo_deps_file=...`

## New project scaffold + task hxmls

Create a starter project from the built-in template:

```bash
npm run dev:new-project -- ./my_haxe_rust_app
cd my_haxe_rust_app
cargo hx --action run
```

Generated projects include this plumbing by default:

- `cargo hx ...` task driver (compile Haxe+Rust, then run/test/build/check/clippy).
- task HXML compatibility files (`compile*.hxml`).
- local watcher script (`scripts/dev/watch-haxe-rust.sh`) for edit-compile-run/test loops.
- local guard entrypoint (`scripts/dev/check-guards.sh`) for path/security checks (+ full gitleaks when installed).
- pre-commit hook installer (`scripts/install-git-hooks.sh`) plus generated hook (`scripts/hooks/pre-commit`) for staged checks.

Generated projects also include a local cargo alias:

```bash
cargo hx --action run
cargo hx --action test
cargo hx --action build --release
```

First-use checklist for app repos:

1. Run `cargo hx --action run` once to prove the Haxe -> Rust -> Cargo path.
2. Run `cargo hx --action test` once before adding app code.
3. Keep `portable` as the default profile until a path has a measured Rust-first or interop reason.
4. Add one app-level smoke test for each production-sensitive boundary you use: file/process,
   sockets or HTTP, TLS, DB setup, and thread/event-loop behavior.

Generated task files:

- `compile.build.hxml` -> debug compile only (`cargo build`)
- `compile.hxml` -> debug compile+run (`cargo run`) default
- `compile.run.hxml` -> explicit debug compile+run (`cargo run`)
- `compile.release.hxml` -> release compile only (`cargo build --release`)
- `compile.release.run.hxml` -> release compile+run (`cargo run --release`)

## Repo CI parity (contributors)

Before pushing to `main`, run the closest local equivalent of CI:

- `bash scripts/ci/local.sh`
- `bash scripts/ci/perf-hxrt-overhead.sh` (already included by `scripts/ci/local.sh`)

GitHub validates pushes to `main` and every pull request, including pull requests stacked on another
feature branch. An open feature branch is validated once in pull-request context instead of running
the same expensive suite for both its push and its pull request. Use manual workflow dispatch when a
branch without a pull request needs remote validation.

Each GitHub run shards the expensive harness work into parallel jobs for speed, then keeps
`Snapshots + Examples` as an aggregate required check. Local runs stay intentionally boring:
`npm run test:all` is still the full harness, and `HARNESS_STAGES=... bash scripts/ci/harness.sh` is
only for focused shard debugging.

When several Haxe-family compiler repositories are validating on the same machine, use the opt-in
queued form to avoid running their heavyweight suites at the same time:

```bash
npm run test:all:queued
```

This runs the unchanged `npm run test:all` command after acquiring the shared
`haxe-family.heavy-run-lease.v1` lease. The wait is bounded to 15 minutes and exits with status 75
if capacity does not become available. CI bypasses the lease, ordinary `npm run test:all` remains
unchanged, and stale owners are recovered without signalling another process. Override the common
lease location only for an isolated test with `HAXE_FAMILY_HEAVY_RUN_LEASE_FILE`; Haxe-family
repositories coordinate through the same user-scoped default path.

## HXRT overhead tracking

To track runtime footprint regressions explicitly:

- compare mode: `bash scripts/ci/perf-hxrt-overhead.sh`
- baseline update: `bash scripts/ci/perf-hxrt-overhead.sh --update-baseline`

See [HXRT overhead benchmarks](perf-hxrt-overhead.md) for methodology and warning policy.
