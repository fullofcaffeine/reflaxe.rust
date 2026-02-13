# Production Readiness Guide

This guide helps non-compiler specialists decide when and how to adopt `reflaxe.rust` in production.

## What "production-ready" means here

For this project, production-ready means:

- critical stdlib/sys parity requirements are met,
- CI-style validation is consistently green,
- profile behavior is documented and predictable,
- interop boundaries are typed and auditable.

## Recommended rollout stages

### Stage 1: Pilot (single service or internal tool)

- Choose profile: `portable` or `idiomatic` unless Rust-first APIs are required.
- Keep interop typed (`extern` + metadata) and avoid app-level `__rust__`.
- Run `npm run test:all` on each change set.

### Stage 2: Controlled production

- Pin toolchain and Cargo lockfiles.
- Add explicit build defines in CI (`rust_cargo_locked`, target triple if required).
- Validate runtime paths for file, process, net, and thread behavior your app uses.

### Stage 3: Broad production rollout

- Confirm the release-readiness checklist is fully closed.
- Document team profile policy (who can use `rusty`, when).
- Add periodic regression runs against representative workloads.

## Operational checklist

1. Build reproducibility
   - Pin dependencies and use locked Cargo mode in CI.
2. Profile policy
   - Decide default profile (`portable`/`idiomatic`) and explicit exception process for `rusty`.
3. Boundary hygiene
   - Keep low-level Rust behind typed wrappers.
4. Failure behavior
   - Ensure expected IO/process/network failures are catchable and tested.
5. Change control
   - Tie release decisions to documented readiness criteria plus green CI evidence.

## Choosing conservative defaults

For teams new to this compiler:

- Profile: `portable` (or `idiomatic` if you care about output cleanliness).
- Build: default Cargo build + `rust_cargo_locked` in CI.
- Interop: typed externs and metadata first.
- Escape hatch: framework-only.

## What can still move after 1.0

- Minor ergonomics and docs can still change.
- Some low-level runtime/internal APIs may continue to evolve.
- Confidence windows depend on sustained regression-free validation.

## Source of truth links

- `docs/progress-tracker.md`
- `docs/vision-vs-implementation.md`
- `docs/v1.md`
- `docs/defines-reference.md`
- `docs/road-to-1.0.md`
- `docs/release-gate-closeout.md`
