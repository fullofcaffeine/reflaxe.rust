# Stdlib Parity Policy

This document defines how `reflaxe.rust` tracks stdlib parity and provenance.

## Scope of parity

Portable stdlib parity targets the upstream, cross-target Haxe stdlib surface.

In scope:

- `Std`, `StringTools`, `Date`, `haxe.*`, `sys.*`, and other cross-target std APIs.

Out of scope for parity accounting (target-specific namespaces):

- `cpp.*`, `cs.*`, `java.*`, `jvm.*`, `js.*`, `lua.*`, `php.*`, `python.*`, `hl.*`, `neko.*`.
- `rust.*` (Rust-native extension surface in this backend).

## Override model

- Upstream-colliding std overrides live under `std/**` and use `.cross.hx` suffixes.
- `.cross.hx` prevents accidental leakage into non-target eval/macro contexts while preserving
  packaged-target behavior.

## Provenance governance

Tracked artifacts:

- `docs/portable-stdlib-allowlist.json`
  - Canonical portable-stdlib scope artifact:
    - excluded target-specific namespace prefixes
    - deterministic Tier1 upstream sweep module list
- `test/upstream_std_modules.txt`
  - Tier1 upstream sweep module list (PR/harness default).
- `test/upstream_std_modules_tier2.txt`
  - Tier2 upstream sweep module list for broader parity checks outside PR-critical loops.
- `docs/stdlib-provenance-ledger.json`
  - Ledger for all tracked `std/**/*.cross.hx` files.
  - Records whether each file is an upstream sync or a repo-authored override.

CI/guard scripts:

- `scripts/ci/upstream-stdlib-boundary-check.js`
  - Enforces `vendor/haxe/**` remains untracked.
  - Restricts checked-in std override file types under `std/`.
- `scripts/ci/stdlib-provenance-ledger-check.js`
  - Enforces ledger coverage and stale-entry detection for tracked `.cross.hx` files.
- `scripts/ci/portable-stdlib-allowlist-check.js`
  - Enforces allowlist invariants:
    - sorted/unique exclude prefixes and Tier1 module list
    - Tier1 modules do not use excluded target prefixes
    - Tier1 list stays in sync with `test/upstream_std_modules.txt` (content + order)
    - Tier2 list is sorted/unique, stays within portable namespace scope, and contains Tier1 as a subset

## Portable contract and native imports

Portable contract should remain reviewably portable.

- Importing native target modules in portable code emits a warning by default.
- Set `-D rust_portable_native_import_strict` to escalate native-import warnings to errors.
- Contract reports (`-D rust_contract_report`) include native-import hits and a portability marker.

## Runtime capability taxonomy (Rust -> family)

`HxrtFeatureAnalyzer` emits Rust runtime feature names that map to family capability groups:

- `core` -> `core`
- `io` -> `io`
- `fs` -> `fs`
- `process` -> `process`
- `thread` -> `thread`
- `net` -> `net`
- `ssl` -> `ssl`
- `json` -> `json`
- `db` -> `db`
- `date` -> `date`
- `async` -> `async`
- `async_tokio` -> `async_runtime_adapter` (tokio-specific adapter lane)

These mappings are reflected in deterministic runtime planning artifacts:

- `runtime_plan.json`
- `runtime_plan.md`

## Validation workflow

- `npm run stdlib:sync:allowlist`
- `npm run guard:upstream-stdlib-boundary`
- `npm run guard:stdlib-ledger`
- `npm run guard:portable-stdlib-allowlist`
- `bash test/run-upstream-stdlib-sweep.sh`
- `bash test/run-upstream-stdlib-sweep.sh --tier tier2`
- `npm run check:harness`
