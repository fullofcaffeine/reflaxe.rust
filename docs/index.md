# Documentation Index

Use this page as the map for `reflaxe.rust` docs.

## Quick start by audience

- New to compiler internals: [Start Here](start-here.md)
- Common first questions: [FAQ](faq.md)
- First generated app from this checkout: [Start Here](start-here.md#scaffold-a-new-app), [Workflow](workflow.md#new-project-scaffold--task-hxmls)
- Installing into an existing app: [Install via lix](install-via-lix.md), [Workflow](workflow.md)
- Evaluating production use: [Production Readiness](production-readiness.md), [Feature support matrix](feature-support-matrix.md), [Semantic confidence summary](semantic-confidence-summary.md)
- Portable-first application path: [Profiles](profiles.md), [Portable near-native guidance](portable-near-native-guidance.md), [Examples matrix](examples-matrix.md)
- Metal-first path: [Metal profile](metal-profile.md) for current contract policy, [Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md) for compiler/API direction, [Metal systems facades roadmap](metal-systems-facades-roadmap.md) for Rust-native file/process/socket/DB handle work, [Portable near-native guidance](portable-near-native-guidance.md), [Examples matrix](examples-matrix.md)
- Release / operations path: [Production Readiness](production-readiness.md), [Semver and release posture](semver-release-posture.md), [Weekly CI Evidence](weekly-ci-evidence.md)
- Need a fast local rebuild loop: [Dev Watcher](dev-watcher.md)
- Building async Rust-first apps: [Async/Await guide](async-await.md)
- Need the exact async contract: [Async Contract](async-contract.md)
- Tracking cross-platform sys risk: [Sys Regression Watchlist](sys-regression-watchlist.md)
- Tracking 1.0 status: [Progress Tracker](progress-tracker.md)
- Checking vision vs reality: [Vision vs Implementation](vision-vs-implementation.md)

## Core product docs

- [Contracts](profiles.md): portable vs metal contract semantics and lane/capability controls.
- [FAQ](faq.md): first-user answers about GC, memory management, generated Rust quality, runtime overhead, profile choice, and interop.
- [Portable idiom adoption contract](reflaxe-std-adoption-contract.md): Rust-side boundary and migration rules for the shared `reflaxe.std` portable idiom layer (v1 starts with `Option`/`Result`).
- [Semver and release posture](semver-release-posture.md): canonical public `1.x` release posture and packaging decision.
- [GA decision record](ga-decision-record.md): historical Milestone 28 gate outcome that led to the semver/public-packaging follow-up.
- [GA caveat classification](ga-caveat-classification.md): historical blocker/defer/non-issue input used by the Milestone 28 gate.
- [Examples matrix](examples-matrix.md): scenario coverage, profile entrypoints, and native-parity quick check (`profile_storyboard`).
- [Portable near-native guidance](portable-near-native-guidance.md): when portable can lower to native Rust representations/cost, when `metal` is still the right contract, and where `reflaxe.std` fits.
- [Portable vs metal authoring](portable-vs-metal-authoring.md): concise source-style guidance for performance-oriented users choosing between portable and metal.
- [Consumer runtime benchmark corpus](consumer-runtime-benchmark-corpus.md): product-neutral benchmark candidates for DTO/codecs, JSON/schema validation, process/tool shims, state transitions, async/runtime surfaces, and no-runtime lower-bound signals.
- [Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md): compiler/API plan for making `metal` a Rust-native authoring surface through Haxe constructs, typed metadata/macros, and constrained DSLs.
- [Metal systems facades roadmap](metal-systems-facades-roadmap.md): active plan for Rust-native file/process/socket/TLS/DB facades and no-hxrt proof.
- [Metal typed DSL authority](metal-typed-dsl-authority.md): rules for admitting typed DSLs and containing `rust.metal.Code`.
- [Metal trait, impl, and bound model](metal-trait-impl-bound-model.md): current trait-facing surfaces and missing typed Rust trait shapes.
- [Extern and lifetime-island cookbook](extern-lifetime-island-cookbook.md): typed facade pattern for Rust APIs with lifetimes, HRTB, const generics, macro setup, or contained unsafe internals.
- [RAII guard and lifetime-island rules](raii-guard-lifetime-islands.md): when to expose guards as scoped callbacks versus typed Rust islands.
- [Metal capability fixture plan](metal-capability-fixtures.md): contract-first positive/negative fixture matrix for the haxified Rust milestone.
- [Metal type surface gap matrix](metal-type-surface-gap-matrix.md): Rust-native type/facade support audit for metal and portable-facade lowering work.
- [Concurrency posture](concurrency-posture.md): canonical status record for async/threading, including what is stable, what is still narrow by contract, and what remains caveat-heavy.
- [Async contract](async-contract.md): canonical supported/unsupported contract for `-D rust_async`.
- [Systems and environment posture](systems-environment-posture.md): canonical status record for `sys.Http`, `sys.ssl.*`, `sys.db.*`, and platform-sensitive proof depth.
- [Metal profile](metal-profile.md): Rust-first performance profile and boundary policy.
- [Lifetime encoding design](lifetime-encoding.md): what lifetime-like guarantees are possible in Haxe and where extern Rust is still required.
- [Async/Await guide](async-await.md): Rust-first async workflow and current constraints.
- [Defines reference](defines-reference.md): practical `-D` reference for build/profile/CI knobs.
- [Feature support matrix](feature-support-matrix.md): evidence-backed portable/native/package support map.
- [Semantic confidence summary](semantic-confidence-summary.md): generated rollup separating compile coverage, targeted parity, and smoke-only buckets.
- [v1 support matrix](v1.md): release-scope contract and parity constraints.
- [HXRT overhead benchmarks](perf-hxrt-overhead.md): size/startup tracking, soft perf budgets, and baseline workflow.
- [JSON boundary contract](json-boundary-contract.md): perf/semantic contract for the current post-`1.0` JSON hotspot tranche.
- [Workflow](workflow.md): Haxe -> Rust -> Cargo workflow.
- [Install via lix](install-via-lix.md): release-tag install and generated-app setup paths.
- [Haxe-authored Rust tests](haxe-rust-tests.md): `@:rustTest` metadata and generated Rust test wrappers.
- [Dynamic boundaries](dynamic-boundaries.md): intentional untyped boundaries and allowlist policy.
- [Weekly CI Evidence](weekly-ci-evidence.md): ongoing validation cadence and evidence protocol.
- [Sys Regression Watchlist](sys-regression-watchlist.md): active cross-platform sys risk tracking.
- [Dev Watcher](dev-watcher.md): local edit-compile-run watch loop.

## Rust interop and runtime

- [Interop](interop.md): externs, metadata-driven Cargo deps, extra Rust modules, and escape hatch policy.
- [Extern and lifetime-island cookbook](extern-lifetime-island-cookbook.md): cookbook for small Rust implementation islands behind typed Haxe facades.
- [RAII guard and lifetime-island rules](raii-guard-lifetime-islands.md): scoped callback versus extern-island selection rules for locks, files, sockets, and other guard/drop APIs.
- [Profile migration guide](rusty-profile.md): migration mapping from removed `idiomatic`/`rusty` selectors.
- [Metal profile](metal-profile.md): Rust-first authoring and boundary policy.
- [Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md): long-range metal compiler/API plan and tracker sweep.
- [Metal systems facades roadmap](metal-systems-facades-roadmap.md): shipped file/path and owned-command/process-output/cwd/env set-remove-clear/cwd+env/stdin-input/stdin+cwd+env/command-spec/command-error slices for Rust-native systems handles distinct from portable `sys.*` semantics.
- [Metal typed DSL authority](metal-typed-dsl-authority.md): when a metal DSL is justified and how raw-code authority is contained.
- [Metal trait, impl, and bound model](metal-trait-impl-bound-model.md): `@:rustImpl`, `@:rustGeneric`, interface trait objects, and future typed trait metadata.
- [Metal capability fixture plan](metal-capability-fixtures.md): planned metal capability fixtures and owning harnesses.
- [Metal type surface gap matrix](metal-type-surface-gap-matrix.md): supported/partial/missing Rust-native type surfaces and follow-up owners.
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
- [Semver and release posture](semver-release-posture.md): public `1.x` posture and packaging truth.
- [Release Gate Closeout](release-gate-closeout.md): closeout template used by the historical release-gate work.
- [Haxelib Packaging Notes](haxelib-packaging.md): package layout rules, flattening behavior, and `.cross.hx` rationale.
- [Stdlib Parity Policy](stdlib-policy.md): parity scope, provenance ledger, and CI boundary governance.
- [Cross overrides and hardening](cross-overrides-and-hardening.md): `.cross.hx` ownership, sibling-target coexistence risk, and hardening notes.
- [Spike: Family `portable|metal` Alignment](spikes/family-portable-metal-alignment.md): cross-repo contract alignment notes and implementation gap history.
- [Spike: `reflaxe.std` Cross-Repo Handoff](spikes/reflaxe-std-cross-repo-handoff.md): ownership split between Rust adoption work and the remaining Go/Elixir/JS/genes rollout tasks.
- [Spike: Auto Profile Exploration](spikes/auto-profile-exploration.md): decision memo for keeping explicit `portable|metal` contracts and constraints for any future `auto` experiment.

## Historical release-gate records

- [Road to 1.0](road-to-1.0.md)
- [GA decision record](ga-decision-record.md)
- [GA caveat classification](ga-caveat-classification.md)
