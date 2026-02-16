# Haxelib Packaging Notes

This repo packages release zips with `scripts/release/package-haxelib.sh`.

## Goals

- Keep packaging behavior aligned with Reflaxe `build` conventions.
- Preserve runtime/compiler assets required by this target (`runtime/`, `vendor/`).
- Avoid std override leakage into non-target contexts.

## Packaging model

- Read `classPath` and `reflaxe.stdPaths` from `haxelib.json`.
- Copy `classPath` into the package.
- Merge each `stdPath` into the packaged `classPath` (flattened layout).
- Copy release files (`LICENSE`, `README.md`, `extraParams.hxml`, optional `Run.hx`/`run.n`).
- Copy and sanitize `haxelib.json` (remove `reflaxe` metadata in the shipped artifact).

## Why `.cross.hx` for std overrides

Upstream-colliding std overrides in `std/` are stored as `.cross.hx` to force target-conditional
selection and avoid accidental use in eval/macro/non-target contexts.

In packaged zips, those files are merged under `src/**` but keep the `.cross.hx` suffix.

## Validation workflow

Use `bash scripts/ci/package-smoke.sh` to validate the shipped artifact end-to-end:

- Build the zip with `scripts/release/package-haxelib.sh`.
- Verify package layout + metadata invariants (`src/` flattening, sanitized `haxelib.json`, pruned runtime artifacts).
- Create an isolated local haxelib repo (`haxelib newrepo`) and install the zip.
- Compile a minimal app with `-lib reflaxe.rust` and confirm std override modules are emitted.
- Build the generated Rust crate with `cargo build`.

Important: validate packaged behavior through `haxelib install` + `-lib reflaxe.rust`, not raw `-cp <pkg>/src`.
Raw classpath-only tests are not equivalent for `.cross.hx` std override selection.

## Backend-specific requirement

The compiler resolves runtime assets relative to library root (`runtime/hxrt`) and bootstrap classpaths
for vendored Reflaxe (`vendor/reflaxe/src`), so both directories are part of the distributed artifact.
