# Reviewed Cargo Dependency Graph

## Why

The generated crate's `rust-version` protects compiler compatibility after Cargo selects a graph.
This directory records the exact dependency graph that reviewers admitted for the compiler matrix.
A later crates.io publication cannot change this repository-owned decision.

## What

Each policy-owned case contains the exact reviewed `Cargo.lock` plus normalized Cargo metadata. The
metadata keeps package requirements, enabled features, workspace membership, and resolved edges,
while excluding checkout paths and Cargo cache locations. `manifest.json` binds every artifact by
SHA-256 and records the resolver, floor, repeatability, and lock policy.

These lockfiles are compiler evidence only. They are not templates for generated applications,
whose dependencies and features can differ and whose own `Cargo.lock` must be committed separately.

## How

`npm run test:fresh-cargo-resolution` copies these locks into isolated fixtures and uses frozen Cargo
commands. It never asks the live registry to select a newer version. Run
`npm run fresh-cargo-resolution:observe` to create an untracked candidate from two independent live
resolutions. Review its classification, then use `npm run fresh-cargo-resolution:admit` to verify and
install those exact candidate bytes without resolving again. Observation never rewrites this directory.
