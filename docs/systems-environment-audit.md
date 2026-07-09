# Systems And Environment Proof Audit

## Why

Milestone 40 exists to keep the remaining systems/environment claims honest.

After the GA closeout and the scheduler/thread-pool hardening tranche, the main public caveats are no
longer core compiler/runtime architecture problems. They are proof-depth problems:

- some systems surfaces are supported by targeted semantic proof plus smoke-backed evidence,
- some are inherently environment-sensitive,
- and the next step must be the narrowest justified hardening slice instead of a broad systems rewrite.

Post-implementation status: the `sys.Http` follow-up identified by this audit has landed as
`test/semantic_diff/sys_http_callback_contract`. This page now records both the original audit
decision and the closed proof boundary so future work does not reopen the same slice.

## What

This document audits the remaining systems/environment buckets and classifies each one as:

- already sufficient for its current public claim,
- targeted proof complete but still explicitly scoped,
- or remains an explicit defer by design.

It also records the single narrowest justified follow-up selected for Milestone 40 and its current
closed state.

## How

The audit is grounded in the current evidence sources:

- `docs/systems-environment-posture.md`
- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.md`
- `test/semantic_diff/sys_http_callback_contract`
- `test/snapshot/sys_http_smoke`
- `test/snapshot/http_base_override_contract`
- `test/snapshot/sys_ssl_sni`
- `test/snapshot/sys_db_sqlite_smoke`
- `test/snapshot/sys_db_mysql_compile`
- `bash scripts/ci/windows-smoke.sh`

Interpretation rule:

- compile/Tier2 coverage proves inventory and build closure,
- targeted semantic coverage proves the named behavior only,
- snapshot/smoke coverage proves targeted Rust-target behavior and generated-shape closure,
- environment-sensitive buckets should stay explicitly qualified instead of being force-promoted into
  fake blanket parity claims.

## Classification Table

| Bucket | Current evidence | Classification | Why | Follow-up decision |
| --- | --- | --- | --- | --- |
| `sys.Http` | `test/semantic_diff/sys_http_callback_contract`, `test/snapshot/sys_http_smoke`, `test/snapshot/http_base_override_contract`, Tier1/Tier2 sweep coverage | targeted proof complete, still scoped | The local-server semantic fixture proves the callback/status/body/error boundary. Snapshot smoke still owns multipart/file transfer, duplicate response headers, nullable missing-header lookup, and callback-hook override shape. This is stronger than the original smoke-only state, but it is still not blanket host/network parity. | Closed by the targeted `sys.Http` contract fixture. No immediate additional systems follow-up is justified by this audit. |
| `sys.ssl.*` | `test/snapshot/sys_ssl_sni`, Tier1/Tier2 sweep coverage | explicit defer by design | SNI support is real, but TLS behavior is still platform- and certificate-environment-sensitive. One more fixture would not change that public truth enough to justify a dedicated implementation slice right now. | Keep qualified support language; no immediate implementation follow-up. |
| `sys.db.*` | `test/snapshot/sys_db_sqlite_smoke`, `test/snapshot/sys_db_mysql_compile`, Tier2 sweep coverage | explicit defer by design | The current evidence already makes the right distinction: SQLite has runtime smoke via `:memory:`, MySQL is compile-only dependency/codegen proof, and both depend on destination environment/native libraries. Additional proof would still leave the bucket environment-sensitive. | Keep the environment-sensitive split explicit; no immediate implementation follow-up. |
| Windows/platform-sensitive claims | `bash scripts/ci/windows-smoke.sh`, CI workflows, semantic-confidence summary | explicit defer by design | The repo already states the right public truth: Linux CI plus curated Windows smoke. Unless the project decides to add materially broader Windows CI, this bucket is a release-language boundary, not a small implementation task. | Keep public language explicit; no immediate implementation follow-up. |

## Resolved Follow-Up

The only implementation/proof slice that was both:

- small enough to stay honest,
- and strong enough to materially improve current truth,

was:

1. add one targeted `sys.Http` contract fixture,
2. prefer a local-server path so the proof covers real request/response behavior,
3. aim at the narrow remaining contract gap rather than broad host/network parity claims.

That landed as `test/semantic_diff/sys_http_callback_contract`, whose target shape is:

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
