# Workflow (Haxe -> Rust -> native)

`reflaxe.rust` generates a Cargo crate under `-D rust_output=...`.

By default it then runs Cargo (debug build). You can opt out to generate Rust only.

## Default build behavior

- Default: `cargo build` after codegen
- Opt-out (codegen only): `-D rust_no_build` (alias: `-D rust_codegen_only`)
- Release: `-D rust_build_release` (alias: `-D rust_release`)
- Optional rustfmt: `-D rustfmt` (best-effort `cargo fmt` after output generation)

## Fast local loop (watch mode)

Use the watcher when you want fast feedback while editing:

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml
```

Common variants:

- Compile + run on change (default): `--mode run`
- Compile + test on change: `--mode test`
- Compile only on change: `--mode build`
- One cycle without watcher: `--once`

Full guide: [Dev Watcher](dev-watcher.md).

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

## Recommended project workflow

- Keep `Cargo.lock` committed in your project (and use `-D rust_cargo_locked` in CI) for reproducibility.
- Prefer declaring Rust deps via Haxe metadata (framework-first):
  - `@:rustCargo({ name: "dep", version: "1.2", features: ["x"] })`
  - avoid requiring users to pass `-D rust_cargo_deps_file=...`

## Repo CI parity (contributors)

Before pushing to `main`, run the closest local equivalent of CI:

- `bash scripts/ci/local.sh`
