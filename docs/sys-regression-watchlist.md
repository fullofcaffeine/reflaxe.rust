# Cross-Platform Sys Regression Watchlist

This page is the post-1.0 watchlist for `sys.*` risk areas.

It exists to keep regressions visible, owned, and mitigated quickly across platforms.

## Scope

Focus areas:

- `sys.FileSystem` / `sys.io.File`
- `sys.net.*`
- `sys.thread.*`
- `sys.io.Process` / process I/O and exit behavior

Platforms:

- Linux (primary CI)
- Windows (smoke CI)
- macOS (local contributor validation)

## Operating rule

If a new regression is observed:

1. add a row to **Active regressions** immediately,
2. open a tracker issue and reference its ID in the row,
3. assign an owner and mitigation status,
4. attach run evidence (CI run URL or local repro notes).

## Active regressions

Current state: none.

| Area | Platform | Symptom | Evidence | Tracker issue | Owner | Mitigation status | Last updated |
| --- | --- | --- | --- | --- | --- | --- | --- |
| _none_ | - | - | - | - | - | - | 2026-02-13 |

## Resolved regressions

Add resolved items here for short-term memory (last 4 to 8 entries), then archive as needed.

| Area | Platform | Symptom | Tracker issue | Resolution summary | Closed date |
| --- | --- | --- | --- | --- | --- |
| _none yet_ | - | - | - | - | - |

## Related docs

- `docs/weekly-ci-evidence.md`
- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
