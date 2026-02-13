# reflaxe.rust

[![Version](https://img.shields.io/badge/version-0.53.0-blue)](https://github.com/fullofcaffeine/reflaxe.rust/releases)

Haxe (4.3.7) -> Rust target built on Reflaxe.

## Start Here (1.0 docs and quickstart)

- Plain-language onboarding: `docs/start-here.md`
- Production rollout guidance: `docs/production-readiness.md`
- 1.0 execution playbook: `docs/road-to-1.0.md`
- 1.0 gate closeout template: `docs/release-gate-closeout.md`
- Live 1.0 tracker (Beads-backed): `docs/progress-tracker.md`
- Vision vs implementation reality check: `docs/vision-vs-implementation.md`
- Profile model (portable/idiomatic/rusty): `docs/profiles.md`
- Defines reference: `docs/defines-reference.md`
- Full docs map: `docs/index.md`
- Technical support matrix: `docs/v1.md`

Keep tracker status synchronized from Beads:

```bash
npm run docs:sync:progress
```

Check for tracker drift (non-zero exit if stale):

```bash
npm run docs:check:progress
```

## Build a native binary

After codegen (`-D rust_output=...`) the compiler invokes Cargo by default (debug build).

- Opt-out (codegen only): add `-D rust_no_build` (alias: `-D rust_codegen_only`)
- Release: add `-D rust_build_release` (alias: `-D rust_release`)
- Cross target: add `-D rust_target=<triple>` (passed to `cargo build --target <triple>`)
- Tooling knobs:
  - `-D rust_cargo_subcommand=build|check|test|clippy|run` (default: `build`)
  - `-D rust_cargo_features=feat1,feat2`
  - `-D rust_cargo_no_default_features`, `-D rust_cargo_all_features`
  - `-D rust_cargo_locked`, `-D rust_cargo_offline`, `-D rust_cargo_quiet`
  - `-D rust_cargo_jobs=8`
  - `-D rust_cargo_target_dir=path/to/target` (sets `CARGO_TARGET_DIR`)

## Roadmap

- Core milestone roadmap (historical compiler build-out): `bd graph haxe.rust-oo3 --compact`
- Production 1.0 parity gate (active): `bd graph haxe.rust-4jb --compact`
- Human-readable readiness tracker: `docs/progress-tracker.md`

## Install (lix, GitHub-only)

See `docs/install-via-lix.md`.

## Quickstart

This repo is developed with **lix** (pinned Haxe toolchain):

```bash
npm install
```

Run snapshot tests:

```bash
npm test
# or: bash test/run-snapshots.sh
```

Run host smoke snapshots without golden diffs (useful on non-Linux hosts):

```bash
SNAP_CARGO_QUIET=0 bash test/run-snapshots.sh --case hello_trace --no-diff
```

Run the Windows-safe smoke subset locally:

```bash
bash scripts/ci/windows-smoke.sh
```

Run full local harness (snapshots + examples + CI-like checks):

```bash
npm run test:all
```

Optional (haxelib dev, if you prefer):

```bash
haxelib dev reflaxe.rust .
```

## Examples

Hello world:

```bash
cd examples/hello
../node_modules/.bin/haxe compile.hxml
(cd out && cargo run -q)
```

Todo TUI demo (ratatui, headless backend):

```bash
cd examples/tui_todo
../node_modules/.bin/haxe compile.hxml
(cd out && cargo run -q)
```

Serde JSON demo (declares Cargo deps via `@:rustCargo`, derives via `@:rustDerive`):

```bash
cd examples/serde_json
../node_modules/.bin/haxe compile.hxml
(cd out && cargo run -q)
```

## Useful defines

- `-D rust_output=out` - output directory (Cargo project is generated under this folder).
- `-D rust_crate=<name>` - Cargo crate name.
- `-D rust_no_gitignore` - opt-out of emitting a minimal Cargo-style `.gitignore` in the generated crate.
- `-D rust_idiomatic` (or `-D reflaxe_rust_profile=idiomatic`) - enable more idiomatic Rust output (for example `let` vs `let mut` inference).
- `-D reflaxe_rust_profile=rusty` - enable Rust-first profile surfaces under `rust.*`.
- `-D rust_cargo_deps_file=<path>` - TOML lines appended under `[dependencies]` in generated `Cargo.toml` (fallback; prefer `@:rustCargo`).
- `-D rust_cargo_toml=<path>` - override the entire generated `Cargo.toml` (supports `{{crate_name}}` placeholder).
- `-D rust_extra_src=<dir>` - copy `*.rs` files from a directory into `out/src/` and auto-`mod` them from `main.rs`.
- `-D rustfmt` - run `cargo fmt` on the generated crate after compilation (best-effort).

See `docs/defines-reference.md` for the full reference.

## Rust-native interop (framework-first)

- Cargo deps: `@:rustCargo("dep = \"1\"")` or `@:rustCargo({ name: "dep", version: "1", features: ["x"] })`
- Extern bindings: `@:native("crate::path") extern class Foo { @:native("fn_name") static function bar(...): ...; }`
- Derives: `@:rustDerive(["serde::Serialize"])` on classes/enums
- Generic bounds (minimal): `@:rustGeneric("T: serde::Serialize")` on methods with type params

See `docs/rusty-profile.md` for the Rust-first profile design and `rust.*` APIs.

See `docs/workflow.md` for the full Haxe->Rust->Cargo workflow (defines, release builds, targets).

See `docs/release.md` for how releases (semver + changelog + GitHub artifacts) are produced.

See `docs/function-values.md` for callback/function-value lowering notes (baseline + constraints).
