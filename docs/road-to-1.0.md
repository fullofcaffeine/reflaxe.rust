# Road to 1.0 (Execution Playbook)

This is the practical plan that moved the project from "almost there" to a defensible production 1.0 release.

It is written for teams that are not compiler specialists.

## Current baseline (as of February 13, 2026)

- Core compiler/runtime foundation work: closed.
- Advanced real-app stress harness work: closed.
- 1.0 production release gate: closed.
- Release-gate checks: 100% closed.

Meaning: the 1.0 closeout gate is complete. Remaining work is post-1.0 quality discipline.

## Exit definition for 1.0

Ship 1.0 only when all conditions below are true at the same time:

1. The release readiness gate is closed.
2. CI-equivalent checks are green on the release candidate branch.
3. Cross-platform CI (including Windows smoke) is green.
4. Docs and implementation are synchronized (profiles, defines, runtime assumptions).
5. No unresolved P0/P1 production-readiness risks remain open.

## Execution phases

### Phase A: Stabilization window

Goal: prove there are no hidden regressions under normal development churn.

Actions:

- Keep running full local CI equivalent on candidate updates:
  - `bash scripts/ci/local.sh`
- Keep `docs/progress-tracker.md` and `docs/vision-vs-implementation.md` in sync:
  - `npm run docs:sync:progress`
- Enforce no new undocumented behavior changes in profiles/interop/runtime.

Success signal:

- Consecutive green CI cycles with no new release-blocking regressions.

Status: completed for 1.0 closeout on February 13, 2026.

### Phase B: Release gate closeout

Goal: convert technical readiness into explicit release readiness.

Actions:

- Re-validate release-gate evidence in the internal tracker:
  - acceptance criteria references,
  - latest green CI links,
  - documented known limitations.
- Confirm docs index points users to current guidance:
  - onboarding,
  - progress tracker,
  - defines reference,
  - production readiness guide.

Success signal:

- The release gate is explicitly marked closed with evidence.

Status: completed on February 13, 2026.

### Phase C: Release candidate and tag

Goal: publish 1.0 without documentation or process drift.

Actions:

- Freeze non-essential feature work during release candidate validation.
- Run full pre-push directive checks from `AGENTS.md`.
- Confirm release automation inputs are aligned (versions, changelog, docs links).

Success signal:

- Mainline release automation can run without manual fixes.

## Weekly operating cadence (recommended)

- Once per week, run and review:
  - `npm run docs:sync:progress`
  - `bash scripts/ci/local.sh`
- Log any new production risks immediately in the internal tracker.

## Common failure modes to avoid

- Assuming dependency closure means release closure.
- Letting docs drift from implementation details (especially profile behavior and string mode policy).
- Relying on one green run instead of sustained green confidence.

## Closeout checklist (completed on February 13, 2026)

1. CI evidence is fresh and repeatable.
2. Tracker docs are synchronized.
3. Profile and define docs reflect current behavior.
4. Release gate has explicit closeout notes.

## Related docs

- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
- `docs/production-readiness.md`
- `docs/defines-reference.md`
- `docs/v1.md`
- `docs/release-gate-closeout.md`
  - helper command: `npm run docs:prep:closeout`
