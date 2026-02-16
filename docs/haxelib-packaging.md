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

## Backend-specific requirement

The compiler resolves runtime assets relative to library root (`runtime/hxrt`) and bootstrap classpaths
for vendored Reflaxe (`vendor/reflaxe/src`), so both directories are part of the distributed artifact.
