# Semver And Release Posture Decision

Date: 2026-03-15  
Scope bead: `haxe.rust-oo3.23.1`

## Why

Milestone 28 closed the broad production-readiness gate and narrowed the remaining blocker to one
explicit question:

should `reflaxe.rust` remain on an intentionally pre-`1.0` public posture, or should the project
adopt an explicit `1.0` semver/release stance and align packaging language around that choice?

This document is the canonical answer for that question.

## What

Decision:

- `reflaxe.rust` should adopt an explicit `1.0` public release posture.
- `1.0` here means:
  - production-capable on the validated lanes documented in the current support/evidence docs,
  - stability commitments are defined by the documented contract surface and known non-goals,
  - distribution remains GitHub Releases plus lix install flow unless and until a separate publish
    decision changes that.
- `1.0` does **not** mean:
  - blanket semantic parity across every Haxe surface,
  - zero remaining caveats,
  - standalone `reflaxe.std` package hosting from this repo,
  - haxelib publication is required on day one.

The blocker from Milestone 28 was not missing technical proof. It was the lack of an explicit
public semver/package decision. This document resolves that blocker.

## How

This decision is justified by the current evidence set and by the caveat classification already
completed in Milestone 28:

1. `docs/ga-decision-record.md`
   - concluded that `reflaxe.rust` is production-capable on validated lanes
   - concluded that the only remaining blocker to broad GA language was semver/public-packaging posture
2. `docs/ga-caveat-classification.md`
   - classified all remaining caveat buckets
   - left only semver/public packaging as a `blocker`
   - left the other buckets as explicit defers or non-issues
3. current release/distribution machinery already exists
   - semantic-release workflow is implemented in `.github/workflows/release.yml`
   - version synchronization already updates `package.json`, `haxelib.json`, and the packaged zip
   - current install/distribution docs already document the intended GitHub Releases plus lix path

So the right move is not to stay on `0.x` out of inertia. The right move is:

1. decide `1.0`,
2. align package metadata and release workflow to that decision,
3. align public docs and status language to the same decision,
4. keep all documented caveats and non-goals explicit.

## Scope Of The `1.0` Claim

The `1.0` decision is bounded by the current evidence-backed contract, not by wishful reading.

Stable claim:

- explicit `portable|metal` contract model
- validated compiler/runtime baseline
- validated real-app harness
- hardened evidence/docs pipeline
- Rust-local `reflaxe.std` adoption truth for `Option` / `Result`

Still explicitly qualified:

- narrower typed-catch caveat on interface-typed or metadata-free catch paths
- `haxe.MainLoop` / `haxe.EntryPoint` narrower than direct `sys.thread.EventLoop` evidence
- `sys.Http`, `sys.ssl.*`, and `sys.db.*` confidence remains bounded by the current smoke/env-sensitive proof depth
- Windows support remains proven by the current smoke subset, not by blanket parity claims

Those caveats remain part of the public contract and do not block `1.0` as long as they stay
documented honestly.

## Packaging Posture

The `1.0` decision does not require changing the current distribution channel.

Public packaging posture:

- release artifacts are published through GitHub Releases
- install flow is GitHub plus lix
- packaged zip remains haxelib-shaped because that is the correct artifact format for install/use
- this repo is not claiming haxelib.org publication as part of the `1.0` decision

This keeps the public promise narrow and true.

## Result

Resulting next steps:

1. bump versioned metadata and release workflow posture to `1.0.0`
2. align README/status/release docs with that decision
3. keep the existing caveat/defer docs intact and linked

This resolves the blocker identified by Milestone 28 without reopening architecture, perf, or
portable-surface scope.
