# Release Scaffold

This bootstrap snapshot is intentionally in-repo and version-pinned via `family/family_std_pin.json`.

Before extracting to a standalone repository:

1. Keep `tools/family_std_sync.py --mode verify` green in CI.
2. Keep `family/reflaxe.family.std/tools/verify_family_std.py` green in CI.
3. Ensure migration checklist cutover criteria in `family/family_std_pin.json` are met.
