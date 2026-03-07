# Stdlib Parity Policy

This document defines how `reflaxe.rust` tracks stdlib parity and provenance.

## Scope of parity

Portable stdlib parity targets the upstream, cross-target Haxe stdlib surface.

In scope:

- `Std`, `StringTools`, `Date`, `haxe.*`, `sys.*`, and other cross-target std APIs.

Out of scope for parity accounting (target-specific namespaces):

- `cpp.*`, `cs.*`, `java.*`, `jvm.*`, `js.*`, `lua.*`, `php.*`, `python.*`, `hl.*`, `neko.*`.
- `rust.*` (Rust-native extension surface in this backend).

## Family governance vs user idiom package

Rust follows a two-layer model:

1. `reflaxe.family.std`
   - Governance/spec/conformance assets shared across backends.
2. `reflaxe.std`
   - User-facing portable idiom package.
   - V1 starts with `Option` / `Result`.
   - Future growth should add portable idioms only when semantics stay explicit and testable across
     backends.

Contract rule:

- portable semantics are owned by family governance assets plus conformance fixtures.
- native target facades (`rust.*`, `go.*`, `elixir.*`, etc.) stay backend-local and are not
  silently substituted for portable APIs.

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
- `docs/portable-stdlib-candidates.json`
  - Deterministic audit report of upstream importable modules in portable scope vs Tier2 coverage.
- `docs/portable-stdlib-candidates.md`
  - Human-readable summary of `portable-stdlib-candidates.json` for parity planning.
- `docs/portable-stdlib-parity-backlog.md`
  - Audit-cycle tracker and closure notes for candidate-gap promotion work.
- `test/upstream_std_modules.txt`
  - Tier1 upstream sweep module list (PR/harness default).
- `test/upstream_std_modules_tier2.txt`
  - Tier2 upstream sweep module list for broader parity checks outside PR-critical loops.
- `test/upstream_std_modules_tier2_extras.txt`
  - Tier2 extras list merged with Tier1 to deterministically produce `test/upstream_std_modules_tier2.txt`.
- `docs/stdlib-provenance-ledger.json`
  - Ledger for all tracked `std/**/*.cross.hx` files.
  - Records whether each file is an upstream sync or a repo-authored override.
- `family/family_std_pin.json`
  - Pin file for the in-repo `reflaxe.family.std` bootstrap snapshot consumed by this repo.
- `family/reflaxe.family.std/**`
  - Family-shared portable contract artifacts (allowlist, conformance, semantics spec, mapping contract).
- `test/portable_allowlist.json`
  - Canonical tiered portable-contract allowlist synchronized with
    `family/reflaxe.family.std/allowlists/portable_allowlist.v1.json`.
- `test/portable_conformance_tier1.json`
  - Canonical Tier1 module→semantic fixture mapping synchronized with
    `family/reflaxe.family.std/conformance/tier1/portable_conformance_tier1.v1.json`.
- `docs/portable-semantics-v1.md`
  - Canonical portable semantics contract synchronized with
    `family/reflaxe.family.std/contracts/portable-semantics/v1.md`.
- `docs/portable-module-mapping-contract.md`
  - Canonical portable module ownership map synchronized with
    `family/reflaxe.family.std/docs/module-mapping-contract.v1.md`.

CI/guard scripts:

- `scripts/ci/upstream-stdlib-boundary-check.js`
  - Enforces `vendor/haxe/**` remains untracked.
  - Restricts checked-in std override file types under `std/`.
- `scripts/ci/stdlib-provenance-ledger-check.js`
  - Enforces ledger coverage and stale-entry detection for tracked `.cross.hx` files.
  - Enforces Tier2 upstream sweep coverage for every ledger-derived import module.
  - Requires explicit `tier2SweepExcludeReason` on ledger entries that intentionally do not
    map to importable upstream modules (for example boundary alias modules).
- `scripts/ci/portable-stdlib-allowlist-check.js`
  - Enforces allowlist invariants:
    - sorted/unique exclude prefixes and Tier1 module list
    - Tier1 modules do not use excluded target prefixes
    - Tier1 list stays in sync with `test/upstream_std_modules.txt` (content + order)
    - Tier2 list is sorted/unique, stays within portable namespace scope, and matches deterministic
      `sort(unique(Tier1 + Tier2 extras))`
- `scripts/ci/audit-upstream-stdlib-candidates.js`
  - Scans `vendor/haxe/std` to compute upstream importable portable-scope modules.
  - Emits deterministic candidate artifacts and validates them via `--check`.
  - Candidate scan is broad by design (including compile-time/tooling modules) and serves as the
    authoritative source for parity-gap detection (`missingFromTier2`).
  - `--check` fallback behavior: if upstream std source discovery is unavailable (for example no
    vendored std and no Haxe binary on PATH), the guard reuses
    `docs/portable-stdlib-candidates.json`'s `upstreamImportableModules` and still verifies
    deterministic artifacts + Tier2 coverage. If allowlist scope/version drift is detected, it
    fails and requires a full `--write` regeneration with std source access.
- `scripts/ci/check-portable-stdlib-candidate-gap.js`
  - Enforces a hard parity-gap budget against `missingFromTier2` in
    `docs/portable-stdlib-candidates.json`.
  - Default budget is `0` (no uncovered candidates).
  - Optional override for planned transitions:
    `PORTABLE_STDLIB_CANDIDATE_GAP_MAX=<n>`.
- `tools/family_std_sync.py`
  - Verifies canonical Rust artifacts remain in sync with the family snapshot.
  - Generates deterministic dual-run artifacts in `test/.cache/family_std_dual_run_report.{json,md}`.

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
- `npm run stdlib:audit:candidates`
- `npm run stdlib:sync:tier2`
- `npm run guard:upstream-stdlib-boundary`
- `npm run guard:stdlib-ledger`
- `npm run guard:portable-stdlib-allowlist`
- `npm run guard:stdlib-candidates`
- `npm run guard:stdlib-candidate-gap`
- `bash test/run-upstream-stdlib-sweep.sh`
- `bash test/run-upstream-stdlib-sweep.sh --tier tier2`
- `npm run check:harness`
