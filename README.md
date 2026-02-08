# reflaxe.rust

[![Version](https://img.shields.io/badge/version-0.39.0-blue)](https://github.com/fullofcaffeine/reflaxe.rust/releases)

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

- Milestones live in Beads (`bd graph haxe.rust-oo5 --compact`) and are summarized in `docs/milestones-oo5.md`.

Haxe (4.3.7) → Rust target built on Reflaxe.

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

- `-D rust_output=out` — output directory (Cargo project is generated under this folder).
- `-D rust_crate=<name>` — Cargo crate name.
- `-D rust_no_gitignore` — opt-out of emitting a minimal Cargo-style `.gitignore` in the generated crate.
- `-D rust_idiomatic` (or `-D reflaxe_rust_profile=idiomatic`) — enable more idiomatic Rust output (e.g. `let` vs `let mut` inference).
- `-D reflaxe_rust_profile=rusty` — enable the “rusty” profile (Rust-facing APIs under `rust.*`).
- `-D rust_cargo_deps_file=<path>` — TOML lines appended under `[dependencies]` in generated `Cargo.toml` (fallback; prefer `@:rustCargo`).
- `-D rust_cargo_toml=<path>` — override the entire generated `Cargo.toml` (supports `{{crate_name}}` placeholder).
- `-D rust_extra_src=<dir>` — copy `*.rs` files from a directory into `out/src/` and auto-`mod` them from `main.rs`.
- `-D rustfmt` — run `cargo fmt` on the generated crate after compilation (best-effort).

## Rust-native interop (framework-first)

- Cargo deps: `@:rustCargo("dep = \"1\"")` or `@:rustCargo({ name: "dep", version: "1", features: ["x"] })`
- Extern bindings: `@:native("crate::path") extern class Foo { @:native("fn_name") static function bar(...): ...; }`
- Derives: `@:rustDerive(["serde::Serialize"])` on classes/enums
- Generic bounds (minimal): `@:rustGeneric("T: serde::Serialize")` on methods with type params

See `docs/rusty-profile.md` for the `rusty` profile design and `rust.*` APIs.

See `docs/workflow.md` for the full Haxe→Rust→Cargo workflow (defines, release builds, targets).

See `docs/release.md` for how releases (semver + changelog + GitHub artifacts) are produced.

See `docs/function-values.md` for callback/function-value lowering notes (baseline + constraints).
