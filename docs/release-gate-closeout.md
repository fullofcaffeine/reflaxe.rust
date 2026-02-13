# 1.0 Release-Gate Closeout Template

Use this template when closing Beads issue `haxe.rust-4jb`.

It keeps release evidence consistent and auditable.

## Preconditions

- `docs/progress-tracker.md` and `docs/vision-vs-implementation.md` are synced.
- CI-equivalent checks are green on the candidate branch.
- No unresolved P0/P1 blockers remain.

## Command checklist

```bash
bd graph haxe.rust-4jb --compact
bd ready
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

## Evidence block (copy/paste into Beads notes)

```text
1.0 closeout evidence (YYYY-MM-DD)

- Gate issue: haxe.rust-4jb
- Gate status at review time: in_progress
- Dependency completion: <N>/<N> closed

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
- Close haxe.rust-4jb now: YES|NO
- If NO, next action + owner + target date: <...>
```

## Suggested close command

After adding closeout notes:

```bash
bd close haxe.rust-4jb
```

## Post-close sync

If Beads JSONL changed, sync and include `.beads/issues.jsonl` in your commit:

```bash
bd sync
```

## Related docs

- `docs/road-to-1.0.md`
- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
- `docs/production-readiness.md`
