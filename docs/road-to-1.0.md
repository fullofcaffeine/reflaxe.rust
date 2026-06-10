# Release Hardening Record

Historical note:

- this document records the Milestone 26 hardening work that made public readiness claims honest
- the current public semver/package posture now lives in
  [Semver And Release Posture Decision](semver-release-posture.md)

This document records the release-evidence hardening playbook and its closeout state for `reflaxe.rust`.

It replaces the earlier “1.0 closeout” framing with a stricter question:
is the repo's public readiness language as honest as the current evidence?

## Why this doc exists

`reflaxe.rust` has already closed a large amount of real work:

- the compiler/runtime baseline is substantial,
- the real-app harness exists,
- CI/evidence automation is real,
- portable/metal contracts are implemented as actual compiler policy.

What required hardening in the release story was:

- some docs were speaking with more confidence than the current proof depth justified,
- Tier2 inventory closure could be overread as runtime semantic closure,
- a few high-risk semantic buckets still need more explicit proof or clearer caveats.

So this doc is not a banner saying “1.0 is already done”.
It is the record of how the repo hardened the readiness story enough to stop overstating what the evidence proves.

## Current posture

As of March 8, 2026:

- core compiler/runtime baseline: closed
- real-app stress harness: closed
- release-evidence hardening: closed
- semver/public packaging posture: unresolved at the time of this hardening snapshot

That last item was later resolved by
[Semver And Release Posture Decision](semver-release-posture.md), which records the current stable
`1.x` public release posture.

Meaning:

- architecture confidence is high,
- validated implementation confidence is high on the exercised lanes,
- broad public release confidence has been hardened to the current evidence baseline.

## Hardening milestone

Closed roadmap tranche:

- `haxe.rust-oo3.20`
  - `Milestone 26 — Release-evidence hardening + truth-in-claims correction`

Its purpose was to close the remaining gap between:

1. what the repo can actually prove today, and
2. what the public docs/readme/status pages imply.

## Exit criteria for stronger public release claims

At the time of this hardening snapshot, public “1.0” / “post-1.0” language was intentionally blocked
until all of the following were true at the same time:

1. Tracker-backed status docs are internally consistent.
2. Public docs no longer overclaim beyond the current evidence.
3. Compile coverage vs semantic/runtime parity is explicit in docs and CI outputs.
4. High-risk semantic buckets have either:
   - targeted contract tests, or
   - explicit downgraded/qualified documentation.
5. The main evidence commands remain green:
   - `npm run docs:sync:progress`
   - `npm run docs:check:progress`
   - `npm run test:semantic-diff`
   - `npm run test:semantic-diff:lanes`
   - `npm run test:upstream-stdlib:tier2`
   - `npm run test:family-stdlib-bootstrap`
   - `npm run test:family-stdlib-sync`
   - `npm run test:all`
   - `npm run test:windows-smoke`

## Execution tracks

### Track A: Truth-in-claims correction

Goal:

- make README, status docs, and support docs say only what current evidence supports.

Examples:

- remove “post-1.0” framing where the repo is still in hardening,
- stop treating compile/inventory closure as blanket semantic parity,
- keep `reflaxe.std` rollout language honest about local-vs-family hosting.

### Track B: Tracker integrity

Goal:

- ensure generated status docs derive from the right milestone/gate sources.

Examples:

- never use the umbrella roadmap epic as the live readiness signal,
- derive readiness from explicit milestone/gate issues,
- keep docs sync/check deterministic even when `bd` is unavailable.

### Track C: Semantic hardening

Goal:

- add proof where current evidence is thinnest.

Priority buckets:

- exceptions / catch / `Dynamic` boundary behavior,
- reflection subset behavior,
- process/net failure paths,
- thread/event-loop/MainLoop caveats.

### Track D: Evidence hardening

Goal:

- make CI/weekly outputs distinguish:
  - compile coverage,
  - targeted semantic parity,
  - smoke/example-only confidence.

Reviewers should not need to reverse-engineer proof depth from a pile of green jobs.

## Weekly cadence after hardening closeout

Keep running and reviewing:

- `npm run docs:sync:progress`
- `npm run docs:check:progress`
- `bash scripts/ci/local.sh`
- `bash scripts/ci/windows-smoke.sh`

Use `docs/weekly-ci-evidence.md` as the runbook for ongoing validation evidence.

## What this doc is not

This doc is not:

- the current semver/package posture decision,
- proof that Tier2 closure equals runtime parity,
- a license to start a new perf-first or feature-first milestone before the truth gap is closed.

## Related docs

- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
- `docs/production-readiness.md`
- `docs/defines-reference.md`
- `docs/v1.md`
- `docs/weekly-ci-evidence.md`
- `docs/sys-regression-watchlist.md`
