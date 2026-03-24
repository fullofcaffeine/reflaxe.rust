# Weekly CI Evidence (Ongoing Validation Cadence)

This page defines the recurring validation cadence for `reflaxe.rust`.

Release-evidence hardening is already closed. This runbook remains useful because the repo still
needs recurring proof that the validated `1.x` lanes stay green and that compile coverage,
semantic parity, and smoke-only confidence remain separated honestly.

Goal: keep confidence anchored to repeatable evidence by re-running full validation on a predictable schedule and reacting quickly to regressions.

## What runs each week

Automated workflow:

- GitHub Actions workflow: `.github/workflows/weekly-ci-evidence.yml`
- Cadence: every Monday at 10:00 UTC
- Trigger options: scheduled run + manual dispatch

Jobs:

1. Linux local-equivalent validation:
   - `npm run docs:sync:progress`
   - `npm run docs:check:progress` (inside `scripts/ci/local.sh`)
   - `bash scripts/ci/local.sh` (includes Tier2 upstream stdlib sweep)
2. Windows smoke validation:
   - `bash scripts/ci/windows-smoke.sh`

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
- semantic-confidence counts that separate:
  - compile/inventory closure
  - targeted semantic/runtime buckets
  - snapshot/smoke-only buckets

Weekly and PR CI also publish deterministic semantic-confidence artifacts:

- `semantic-confidence-summary.json`
- `semantic-confidence-summary.md`

This keeps evidence auditable without requiring manual copy/paste into docs every week.

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
```

## Related docs

- `docs/road-to-1.0.md`
- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
- `docs/semantic-confidence-summary.md`
