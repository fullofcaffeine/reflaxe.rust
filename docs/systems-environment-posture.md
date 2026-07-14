# Systems And Environment Posture

This page is the canonical status record for the remaining platform-sensitive systems surfaces in
`reflaxe.rust`.

Use it when the question is:

- what is supported today for `sys.Http`, `sys.ssl.*`, and `sys.db.*`,
- what proof depth exists for those surfaces,
- what is still environment-sensitive,
- and what should remain explicitly qualified in production language?

## Why this exists

Systems truth was previously scattered across:

- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.md`
- `docs/production-readiness.md`
- `docs/ga-caveat-classification.md`

Those pages still matter, but they answer different questions. This page is the one place that
classifies the current systems/environment posture.

## Stable today

### Portable `sys.*` support remains real on validated Rust lanes

Stable posture:

- `sys.*` stays part of the portable contract on Rust-supported platforms
- support claims remain explicit about proof depth instead of collapsing everything into a fake
  blanket semantic-parity story
- admitted `Sys` path/process failures and standard-stream I/O failures cross the Haxe exception
  boundary instead of terminating through Rust `unwrap()` panics
- malformed environment names/values are validated before Rust's process-environment API can panic
- `Sys.putEnv` is experimental rather than stable-candidate: Windows permits process-environment
  mutation, but on non-Windows Rust cannot guarantee it after threads or foreign environment readers
  exist; concurrent production code should use child-process-specific environment configuration
- standard-input EOF remains distinct from a read error, and standard-stream failures use typed
  `haxe.io.Error.Custom(...)` payloads
- `Sys.cpuTime` is explicitly experimental and currently throws; it is not admitted until a real
  process CPU clock is validated on every admitted platform

Primary evidence:

- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.md`
- Tier1/Tier2 sweep coverage
- `test/semantic_diff/sys_core_failure_paths`
- `npm run test:portable-sys-failures`

## Targeted parity plus smoke-backed today

### `sys.Http`

Current posture:

- supported in the portable lane
- current proof depth is targeted parity for the callback/status/error boundary plus snapshot/smoke
  coverage for request assembly behavior

Primary evidence:

- `test/semantic_diff/sys_http_callback_contract`
- `test/snapshot/sys_http_smoke`
- `test/snapshot/http_base_override_contract`
- Tier1/Tier2 sweeps
- `docs/feature-support-matrix.md`

Interpretation rule:

- this is enough to say the surface is supported,
- the current proof now covers:
  - local-server status + body callback behavior,
  - local connection-failure routing through `onError(...)`,
  - request assembly/response handling,
  - and the callback-hook override contract,
- it is not enough to claim blanket host/network semantic parity.

### `sys.ssl.*`

Current posture:

- supported in the portable lane
- current proof depth is snapshot/smoke, especially around SNI behavior

Primary evidence:

- `test/snapshot/sys_ssl_sni`
- Tier1/Tier2 sweeps
- `docs/feature-support-matrix.md`

Interpretation rule:

- TLS/SNI support is real,
- the current proof locks the generated/buildable Rust path for SNI certificate selection,
- but TLS behavior remains platform- and environment-sensitive and should stay qualified as such.

## Environment-sensitive today

### `sys.db.*`

Current posture:

- supported as a Rust-target portable systems surface
- confidence is split between runtime smoke and compile-only dependency/codegen coverage
- still depends on native libraries and destination environment

Primary evidence:

- `test/snapshot/sys_db_mysql_compile`
- `test/snapshot/sys_db_sqlite_smoke`
- Tier2 sweep coverage
- `docs/feature-support-matrix.md`

Interpretation rule:

- `test/snapshot/sys_db_sqlite_smoke` is the runtime-backed smoke path and uses SQLite `:memory:` to
  prove the row/result contract without requiring an external service,
- `test/snapshot/sys_db_mysql_compile` is compile-only proof for MySQL dependency/codegen coverage,
- do not translate DB smoke proof into blanket host-independent parity,
- keep native-library/service prerequisites explicit.

### Windows and other platform-sensitive proof

Current posture:

- Linux remains the primary full CI environment
- Windows confidence is real, but it is still a curated smoke subset

Primary evidence:

- `bash scripts/ci/windows-smoke.sh`
- `.github/workflows/ci.yml`
- `.github/workflows/weekly-ci-evidence.yml`
- `docs/semantic-confidence-summary.md`

Interpretation rule:

- say `Linux CI + Windows smoke` when speaking publicly,
- do not imply blanket cross-platform semantic closure from the smoke subset alone.

## How to read the current contract

Use these practical rules:

1. `sys.Http`, `sys.ssl.*`, and `sys.db.*` are supported surfaces on the Rust target.
2. Their proof depth is not identical:
   - `sys.Http` combines targeted local-server callback/status/error proof with smoke-backed request
     assembly coverage,
   - `sys.ssl.*` is currently snapshot/smoke-backed,
   - `sys.db.*` is explicitly environment-sensitive,
   - Windows remains a smoke-confidence platform lane.
3. Stronger future claims for these surfaces require stronger artifacts, not just stronger prose.
4. Until then, production language should stay explicit about targeted/smoke and
   environment-sensitive proof depth.

## What this page does not claim

This page does **not** claim:

- blanket host-independent parity for all `sys.Http` behavior,
- blanket TLS parity for all certificates/platforms,
- blanket DB portability without native-library or service prerequisites,
- or blanket Windows semantic closure.

## Read next

- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.md`
- `docs/production-readiness.md`
- `docs/sys-regression-watchlist.md`
- `docs/semver-release-posture.md`
