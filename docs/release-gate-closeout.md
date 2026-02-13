# 1.0 Release Closeout Template

Use this template when finalizing the 1.0 release-readiness gate in your internal tracker.

It keeps release evidence consistent and auditable.

## Preconditions

- `docs/progress-tracker.md` and `docs/vision-vs-implementation.md` are synced.
- CI-equivalent checks are green on the candidate branch.
- No unresolved P0/P1 blockers remain.

## Command checklist

```bash
npm run docs:sync:progress
npm run docs:check:progress
bash scripts/ci/local.sh
```

Optional but recommended before final push:

```bash
bash scripts/ci/windows-smoke.sh
```

Generate a prefilled evidence block first:

```bash
npm run docs:prep:closeout
```

## Evidence block (copy/paste into your release notes)

```text
1.0 closeout evidence (YYYY-MM-DD)

- Release gate status at review time: CLOSED|IN_PROGRESS
- Checklist completion: <N>/<N> closed

Validation runs:
- npm run docs:sync:progress -> PASS
- npm run docs:check:progress -> PASS
- bash scripts/ci/local.sh -> PASS
- bash scripts/ci/windows-smoke.sh -> PASS|SKIPPED (reason)

Docs alignment checks:
- README 1.0 docs index reviewed
- docs/start-here.md reviewed
- docs/progress-tracker.md synced
- docs/vision-vs-implementation.md synced
- docs/defines-reference.md reviewed

Residual risks:
- <list, or "none">

Decision:
- Declare release gate closed now: YES|NO
- If NO, next action + owner + target date: <...>
```

## Closeout step

After adding closeout notes, mark the release gate as closed in your internal tracker.

## Related docs

- `docs/road-to-1.0.md`
- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
- `docs/production-readiness.md`
