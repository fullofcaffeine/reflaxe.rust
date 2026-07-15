# Fresh Cargo Resolution Baseline

## Why

The generated crate's `rust-version` protects compiler compatibility after Cargo selects a graph,
but future semver-compatible dependency releases can change what an empty installation selects.
This baseline makes that external graph change reviewable at the supported Rust floor.

## What

Each policy-owned case contains the exact fresh `Cargo.lock` plus normalized Cargo metadata. The
metadata keeps package requirements, enabled features, workspace membership, and resolved edges,
while excluding checkout paths and Cargo cache locations. `manifest.json` binds every artifact by
SHA-256 and records the resolver, floor, repeatability, and lock policy.

These lockfiles are compiler evidence only. They are not templates for generated applications,
whose dependencies and features can differ and whose own `Cargo.lock` must be committed separately.

## How

Run `npm run fresh-cargo-resolution:refresh` only on the exact minimum Rust toolchain. The runner
uses two independent passes with an empty Cargo home for every case, checks/tests the first pass,
requires both passes to match byte-for-byte, and rejects an incompatible-dependency mutation. Review
all lock, metadata, and manifest diffs before accepting the refresh; normal CI uses check-only mode
and cannot rewrite this directory.
