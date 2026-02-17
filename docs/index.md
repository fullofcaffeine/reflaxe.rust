# Documentation Index

Use this page as the map for `reflaxe.rust` docs.

## Quick start by audience

- New to compiler internals: [Start Here](start-here.md)
- Need a fast local rebuild loop: [Dev Watcher](dev-watcher.md)
- Building async Rust-first apps: [Async/Await preview](async-await.md)
- Planning production rollout: [Production Readiness](production-readiness.md)
- Planning release closeout: [Road to 1.0](road-to-1.0.md)
- Running post-1.0 weekly operations: [Weekly CI Evidence](weekly-ci-evidence.md)
- Tracking cross-platform sys risk: [Sys Regression Watchlist](sys-regression-watchlist.md)
- Using the release-gate template: [Release Gate Closeout](release-gate-closeout.md)
- Tracking 1.0 status: [Progress Tracker](progress-tracker.md)
- Checking vision vs reality: [Vision vs Implementation](vision-vs-implementation.md)

## Core product docs

- [Profiles](profiles.md): portable vs idiomatic vs rusty vs metal, and when to choose each.
- [Examples matrix](examples-matrix.md): scenario coverage and profile-by-profile example entrypoints.
- [Metal profile](metal-profile.md): experimental Rust-first+ profile with typed low-level interop façade.
- [Lifetime encoding design](lifetime-encoding.md): what lifetime-like guarantees are possible in Haxe and where extern Rust is still required.
- [Async/Await preview](async-await.md): Rust-first async workflow and current constraints.
- [Defines reference](defines-reference.md): practical `-D` reference for build/profile/CI knobs.
- [v1 support matrix](v1.md): technical support matrix and parity constraints.
- [Workflow](workflow.md): Haxe -> Rust -> Cargo workflow.
- [Dynamic boundaries](dynamic-boundaries.md): intentional untyped boundaries and allowlist policy.
- [Weekly CI Evidence](weekly-ci-evidence.md): post-1.0 validation cadence and evidence protocol.
- [Sys Regression Watchlist](sys-regression-watchlist.md): active cross-platform sys risk tracking.
- [Dev Watcher](dev-watcher.md): local edit-compile-run watch loop.
- [Install via lix](install-via-lix.md): toolchain setup.

## Rust interop and runtime

- [Interop](interop.md): externs, metadata-driven Cargo deps, extra Rust modules, and escape hatch policy.
- [Rusty profile](rusty-profile.md): Rust-first authoring model details.
- [Metal profile](metal-profile.md): Rust-first+ authoring model and boundary policy.
- [Lifetime encoding design](lifetime-encoding.md): borrow/lifetime modeling constraints and roadmap.
- [Threading](threading.md): threading model and runtime guarantees.
- [TUI](tui.md): deterministic TUI testing approach.

## Language and codegen deep dives

- [Array](array.md)
- [Generics](generics.md)
- [Abstracts and casts](abstracts-and-casts.md)
- [Function values](function-values.md)
- [Lambda](lambda.md)
- [Null option](null-option.md)
- [Operators](operators.md)

## Release and governance

- [Release](release.md): semantic-release flow and release artifacts.
- [Haxelib Packaging Notes](haxelib-packaging.md): package layout rules, flattening behavior, and `.cross.hx` rationale.
