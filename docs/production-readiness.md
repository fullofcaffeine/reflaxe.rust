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

Independent review disposition (2026-07-13): **ready with bounded scope for controlled production;
not ready for a stable `1.x` compatibility promise**. See the
[production-readiness audit disposition](production-readiness-audit-2026-07-13.md) for the verified
findings and dependency-ordered follow-up.

Use `reflaxe.rust` in production when all of these are true:

- your app fits the documented supported surface,
- your team can run the local/CI harness for changes that affect compiler/runtime behavior,
- your app has smoke tests for its own file/process/network/TLS/DB/thread paths,
- native Rust interop is behind typed wrappers,
- `metal` is used deliberately instead of as a default escape hatch.

Until the audit follow-up lands, do not treat broad dynamic `Type.*` reflection, useful native
`CallStack` contents, same-handle native lock callback reentry, unproven async cancellation/shutdown,
or untested normal OS-failure paths as production-stable behavior. Long-lived strong `HxRef` cycles
must be avoided or explicitly broken.

If those are not true yet, treat adoption as a pilot rather than broad rollout.

## Recommended rollout stages

### Stage 1: Pilot (single service or internal tool)

- Choose profile: `portable` by default; use `metal` only for Rust-first/performance-critical paths.
- Keep interop typed (`extern` + metadata) and avoid app-level `__rust__`.
- Run `npm run test:all` on each change set.

### Stage 2: Controlled production

- Use the supported Rust floor and repository/release pin from
  [Rust Toolchain Policy](rust-toolchain-policy.md), and commit Cargo lockfiles.
- Add explicit build defines in CI (`rust_cargo_locked`, target triple if required).
- Validate runtime paths for file, process, net, and thread behavior your app uses.

### Stage 3: Broad production rollout

- Confirm the current public release posture in `docs/semver-release-posture.md` matches the rollout you intend to adopt.
- Document team profile policy (when metal is required vs portable).
- Add periodic regression runs against representative workloads. For this compiler repo,
  `codex-hxrust` remains an independent consumer compatibility check on the weekly evidence cadence;
  compiler-owned runtime assertions stay in this repository's E2E suite.

## Operational checklist

1. Build reproducibility
   - Pin dependencies and use locked Cargo mode in CI.
2. Profile policy
   - Decide default profile (`portable`) and explicit exception process for `metal`.
3. Boundary hygiene
   - Keep low-level Rust behind typed wrappers.
4. Failure behavior
   - Ensure expected IO/process/network failures are catchable and tested. The compiler-owned
     portable `Sys` gate proves invalid cwd, missing direct executables, broken stdout, and the
     stdin error-versus-EOF boundary; application-specific file/network/process cases remain the
     adopter's responsibility.
   - Do not use `Sys.cpuTime` for production measurements yet. It is explicitly experimental and
     throws until a real process CPU clock is validated on the admitted platforms.
   - Treat `Sys.putEnv` as startup-only experimental behavior on non-Windows. Once a process may be
     concurrent, configure child environments through process-specific APIs instead of mutating the
     process-global environment.
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

## Independent Consumer Compatibility

`../codex-hxrust` is an independent application and a useful consumer pressure test for production
Rust output. Its normal build should keep compiling through this compiler in both portable and metal
lanes. It is not a compiler-owned fixture and should not receive haxe.rust-specific scenarios or
assertions merely to deepen this repository's evidence.

Run it locally with:

```bash
npm run test:codex-hxrust
```

The command expects a sibling checkout at `../codex-hxrust` and skips when that app is absent. The
weekly evidence workflow clones `https://github.com/fullofcaffeine/codex-hxrust` beside this repo
and runs the same command as scheduled QA.

What the gate does today:

- regenerates the full `codex-hxrust` portable Cargo project from Haxe,
- verifies the generated `Cargo.toml` and `Cargo.lock` exist,
- runs `cargo check --locked` for the portable generated crate,
- runs `cargo test --locked` for the portable generated crate,
- repeats the same regeneration, Cargo artifact checks, `cargo check`, and `cargo test` for metal.

`cargo test` is a real Rust test-harness invocation, but it only performs runtime testing to the
extent that `codex-hxrust` independently defines application tests. If it has no generated tests,
this still proves Haxe-to-Rust codegen, Cargo dependency resolution, Rust type checking, linking,
and test-harness construction for both profiles; it does not prove interactive Codex behavior.

Compiler-owned runtime proof is separate:

- `examples/profile_storyboard` compiles the same typed scenario under portable and metal profiles,
- both generated crates execute four named `@:rustTest` assertions,
- `required-rust-tests.txt` plus the harness verifier prevents silent regression to zero tests,
- compiler lowering/output-shape defects receive focused fixtures in this repository.

Local cadence: run this QA after important complex tasks or milestones that touch compiler lowering,
runtime behavior, std overrides, profile policy, report schemas, generated Rust shape, or
metal/portable semantics. It is optional for small docs-only or mechanical edits, but skipped runs
should be called out when the task otherwise changes compiler behavior.

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
- [Pre-1.0 Compatibility Review](pre-1.0-compatibility-review.md)
- [2026-07-13 Production-readiness Audit Disposition](production-readiness-audit-2026-07-13.md)

Historical closeout context:

- [GA decision record](ga-decision-record.md)
- [GA caveat classification](ga-caveat-classification.md)
- [Road to 1.0](road-to-1.0.md)
- [Release gate closeout](release-gate-closeout.md)
