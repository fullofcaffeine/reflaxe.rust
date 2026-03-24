# Systems And Environment Proof Audit

## Why

Milestone 40 exists to keep the remaining systems/environment claims honest.

After the GA closeout and the scheduler/thread-pool hardening tranche, the main public caveats are no
longer core compiler/runtime architecture problems. They are proof-depth problems:

- some systems surfaces are supported, but only with smoke-backed evidence,
- some are inherently environment-sensitive,
- and the next step must be the narrowest justified hardening slice instead of a broad systems rewrite.

## What

This document audits the remaining systems/environment buckets and classifies each one as:

- already sufficient for its current public claim,
- needs one targeted proof artifact,
- or remains an explicit defer by design.

It also records the single narrowest justified follow-up for Milestone 40.

## How

The audit is grounded in the current evidence sources:

- `docs/systems-environment-posture.md`
- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.md`
- `test/snapshot/sys_http_smoke`
- `test/snapshot/http_base_override_contract`
- `test/snapshot/sys_ssl_sni`
- `test/snapshot/sys_db_sqlite_smoke`
- `test/snapshot/sys_db_mysql_compile`
- `bash scripts/ci/windows-smoke.sh`

Interpretation rule:

- compile/Tier2 coverage proves inventory and build closure,
- snapshot/smoke coverage proves targeted Rust-target behavior,
- environment-sensitive buckets should stay explicitly qualified instead of being force-promoted into
  fake blanket parity claims.

## Classification Table

| Bucket | Current evidence | Classification | Why | Follow-up decision |
| --- | --- | --- | --- | --- |
| `sys.Http` | `test/snapshot/sys_http_smoke`, `test/snapshot/http_base_override_contract`, Tier1/Tier2 sweep coverage | needs one targeted proof artifact | Current smoke already proves request assembly, multipart/file transfer, duplicate response headers, nullable missing-header lookup, and callback-hook override behavior. The remaining gap is that this is still Rust-target smoke only. A narrow local-server semantic fixture can sharpen confidence without pretending the entire network stack is solved. | Add one targeted `sys.Http` contract fixture as the implementation slice for Milestone 40. |
| `sys.ssl.*` | `test/snapshot/sys_ssl_sni`, Tier1/Tier2 sweep coverage | explicit defer by design | SNI support is real, but TLS behavior is still platform- and certificate-environment-sensitive. One more fixture would not change that public truth enough to justify a dedicated implementation slice right now. | Keep qualified support language; no immediate implementation follow-up. |
| `sys.db.*` | `test/snapshot/sys_db_sqlite_smoke`, `test/snapshot/sys_db_mysql_compile`, Tier2 sweep coverage | explicit defer by design | The current evidence already makes the right distinction: SQLite has runtime smoke via `:memory:`, MySQL is compile-only dependency/codegen proof, and both depend on destination environment/native libraries. Additional proof would still leave the bucket environment-sensitive. | Keep the environment-sensitive split explicit; no immediate implementation follow-up. |
| Windows/platform-sensitive claims | `bash scripts/ci/windows-smoke.sh`, CI workflows, semantic-confidence summary | explicit defer by design | The repo already states the right public truth: Linux CI plus curated Windows smoke. Unless the project decides to add materially broader Windows CI, this bucket is a release-language boundary, not a small implementation task. | Keep public language explicit; no immediate implementation follow-up. |

## Narrowest Justified Follow-Up

The only implementation/proof slice that is both:

- small enough to stay honest,
- and strong enough to materially improve current truth,

is:

1. add one targeted `sys.Http` contract fixture,
2. prefer a local-server path so the proof covers real request/response behavior,
3. aim at the narrow remaining contract gap rather than broad host/network parity claims.

The likely target shape is:

- deterministic local server,
- explicit `onStatus` / `onData` or error-path observation,
- still no claim of blanket host/network semantic parity.

## What This Audit Rejects

This audit explicitly rejects:

- a broad systems rewrite,
- a generic TLS hardening tranche,
- a DB portability milestone,
- or a docs-only milestone with no new proof artifact.

Those would either over-scope Milestone 40 or fail to materially improve the truth boundary.
