# Weekly CI Evidence (Ongoing Validation Cadence)

This page defines the recurring validation cadence for `reflaxe.rust`.

Release-evidence hardening is already closed. This runbook remains useful because every supported
release line needs recurring proof that its validated lanes stay green and that compile coverage,
semantic parity, and smoke-only confidence remain separated honestly.

Goal: keep confidence anchored to repeatable evidence by re-running full validation on a predictable schedule and reacting quickly to regressions.

## What runs each week

Automated workflow:

- GitHub Actions workflow: `.github/workflows/weekly-ci-evidence.yml`
- Cadence: every Monday at 10:00 UTC
- Trigger options: scheduled run + manual dispatch

Jobs:

1. Linux local-equivalent validation:
   - exact minimum Rust lane from `rust-toolchain-policy.json`
   - `npm run docs:sync:progress`
   - `npm run docs:check:progress` (inside `scripts/ci/local.sh`)
   - `bash scripts/ci/local.sh` (includes Tier2 upstream stdlib sweep)
   - compiler-owned `profile_storyboard` runtime assertions execute through generated portable and
     metal Cargo tests; a required-test inventory makes a missing generated test fail the harness
2. Windows smoke validation:
   - exact minimum Rust lane from the same policy
   - `bash scripts/ci/windows-smoke.sh`
3. Independent `codex-hxrust` consumer compatibility:
   - exact minimum Rust lane from the same policy
   - clones `https://github.com/fullofcaffeine/codex-hxrust` beside this repo
   - `npm run test:codex-hxrust`
   - regenerates portable and metal Rust from Haxe
   - verifies generated `Cargo.toml` / `Cargo.lock`
   - runs `cargo check --locked` and `cargo test --locked` for both generated profiles

The `codex-hxrust` job deliberately consumes that application's normal generated-Cargo command; it
does not turn the app into a compiler test fixture. If the app has no generated tests, the job proves
both profiles compile and link through Cargo but does not claim interactive application runtime
coverage. Purpose-built compiler runtime proof lives in this repository's E2E examples. A generic
backend defect discovered through the consumer build receives a minimized regression here.

Normal push/PR CI also has a required rolling current-stable Rust compatibility job. It catches new
compiler or lint incompatibilities without silently changing the minimum supported version. See
[Rust Toolchain Policy](rust-toolchain-policy.md).

## PR CI harness topology

The push/PR workflow keeps the public `Snapshots + Examples` check name as an aggregate gate, but
the expensive harness work now runs as parallel shards:

- `Harness / snapshots`: snapshot generation/build/run checks.
- `Harness / conformance + policy`: semantic diff, lane diff, upstream stdlib sweep, family std
  sync, metal policy, native-import diagnostics, fallback-count guards, and metal idiom-count guards.
- `Harness / packaging + examples`: package/template smoke, examples compile/run matrix, and
  native-parity checks.
- `HXRT overhead benchmarks`: runtime overhead benchmark gate and benchmark artifacts.

The aggregate `Snapshots + Examples` job depends on those shards and fails if any shard fails or is
cancelled. That preserves one simple required check for branch protection while avoiding a single
long-running monolithic harness job.

Local development intentionally stays simpler:

- `npm run test:all` runs the full harness in one process.
- `HARNESS_STAGES=... bash scripts/ci/harness.sh` is available for focused shard debugging.

## Docs sync guard discipline

- `npm run docs:check:progress` is a required guard for CI/local-CI.
- The guard does not skip when `bd` is unavailable; it falls back to `.beads/issues.jsonl`.
- If tracker-backed sections are stale, regenerate with `npm run docs:sync:progress` and commit docs updates.

## Where evidence is recorded

For each run, evidence is recorded in the workflow run summary (`$GITHUB_STEP_SUMMARY`) with:

- commit SHA
- pass/fail status for each job
- run URL
- command set executed
- exact `rustc --version` used by each required evidence job
- semantic-confidence counts that separate:
  - compile/inventory closure
  - targeted semantic/runtime buckets
  - snapshot/smoke-only buckets

Weekly and PR CI also publish deterministic semantic-confidence artifacts:

- `semantic-confidence-summary.json`
- `semantic-confidence-summary.md`

PR CI uploads those artifacts from the `Harness / conformance + policy` shard. HXRT performance
artifacts are uploaded from the `HXRT overhead benchmarks` shard.

This keeps evidence auditable without requiring manual copy/paste into docs every week.

## Using recurring evidence for release posture

Weekly CI is ongoing monitoring, not a calendar that automatically matures the project. Repeating
an unchanged commit several times mainly tests flake resistance; materially distinct events provide
the stronger release-posture evidence.

- Keep baseline, defect/fix, real release, later no-op or repair, toolchain transition,
  cross-platform, and representative-application evidence distinct.
- A scheduled or manually dispatched run is valid recurring evidence only when all three required
  jobs succeed on the same `haxe.rust` commit: Linux local-equivalent validation, Windows smoke,
  and `codex-hxrust` QA.
- Record exact `haxe.rust` and `codex-hxrust` SHAs, workflow/run and job identifiers, semantic
  confidence artifacts, and the open P0/P1 regression inventory when a run informs a posture
  decision.
- A failed run is evidence, not something to waive. File a regression Bead the same day and require
  a root-cause fix plus regression coverage before relying on later evidence.
- Time-separated runs remain useful for ecosystem and runner drift, but no fixed number of Mondays
  substitutes for the independent `thinking:xhigh` stable-major authorization.

## What to do when a weekly run fails

Open a regression issue in the tracker the same day and include:

1. failing job and step
2. run URL and relevant log excerpt
3. expected behavior vs actual behavior
4. owner and mitigation target date

Treat regressions as release-discipline work, even when they do not block an immediate release.

## Local dry-run commands (manual verification)

```bash
npm run docs:sync:progress
npm run docs:check:progress
npm run docs:sync:evidence
npm run docs:check:evidence
bash scripts/ci/local.sh
bash scripts/ci/windows-smoke.sh
npm run test:codex-hxrust
```

Use `npm run test:codex-hxrust` locally after important complex compiler/runtime/std/profile
milestones when the sibling app checkout is available. This keeps the weekly independent-consumer
signal from being the first time a broad generated-Rust regression is seen. Source-checkout sibling
apps should mirror `reflaxe.rust`'s `haxe_libraries/reflaxe.rust.hxml` classpaths, including
`std/rust/_std`, so upstream-colliding std modules are visible before Haxe typing starts.

## Related docs

- `docs/road-to-1.0.md`
- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
- `docs/semantic-confidence-summary.md`
