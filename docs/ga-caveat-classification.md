# GA Caveat Classification

Historical note:

- this document is the Milestone 28 caveat input, not the current public release posture
- the semver/public-packaging blocker identified here was resolved by
  [Semver And Release Posture Decision](semver-release-posture.md)

## Why

Milestone 28 needs one canonical input that answers a narrow release question:
which remaining caveats actually block an honest broad production / GA decision, and which are documented defers or non-issues.

Without that classification, the repo risks bouncing between two bad states:

- overclaiming broad readiness from compile coverage and green harnesses alone, or
- underselling validated lanes because every remaining caveat gets treated like a release blocker.

## What

This document classifies the current candidate caveat buckets for `reflaxe.rust` into one of:

- `blocker`: must be resolved before an honest broad production / GA closeout
- `explicit defer`: may remain open, but only if the limitation stays documented and public claims stay qualified
- `non-issue`: already resolved, already qualified enough, or not material to the GA decision

This is a release-truth input, not a broad feature roadmap.

## How

The classifications below are grounded in the current repo evidence:

- support and confidence summaries: `docs/feature-support-matrix.md`, `docs/semantic-confidence-summary.md`
- readiness and limitation docs: `docs/production-readiness.md`, `docs/v1.md`, `docs/threading.md`, `docs/reflaxe-std-adoption-contract.md`
- current public/package posture: `README.md`, `package.json`
- CI/workflow evidence: `.github/workflows/ci.yml`, `.github/workflows/weekly-ci-evidence.yml`, `docs/weekly-ci-evidence.md`

Interpretation rule:

- Tier1/Tier2 sweeps and candidate-audit closure are strong compile/inventory proof.
- They are not blanket runtime-semantic proof.
- Snapshot/smoke-only buckets can still be acceptable for GA, but only when public claims stay explicit about their proof depth.

## Historical Classification Table

This table is preserved as the Milestone 28 classification input. The semver/public-packaging row
was later resolved by [Semver And Release Posture Decision](semver-release-posture.md).

| Bucket | Current evidence | Classification | Why | GA implication |
| --- | --- | --- | --- | --- |
| Typed catch exact-type limitation | `docs/v1.md`, `docs/feature-support-matrix.md`, `docs/semantic-confidence-summary.md`, `test/semantic_diff/exceptions_typed_dynamic`, `test/semantic_diff/exception_dynamic_payload`, `test/semantic_diff/typed_catch_subclass` | `explicit defer` | Exception semantics are covered on key lanes, and emitted non-generic class hierarchies now follow the Haxe subclass chain. The remaining limitation is narrower: interface-typed or metadata-free catch paths still rely on exact downcast behavior. | Keep the narrower limitation visible in public docs. Do not claim blanket typed-catch parity across every dynamic/interface edge. |
| `haxe.MainLoop` / `haxe.EntryPoint` vs direct `sys.thread.EventLoop` | `docs/threading.md`, `docs/v1.md`, `docs/semantic-confidence-summary.md`, `test/snapshot/sys_thread_event_loop`, `examples/sys_thread_smoke`, `examples/thread_pool_smoke` | `explicit defer` | Direct `sys.thread.EventLoop` has Rust-target smoke proof. `haxe.MainLoop` / `haxe.EntryPoint` are still narrower and are not claimed as `--interp`-backed semantic parity. | Broad production claims must keep this caveat. Do not claim blanket `--interp`-style thread/event-loop parity. |
| `sys.Http` smoke-only confidence | `docs/feature-support-matrix.md`, `docs/semantic-confidence-summary.md`, `test/snapshot/sys_http_smoke`, Tier1/Tier2 sweeps | `explicit defer` | The current proof depth is compile coverage plus snapshot-backed smoke. That is enough to keep `sys.Http` in the supported portable surface, but not enough for blanket semantic-parity language. | Leave `sys.Http` qualified as supported with smoke-level proof depth rather than full semantic closure. |
| `sys.ssl.*` snapshot/smoke confidence | `docs/feature-support-matrix.md`, `docs/semantic-confidence-summary.md`, `test/snapshot/sys_ssl_sni`, Tier1/Tier2 sweeps | `explicit defer` | SNI support exists and snapshot smoke is real, but TLS behavior remains environment- and platform-sensitive. | Keep support claims qualified. Do not translate SNI smoke into blanket TLS parity language. |
| `sys.db.*` native-environment smoke confidence | `docs/feature-support-matrix.md`, `docs/semantic-confidence-summary.md`, `test/snapshot/sys_db_mysql_compile`, `test/snapshot/sys_db_sqlite_smoke`, Tier2 sweep | `explicit defer` | DB support is real on the Rust target, but current evidence is compile/smoke-oriented and depends on destination native libraries and environment setup. | Preserve support language, but keep environment-sensitive caveats explicit. This is not broad host-independent parity proof. |
| Windows smoke subset vs blanket platform claims | `.github/workflows/ci.yml`, `.github/workflows/weekly-ci-evidence.yml`, `docs/weekly-ci-evidence.md`, `docs/semantic-confidence-summary.md` | `explicit defer` | Windows confidence is real, but it is a curated smoke subset, not the same as full Windows semantic closure. | Broad production language must say Linux CI + Windows smoke, not imply broad cross-platform parity. |
| `reflaxe.std` package-hosting truth vs local Rust adoption | `docs/reflaxe-std-adoption-contract.md`, `docs/road-to-1.0.md`, `docs/index.md` | `non-issue` | The repo already documents the important truth: Rust has local adoption and lowering, but standalone family hosting/publishing is not owned here. Some entrypoint wording still needs cleanup, but the substantive boundary is already clear. | Fix stale public wording in Milestone 28 docs work, but this does not block a GA decision on the Rust target itself. |
| Semver / public packaging posture while still on `0.x` | `package.json`, `docs/production-readiness.md`, `docs/road-to-1.0.md`, `README.md` as they stood during Milestone 28 | `blocker` | The repo could plausibly justify production use on validated lanes, but an honest broad GA / `1.0` closeout still required an explicit semver and release decision. Staying on `0.62.0` while speaking like GA was closed would have collapsed the distinction between “production-capable” and “released as 1.0”. | Milestone 28 had to end with an explicit go/no-go decision. That follow-up decision is now recorded in [Semver And Release Posture Decision](semver-release-posture.md). |

## Out-Of-Band Findings For Milestone 28

These are not separate caveat buckets, but they do affect the public-truth pass:

- `README.md` still says release-evidence hardening is still in progress, which now undershoots the actual closed state of Milestones 26 and 27.
- `docs/road-to-1.0.md`, `docs/progress-tracker.md`, and `docs/vision-vs-implementation.md` already reflect the harder truth more accurately than `README.md`.
- The support matrix and semantic-confidence summary are directionally honest, but public entrypoint docs still need a single canonical GA-decision source once Milestone 28 closes.

## Current Decision Posture

Historical posture immediately after this classification:

- `reflaxe.rust` is production-capable on its validated lanes.
- Most remaining caveats are `explicit defer`, not broad architectural blockers.
- The only `blocker` to an honest broad GA / `1.0` closeout at that time was that the repo had not yet made the explicit semver/release decision and aligned public entrypoint language around it.

Current release posture:

- that semver/release blocker is resolved by
  [Semver And Release Posture Decision](semver-release-posture.md)
- the explicit defers remain documented caveats, not broad release blockers

At the time, that meant Milestone 28 should continue as planned:

1. align entrypoint docs to the audited truth,
2. freeze the honest post-M27 perf posture,
3. freeze the Rust-local `reflaxe.std` boundary truth,
4. then publish one canonical GA decision record.
