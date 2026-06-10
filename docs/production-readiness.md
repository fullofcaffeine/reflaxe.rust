# Production Readiness Guide

This guide helps non-compiler specialists decide when and how to adopt `reflaxe.rust` in production.

## What "production-ready" means here

For this project, production-ready means:

- critical stdlib/sys parity requirements are met,
- CI-style validation is consistently green,
- profile behavior is documented and predictable,
- interop boundaries are typed and auditable.

It does not mean every upstream Haxe/std/sys behavior has blanket runtime parity on every host. The
honest production claim is bounded by the support matrix, semantic-confidence evidence, and the
runtime paths your application actually uses.

## Quick answer

Use `reflaxe.rust` in production when all of these are true:

- your app fits the documented supported surface,
- your team can run the local/CI harness for changes that affect compiler/runtime behavior,
- your app has smoke tests for its own file/process/network/TLS/DB/thread paths,
- native Rust interop is behind typed wrappers,
- `metal` is used deliberately instead of as a default escape hatch.

If those are not true yet, treat adoption as a pilot rather than broad rollout.

## Recommended rollout stages

### Stage 1: Pilot (single service or internal tool)

- Choose profile: `portable` by default; use `metal` only for Rust-first/performance-critical paths.
- Keep interop typed (`extern` + metadata) and avoid app-level `__rust__`.
- Run `npm run test:all` on each change set.

### Stage 2: Controlled production

- Pin toolchain and Cargo lockfiles.
- Add explicit build defines in CI (`rust_cargo_locked`, target triple if required).
- Validate runtime paths for file, process, net, and thread behavior your app uses.

### Stage 3: Broad production rollout

- Confirm the current public release posture in `docs/semver-release-posture.md` matches the rollout you intend to adopt.
- Document team profile policy (when metal is required vs portable).
- Add periodic regression runs against representative workloads.

## Operational checklist

1. Build reproducibility
   - Pin dependencies and use locked Cargo mode in CI.
2. Profile policy
   - Decide default profile (`portable`) and explicit exception process for `metal`.
3. Boundary hygiene
   - Keep low-level Rust behind typed wrappers.
4. Failure behavior
   - Ensure expected IO/process/network failures are catchable and tested.
5. Change control
   - Tie release decisions to documented readiness criteria plus green CI evidence.

## App-specific validation checklist

For each production app, add focused tests for the runtime edges it actually relies on:

- File and path behavior: permissions, missing files, relative paths, temp dirs.
- Process behavior: exit codes, stderr/stdout capture, kill/error paths.
- Network behavior: connection refused, timeouts, local loopback success/failure.
- TLS/HTTP behavior: certificate setup, request/response callbacks, error routing.
- DB behavior: driver availability, connection failure, transaction rollback.
- Threading behavior: message passing, event-loop scheduling, shutdown/cleanup.

This is intentionally narrower than "prove the whole stdlib." It turns the broad support matrix into
evidence for your real deployment shape.

## Choosing conservative defaults

For teams new to this compiler:

- Profile: `portable`.
- Build: default Cargo build + `rust_cargo_locked` in CI.
- Interop: typed externs and metadata first.
- Escape hatch: framework-only.

## What can still move after 1.0

- Minor ergonomics and docs can still change.
- Some low-level runtime/internal APIs may continue to evolve.
- Confidence windows depend on sustained regression-free validation.

## Source of truth links

Current operational sources:

- [Semver and release posture](semver-release-posture.md)
- [Systems and environment posture](systems-environment-posture.md)
- [Progress tracker](progress-tracker.md)
- [Vision vs implementation](vision-vs-implementation.md)
- [Portable near-native guidance](portable-near-native-guidance.md)
- [v1 support matrix](v1.md)
- [Feature support matrix](feature-support-matrix.md)
- [Semantic confidence summary](semantic-confidence-summary.md)
- [Defines reference](defines-reference.md)
- [Weekly CI Evidence](weekly-ci-evidence.md)

Historical closeout context:

- [GA decision record](ga-decision-record.md)
- [GA caveat classification](ga-caveat-classification.md)
- [Road to 1.0](road-to-1.0.md)
- [Release gate closeout](release-gate-closeout.md)
