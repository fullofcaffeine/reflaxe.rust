# Weekly CI Evidence (Post-1.0 Operations)

This page defines the weekly quality cadence after 1.0.

Goal: keep production confidence high by re-running full validation on a predictable schedule and reacting quickly to regressions.

## What runs each week

Automated workflow:

- GitHub Actions workflow: `.github/workflows/weekly-ci-evidence.yml`
- Cadence: every Monday at 10:00 UTC
- Trigger options: scheduled run + manual dispatch

Jobs:

1. Linux local-equivalent validation:
   - `npm run docs:sync:progress`
   - `bash scripts/ci/local.sh`
2. Windows smoke validation:
   - `bash scripts/ci/windows-smoke.sh`

## Where evidence is recorded

For each run, evidence is recorded in the workflow run summary (`$GITHUB_STEP_SUMMARY`) with:

- commit SHA
- pass/fail status for each job
- run URL
- command set executed

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
bash scripts/ci/local.sh
bash scripts/ci/windows-smoke.sh
```

## Related docs

- `docs/road-to-1.0.md`
- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
