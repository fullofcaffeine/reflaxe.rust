# Vision vs Implementation (plain-language reality check)

This document checks whether the original product vision matches what is implemented today.

## Vision in one paragraph

`reflaxe.rust` should let teams ship native Rust binaries from Haxe with two practical authoring styles:

- portable Haxe-first development,
- Rust-first development when lower-level control is needed,

while preserving escape hatches behind typed boundaries.

## Live implementation status (auto-generated)

<!-- GENERATED:vision-status:start -->
_Generated from Beads on 2026-02-13 via `npm run docs:sync:progress`._

| Vision checkpoint | Source | Status |
| --- | --- | --- |
| Milestone roadmap complete | `haxe.rust-oo3` | closed |
| Real-app harness complete | `haxe.rust-cu0` | closed |
| 1.0 parity gate | `haxe.rust-4jb` | closed |

- 1.0 parity dependencies closed: **21 / 21 (100%)**
- 1.0 parity dependencies still open: **0**
<!-- GENERATED:vision-status:end -->

## Alignment by major promise

### 1) Native binary workflow should be the default

Status: aligned

- `-D rust_output=...` generates a Cargo crate.
- Cargo build runs by default unless `-D rust_no_build` or `-D rust_codegen_only` is set.

### 2) Product should support both portable and Rust-first usage

Status: aligned, with one important clarification

- User-facing model: portable-first and Rust-first workflows.
- Implementation model: three profiles (`portable`, `idiomatic`, `rusty`).
- `idiomatic` is intentionally a bridge profile, not a separate philosophy.

### 3) Users should not need raw Rust in app code

Status: aligned with enforcement options

- Typed interop surfaces exist (`extern`, `@:native`, `@:rustCargo`, extra source metadata).
- Strict modes exist to prevent direct injection in app-facing code paths.
- Escape hatch still exists for framework/runtime internals.

### 4) 1.0 should represent production-grade stdlib/sys parity

Status: aligned

- The dedicated release gate (`haxe.rust-4jb`) is closed.
- Closeout evidence includes green `scripts/ci/local.sh` and `scripts/ci/windows-smoke.sh` on 2026-02-13.
- Remaining focus is sustained validation quality as new changes land.

### 5) Product should be battle-tested by a real application harness

Status: aligned

- Advanced TUI harness epic (`haxe.rust-cu0`) is closed.
- Harness coverage remains part of CI-style checks.

## Post-1.0 watchlist

1. CI stability should hold across repeated runs, not only one green pass.
2. Docs and defines reference must stay synchronized with implementation changes.
3. Cross-platform sys behavior edge cases should be logged in Beads as soon as they appear.

## Related docs

- `docs/progress-tracker.md`
- `docs/production-readiness.md`
- `docs/profiles.md`
- `docs/defines-reference.md`
- `docs/road-to-1.0.md`
