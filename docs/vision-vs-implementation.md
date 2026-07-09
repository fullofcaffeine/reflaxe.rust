# Vision vs Implementation (plain-language reality check)

This document checks whether the original product vision matches what is implemented today.

It should read as a calibration document, not a victory lap.

<!-- GENERATED:release-posture:start -->
Current release posture: **intentional `0.x` pre-1.0 posture**.

Maturity: **production-capable preview on validated lanes**. See [Semver And Release Posture](semver-release-posture.md).
<!-- GENERATED:release-posture:end -->

## Vision in one paragraph

`reflaxe.rust` should let teams ship native Rust binaries from Haxe with two practical authoring styles:

- portable Haxe-first development,
- Rust-first development when lower-level control is needed,

while preserving escape hatches behind typed boundaries.

## Live implementation status (auto-generated)

<!-- GENERATED:vision-status:start -->
_Status snapshot generated from the internal tracker via `npm run docs:sync:progress`._

| Vision checkpoint | What this means | Status |
| --- | --- | --- |
| Baseline milestones complete | Core compiler/runtime architecture is stable across the closed milestone baseline. | closed |
| Real-app harness complete | App-scale behavior is validated in CI-style flows. | closed |
| Release-evidence hardening closed | Public readiness claims, semantic proof depth, and tracker truth were aligned in the latest hardening tranche. | closed |

- Release-evidence hardening checks closed: **5 / 5 (100%)**
- Release-evidence hardening checks still open: **0**
<!-- GENERATED:vision-status:end -->

## Alignment by major promise

### 1) Native binary workflow should be the default

Status: aligned

- `-D rust_output=...` generates a Cargo crate.
- Cargo build runs by default unless `-D rust_no_build` or `-D rust_codegen_only` is set.

### 2) Product should support both portable and Rust-first usage

Status: aligned

- User-facing model: portable-first and Rust-first workflows.
- Implementation model: two explicit profiles (`portable`, `metal`).
- `portable` carries Haxe-portable semantics with production codegen hygiene.
- `metal` is the Rust-first performance profile with strict boundary defaults.

### 3) Users should not need raw Rust in app code

Status: aligned with enforcement options

- Typed interop surfaces exist (`extern`, `@:native`, `@:rustCargo`, extra source metadata).
- Strict modes exist to prevent direct injection in app-facing code paths.
- Escape hatch still exists for framework/runtime internals.

### 4) Release claims should match actual stdlib/sys proof depth

Status: aligned with explicit caveats

- The repo has strong compile/inventory closure and real CI evidence.
- The canonical posture and its measurable graduation evidence are recorded separately from the
  historical gate docs.
- The release-evidence hardening tranche is closed, and current docs now keep compile coverage, targeted semantic parity, and smoke-only confidence separate instead of blending them into one vague support claim.

### 5) Product should be battle-tested by a real application harness

Status: aligned

- The advanced TUI stress harness is complete.
- Harness coverage remains part of CI-style checks.

## Current hardening watchlist

1. CI stability should hold across repeated runs, not only one green pass.
2. Docs and defines reference must stay synchronized with implementation changes.
3. Cross-platform sys behavior edge cases should be logged immediately in the internal tracker.
4. Compile coverage must not be presented as equivalent to runtime semantic parity.

## Related docs

- `docs/progress-tracker.md`
- `docs/production-readiness.md`
- `docs/semver-release-posture.md`
- `docs/profiles.md`
- `docs/defines-reference.md`
- `docs/road-to-1.0.md`
