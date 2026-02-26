# Portable Stdlib Parity Backlog

Status: closed for the current audit cycle.

Current state:

- `docs/portable-stdlib-candidates.json` reports `missingFromTier2: 0`.
- Tier2 now covers all currently importable upstream modules detected by the candidate audit.

Closed implementation track:

- `haxe.rust-hss.1` promoted tranche A.
- `haxe.rust-hss.1.1` fixed `Std` upstream-sweep resolution and promoted `Std`.
- `haxe.rust-hss.2` promoted tranche B.
- `haxe.rust-hss.3` documented macro/display + target-adapter interpretation and is now superseded
  by zero-gap candidate coverage.
- `haxe.rust-qjs` swept the remaining candidate set and promoted all compileable modules.

Future parity expansion should continue via:

- `npm run stdlib:audit:candidates`
- `npm run guard:stdlib-candidates`
- `bash test/run-upstream-stdlib-sweep.sh --tier tier2`
