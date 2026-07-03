# Metal Capability Fixture Plan

This document is the contract-first fixture plan for `haxe.rust-oo3.74` ("Metal as haxified Rust").

It exists so metal compiler work starts from explicit positive and negative contracts rather than
from ad hoc lowering changes.

## Rules

- Add or update the fixture before changing compiler/runtime behavior.
- Keep fixture names product-neutral.
- Prefer typed Haxe source and typed Rust-facing APIs over raw snippets.
- Add both positive and negative cases when a capability can fail by silently escaping the metal contract.
- Every metal-clean output-shape claim needs a generated Rust audit surface: snapshot diff, report artifact, rustfmt/warning gate, fallback baseline, or no-hxrt guard.
- If a fixture requires temporary fallback, record that fallback in the fixture name, hxml, or policy baseline. Do not let fallback look metal-clean.

## Existing Harness Owners

| Harness | Owns |
| --- | --- |
| `test/run-snapshots.sh` | Generated Rust shape, rustfmt, cargo build, targeted stdout snapshots. |
| `scripts/ci/check-metal-policy.sh` | Negative metal policy diagnostics, profile reports, contract reports, report determinism. |
| `scripts/ci/check-metal-fallback-counts.sh` | Deterministic ERaw fallback counts for curated metal examples/snapshots. |
| `test/negative/**` | Compile-time rejections for raw Rust, Dynamic/reflection, no-hxrt misuse, borrow capture, and metal islands. |
| `test/positive/**` | Small positive compile contracts, especially no-hxrt and strict profile checks. |
| `test/semantic_diff/**` | Runtime parity where Haxe interp is a valid oracle. This is usually secondary for Rust-native metal APIs. |
| `examples/**` | End-to-end Rust-first app surfaces and `@:rustTest`-backed native test suites. |

## Capability Matrix

| Capability area | Existing evidence | Missing contract-first fixtures | Gate owner |
| --- | --- | --- | --- |
| Scoped borrows and slices | `test/snapshot/rust_vec`, `test/snapshot/borrow_scope_tightening`, `test/negative/send_sync_borrow_capture` | `test/negative/metal_ref_escape`, `test/negative/metal_mut_ref_alias_escape`, `test/snapshot/metal_slice_view_no_clone` | snapshot + negative policy |
| Traits, impls, and bounds | generic/interface snapshots and open bounds gaps | `test/snapshot/metal_trait_impl_bounds`, `test/negative/metal_trait_bound_missing`, `test/snapshot/metal_trait_object_boundary` | snapshot + cargo build |
| Typed mini-DSL authority | `test/snapshot/metal_typed_injection`, raw app-side negative fixtures | `test/snapshot/metal_typed_dsl_contract`, `test/negative/metal_stringly_dsl_app_api`, `test/negative/metal_dsl_bypasses_policy` | snapshot + metal policy |
| Extern and lifetime islands | `@:native`, `@:rustCargo`, `@:rustExtraSrc` examples and interop docs | `test/snapshot/metal_extern_lifetime_island`, `test/negative/metal_extern_unsafe_surface`, cookbook example with cargo test | snapshot + example smoke |
| no-hxrt minimal runtime | `test/positive/metal_no_hxrt_minimal`, `test/negative/metal_no_hxrt_runtime_boundary`, `test/negative/metal_no_hxrt_requires_metal` | `test/snapshot/metal_no_hxrt_option_result_values`, `test/negative/metal_no_hxrt_dynamic_boundary` | positive/negative + cargo check |
| Dynamic/reflection boundaries | `test/negative/metal_dynamic_access`, `test/negative/metal_reflect`, `test/negative/metal_type_reflection` | `test/negative/metal_dynamic_dsl_payload`, `test/negative/metal_reflect_trait_boundary` | metal policy |
| Metal islands in portable builds | `test/negative/metal_island_*`, contract report cases | `test/snapshot/portable_with_metal_trait_island`, `test/negative/metal_island_lifetime_escape` | metal policy + contract report |
| Idiomatic output shape | fallback baseline, rustfmt/cargo build in snapshots | `test/snapshot/metal_idiom_values`, `test/snapshot/metal_idiom_option_result_vec`, deterministic clone/borrow/hxrt counters | snapshot + fallback baseline |
| Portable facades with metal-backed Rust lowering | `test/snapshot/reflaxe_std_option_result`, `test/snapshot/rust_reflaxe_std_adapters`, `docs/reflaxe-std-adoption-contract.md` | `test/snapshot/portable_facade_native_option_result_vec`, `test/positive/portable_facade_no_hxrt_subset`, `test/negative/portable_facade_no_hxrt_dynamic_fallback`, fallback-reason report fixture | snapshot + no-hxrt + contract report |

## First Wave

Implement these before broad compiler work in the milestone:

1. `test/negative/metal_ref_escape`
   - Proves `rust.Ref<T>` / `rust.Slice<T>` cannot escape their lexical region in metal-clean code.
   - Expected owner: `scripts/ci/check-metal-policy.sh`.

2. `test/snapshot/metal_trait_impl_bounds`
   - Proves one Haxe-facing trait/impl/bound shape lowers to warning-clean Rust.
   - Expected owner: `test/run-snapshots.sh`.

3. `test/negative/metal_stringly_dsl_app_api`
   - Proves app-level stringly Rust DSLs do not bypass typed `rust.metal` authority policy.
   - Expected owner: `scripts/ci/check-metal-policy.sh`.

4. `test/snapshot/metal_extern_lifetime_island`
   - Proves a lifetime-heavy Rust helper can sit in a handwritten Rust module behind a typed Haxe facade.
   - Expected owner: `test/run-snapshots.sh` plus a narrow example/cargo test if runtime behavior matters.

5. `test/snapshot/metal_idiom_option_result_vec`
   - Proves native `Option`, `Result`, and `Vec` shapes stay readable, rustfmt-clean, and free of avoidable hxrt/Dynamic/raw fallback.
   - Expected owner: `test/run-snapshots.sh` and `scripts/ci/check-metal-fallback-counts.sh`.

Later portable-facade work should add:

- `test/snapshot/portable_facade_native_option_result_vec`
  - Proves portable-shaped facade source lowers to native Rust `Option`, `Result`, and `Vec` on the Rust target.
- `test/positive/portable_facade_no_hxrt_subset`
  - Proves the facade subset can compile with `rust_no_hxrt` when no Haxe runtime semantics are required.
- `test/negative/portable_facade_no_hxrt_dynamic_fallback`
  - Proves unsupported portable semantics fail under `rust_no_hxrt` with a diagnostic that names the runtime fallback reason.
- A deterministic fallback-reason report fixture.
  - Proves every `hxrt` dependency introduced by facade lowering is explained by source semantics rather than hidden convenience.

## Failure Policy

- New negative fixtures must fail before implementation unless they document an already-existing rejection.
- Positive snapshots may start as compile-only contracts, but they must still run through rustfmt and cargo build.
- A metal-clean fixture must not pass by enabling `rust_metal_allow_fallback` unless the fixture name and acceptance text explicitly make fallback the behavior under test.
- Increases in ERaw fallback counts, generated hxrt use in no-hxrt fixtures, Dynamic usage, or borrow-guard bloat are regressions unless the owning bead updates a deterministic baseline with rationale.
- Runtime semantic-diff is required only when Haxe interp is a valid oracle. Rust-native ownership, borrow, no-hxrt, and extern-island contracts should prefer generated Rust shape plus cargo/rustfmt/policy gates.

## Beads Mapping

| Bead | Fixture responsibility |
| --- | --- |
| `haxe.rust-oo3.74.2` | Borrow/lifetime positive and negative fixtures. |
| `haxe.rust-oo3.74.3` | Trait, impl, where-bound, associated-type, and trait-object fixtures. |
| `haxe.rust-oo3.74.4` | Type-surface gap matrix and fixture coverage status per type. |
| `haxe.rust-oo3.74.5` | Typed DSL positive and negative fixtures. |
| `haxe.rust-oo3.74.6` | Idiomatic-output gates and deterministic fail/baseline thresholds. |
| `haxe.rust-oo3.74.7` | Extern/lifetime-island cookbook fixture and example. |
| `haxe.rust-oo3.74.9` | Portable facade, metal-backed Rust lowering, no-hxrt eligibility, and fallback-reason fixtures. |

## Closeout Checklist For New Metal Capability Fixtures

- Fixture source is typed Haxe unless the boundary under test is explicitly a framework/native facade.
- The hxml states the intended contract: `portable`, `metal`, `@:haxeMetal`, `rust_no_hxrt`, fallback allowed, or fallback forbidden.
- Diagnostics anchor to project source for negative cases where possible.
- Generated Rust is inspected for ownership, allocation, module paths, `Dynamic`, `hxrt`, raw `ERaw`, clone noise, and borrow-guard scope.
- The owning script runs locally and is wired to the relevant aggregate guard before the bead closes.
