# GA Decision Record

Historical note:

- this document records the Milestone 28 GA gate outcome
- the current public semver/package posture now lives in `docs/semver-release-posture.md`

Date: 2026-03-15  
Scope bead: `haxe.rust-oo3.22.5`

## Why

Milestone 28 exists to answer one release-sensitive question cleanly:

is `reflaxe.rust` ready for an honest broad production / GA / `1.0` closeout right now, or does the
repo still have a blocker that must be resolved in a narrow follow-up milestone?

This record is the canonical answer.

## What

Decision:

- `reflaxe.rust` is production-capable on its validated lanes.
- `reflaxe.rust` is **not yet** ready for an honest broad GA / `1.0` closeout.
- The blocker is narrow and explicit: semver/public-packaging posture is still unresolved while the
  repo remains on `0.62.0`.

That means Milestone 28 closes by creating a blocker-only Milestone 29 rather than by declaring
broad GA / `1.0` complete.

## How

This decision is based on three inputs that were completed during Milestone 28:

1. `docs/ga-caveat-classification.md`
   - classified the remaining caveat buckets as `blocker`, `explicit defer`, or `non-issue`
   - outcome: only semver/public-packaging posture remained a blocker
2. public docs alignment
   - README and landing docs now point to one canonical GA-review source
   - hardening and support language no longer contradict the current evidence posture
3. current validation evidence
   - docs sync/evidence guards
   - family std bootstrap/sync verification
   - Windows smoke
   - full local CI-equivalent run

## Caveat Classification Outcome

Current classification summary:

- `blocker`
  - semver / public packaging posture while still on `0.x`
- `explicit defer`
  - typed catch exact-type limitation (now narrowed after Milestone 35)
  - `haxe.MainLoop` / `haxe.EntryPoint` vs direct `sys.thread.EventLoop`
  - `sys.Http` smoke-only confidence
  - `sys.ssl.*` smoke-only confidence
  - `sys.db.*` environment-sensitive smoke confidence
  - Windows smoke subset vs blanket platform claims
- `non-issue`
  - `reflaxe.std` package-hosting truth vs local Rust adoption

Interpretation:

- most remaining caveats are real but already qualified enough to live as documented defers
- they do not justify reopening architecture or broad implementation work
- the release truth still cannot honestly jump from `0.62.0` to broad GA language without an explicit
  semver/public-packaging decision

## Evidence Commands

Recorded command set for this decision:

- `npm run docs:sync:progress` -> PASS
- `npm run docs:check:progress` -> PASS
- `npm run docs:sync:evidence` -> PASS
- `npm run docs:check:evidence` -> PASS
- `npm run test:family-stdlib-bootstrap` -> PASS
- `npm run test:family-stdlib-sync` -> PASS
- `bash scripts/ci/windows-smoke.sh` -> PASS
- `npm run docs:prep:closeout` -> PASS
- `bash scripts/ci/local.sh` -> PASS
  - full local CI-equivalent completed successfully
  - noted non-blocking soft perf warnings:
    - `json_overhead.metal.runtime`
    - `portable_vs_metal.bytesRuntimePortableVsMetal`
  - these remain warnings only and match the frozen post-M27 perf posture in `docs/perf-hxrt-overhead.md`

## 1.0 Closeout Evidence Block

```text
1.0 closeout evidence (2026-03-15)

- Release gate status at review time: NOT_READY_FOR_CLOSEOUT
- Checklist completion: historical closeout exists, but current GA review keeps semver/public packaging as an explicit blocker
- Remaining checklist items: semver/public packaging decision

Validation runs:
- npm run docs:sync:progress -> PASS
- npm run docs:check:progress -> PASS
- npm run docs:sync:evidence -> PASS
- npm run docs:check:evidence -> PASS
- npm run test:family-stdlib-bootstrap -> PASS
- npm run test:family-stdlib-sync -> PASS
- bash scripts/ci/local.sh -> PASS
- bash scripts/ci/windows-smoke.sh -> PASS

Docs alignment checks:
- README reviewed and corrected
- docs/start-here.md reviewed and corrected
- docs/index.md reviewed and corrected
- docs/progress-tracker.md synced
- docs/vision-vs-implementation.md synced
- docs/road-to-1.0.md reviewed
- docs/reflaxe-std-adoption-contract.md reviewed and corrected
- docs/perf-hxrt-overhead.md reviewed and corrected

Residual risks:
- typed catch now covers emitted non-generic class hierarchies; narrower exact-type limits remain on some interface/metadata-free paths
- MainLoop/EntryPoint remain narrower than direct EventLoop evidence
- sys.Http / sys.ssl / sys.db remain supported with smoke-level or environment-sensitive proof depth
- Windows confidence remains smoke-subset rather than blanket parity
- semver/public packaging posture is still unresolved while version remains 0.62.0

Decision:
- Declare release gate closed now: NO
- Next action + owner + target: complete blocker-only Milestone 29 (`haxe.rust-oo3.23`) for semver/public packaging decision and aligned release language
```

## Resulting Next Milestone

Created blocker-only follow-up:

- `haxe.rust-oo3.23` — `Milestone 29 — Release closeout + semver/public packaging decision`

Child tasks:

- `haxe.rust-oo3.23.1` — decide and document `1.0` vs continued `0.x` posture
- `haxe.rust-oo3.23.2` — align package metadata and release workflow with that decision
- `haxe.rust-oo3.23.3` — align public release language with that decision

This next milestone is intentionally narrow. It does **not** reopen feature work, broad perf work, or
portable-surface expansion.

## Final Call

Current final call for Milestone 28:

- architecture: ready
- validated-lane production use: ready
- broad GA / `1.0` closeout: not yet
- reason: explicit semver/public-packaging blocker remains

Milestone 28 can close now that the full local CI-equivalent run has been recorded as `PASS`.
