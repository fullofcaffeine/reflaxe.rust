# Defines Reference (`-D ...`)

This page is a practical reference for the most relevant compiler defines.

## Core output and build

- `rust_output=<dir>`
  - Required for Rust generation. Also acts as the stable signal that Rust target compilation is active.
- `rust_crate=<name>`
  - Override generated Cargo crate name.
- `rust_no_build` or `rust_codegen_only`
  - Generate Rust only; skip Cargo invocation.
- `rust_build_release` or `rust_release`
  - Use release build mode (`cargo build --release`).
- `rust_target=<triple>`
  - Pass Cargo target triple.
- `rust_no_gitignore`
  - Do not emit generated crate `.gitignore`.
- `rustfmt`
  - Run `cargo fmt` after code generation (best effort).
- `rust_deny_warnings`
  - Emit crate-level deny warnings for generated Rust.

## Profiles and semantics

- `reflaxe_rust_profile=portable|idiomatic|rusty|metal`
  - Main profile switch.
- `rust_idiomatic`
  - Alias for `reflaxe_rust_profile=idiomatic`.
- `rust_metal`
  - Alias for `reflaxe_rust_profile=metal`.
- `rust_async_preview`
  - Enable async/await preview surfaces (`rust.async.Future`, `rust.async.Async.*`).
  - Requires a Rust-first profile: `reflaxe_rust_profile=rusty|metal`.
- `rust_string_nullable`
  - Force nullable string representation.
- `rust_string_non_nullable`
  - Force legacy non-null Rust `String` representation.
- `rust_emit_upstream_std`
  - Emit upstream Haxe std modules when referenced.
- `rust_warn_unresolved_monomorph_std`
  - Re-enable unresolved monomorph warnings for framework/upstream std internals.
- `rust_debug_string_types`
  - Debug define for string type diagnostics.

## Cargo command controls

- `rust_cargo_subcommand=build|check|test|clippy|run`
- `rust_cargo_cmd=<binary>`
- `rust_cargo_target_dir=<path>`
- `rust_cargo_features=feat1,feat2`
- `rust_cargo_no_default_features`
- `rust_cargo_all_features`
- `rust_cargo_jobs=<n>`
- `rust_cargo_locked`
- `rust_cargo_offline`
- `rust_cargo_quiet`
- `rust_cargo_toml=<path>`
  - Override full generated `Cargo.toml` template.
- `rust_cargo_deps_file=<path>`
  - Append dependency lines under `[dependencies]` from file.
- `rust_cargo_deps=<toml-lines>`
  - Inline dependency lines fallback.

## Interop and extra sources

- `rust_extra_src=<dir>`
  - Copy `.rs` modules into generated crate `src/` and auto-include them.

## Strictness and boundary enforcement

- `reflaxe_rust_strict`
  - Enforce strict no-injection policy for user project code.
- `reflaxe_rust_strict_examples`
  - Enforce strict policy in repo examples/snapshot paths.

## Notes on defaults

- If no string mode define is provided:
  - portable and idiomatic default to `rust_string_nullable`.
  - rusty and metal default to non-null string mode.
- `target.name` is read internally by compiler macros; users typically do not set it directly.

## Related docs

- `docs/profiles.md`
- `docs/metal-profile.md`
- `docs/async-await.md`
- `docs/workflow.md`
- `docs/interop.md`
- `docs/v1.md`
