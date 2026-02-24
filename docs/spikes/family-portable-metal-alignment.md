# Spike: Family `portable|metal` Alignment (Rust)

Date: 2026-02-24  
Scope bead: `haxe.rust-8z8`

## Inputs

- `../haxe.go/docs/portable-canonical-contract.md`
- `../haxe.go/docs/phase2-roadmap.md`
- `../haxe.go/docs/hxrt-selective-runtime.md`
- `src/reflaxe/rust/ProfileResolver.hx`
- `src/reflaxe/rust/analyze/HxrtFeatureAnalyzer.hx`
- `src/reflaxe/rust/emit/ProjectEmitter.hx`
- `src/reflaxe/rust/passes/NoHxrtPass.hx`
- `docs/profiles.md`
- `docs/metal-profile.md`

## Current State

Rust already matches the family direction on the core contract:

- Public profiles are hard-cut to `portable|metal` only.
- Removed profile aliases fail fast with explicit diagnostics.
- `portable` is semantics-first, `metal` is strict/performance-first.
- Selective `hxrt` feature slicing exists and is orthogonal to profile choice.
- `metal` already has typed fallback visibility (`rust_metal_allow_fallback`) and deterministic viability artifacts.
- `rust_no_hxrt` has a hard AST-level boundary pass (`NoHxrtPass`) plus define conflict guards.

## Gap Matrix

| Area | Family expectation | Rust current state | Gap | Priority |
| --- | --- | --- | --- | --- |
| Profile report artifact | Deterministic compile artifact that records effective profile contract | Diagnostics exist, but no emitted profile contract artifact | Missing machine-readable contract output for CI diffing | P4 |
| Runtime plan artifact | Deterministic runtime plan (selected features + why) | Features are inferred/selected deterministically, but not emitted as an artifact | Missing explainability/debug artifact for selective runtime decisions | P4 |
| Feature reason trace | Runtime plan should explain inferred vs manual/default decisions | `HxrtFeatureAnalyzer` computes features but does not expose reason mapping | Missing per-feature provenance for audit/debug | P4 |
| Family-level contract test shape | Cross-target contract gates should be explicit and easy to compare | Rust has strong harness coverage, but no dedicated family-contract snapshot/report checks | Missing direct parity lane for cross-repo comparison | P4 |
| Docs cross-link parity | Family docs should point to canonical contract + target-specific deviations | Rust docs describe behavior well; family alignment is implicit | Missing explicit alignment doc in repo docs tree | P4 |

## Proposed Artifact Contracts (Rust)

### 1) Profile Contract Report

Proposed opt-in define: `-D rust_profile_contract_report`

Output files in generated crate root:

- `profile_contract.json`
- `profile_contract.md`

Minimum JSON fields:

- `schemaVersion`
- `profile` (`portable|metal`)
- `strictBoundary` (bool)
- `metalFallbackAllowed` (bool)
- `noHxrt` (bool)
- `asyncEnabled` (bool)
- `nullableStrings` (bool)
- `contractWarnings[]`
- `contractErrors[]`

Goal: make policy drift visible in CI without scraping compiler stderr.

### 2) Runtime Plan Report

Proposed opt-in define: `-D rust_hxrt_plan_report`

Output files in generated crate root:

- `hxrt_plan.json`
- `hxrt_plan.md`

Minimum JSON fields:

- `schemaVersion`
- `mode` (`no_hxrt|default_features|selective`)
- `selectedFeatures[]`
- `manualFeatures[]`
- `inferenceDisabled` (bool)
- `reasons[]` with entries `{feature, sourceKind, source}`
  - `sourceKind` examples: `module`, `define`, `dependency_edge`

Goal: deterministic and reviewable runtime feature planning.

## Minimal Migration Tasks

1. Add typed planning output model for profile contract and runtime plan (shared serializer helpers, deterministic ordering).
2. Extend `ProjectEmitter.selectHxrtFeatures(...)` / analyzer pipeline to return feature provenance metadata (not only names).
3. Emit opt-in `profile_contract.*` and `hxrt_plan.*` artifacts in generated crate root.
4. Add dedicated harness checks for deterministic artifact content and key-field presence.
5. Link this spike from docs navigation and call out current known deviations explicitly.

## Risks

- Over-reporting noise: artifacts must stay opt-in and deterministic.
- Schema churn: lock `schemaVersion` and add additive-only changes.
- Drift risk: avoid duplicated logic by reusing existing analyzers/passes instead of recomputing policy in emit-only code.
- CI cost: artifact checks should be targeted fixture tests, not full-matrix heavy steps.

## Follow-up Beads

Created from this matrix:

- `haxe.rust-t8e` - emit `profile_contract.json|md` artifacts.
- `haxe.rust-xth` - emit `hxrt_plan.json|md` runtime-plan artifacts.
- `haxe.rust-14g` - add typed hxrt feature provenance mapping.
- `haxe.rust-bzq` - add targeted fixture checks for report determinism/shape.
- `haxe.rust-in3` - publish docs navigation links + explicit deviation notes.

## Deviation Notes (Rust vs Family Contract)

As of 2026-02-24, there are no unresolved Rust-vs-family contract deviations from this spike:

| Area | Expected family state | Rust state | Owner | Status |
| --- | --- | --- | --- | --- |
| Profile contract reports | Deterministic `profile_contract.{json,md}` artifacts | Implemented (`haxe.rust-t8e`) | `@fullofcaffeine` | closed |
| Runtime plan reports | Deterministic `hxrt_plan.{json,md}` artifacts | Implemented (`haxe.rust-xth`) | `@fullofcaffeine` | closed |
| Feature provenance | Typed per-feature reason mapping | Implemented (`haxe.rust-14g`) | `@fullofcaffeine` | closed |
| Family fixture checks | Deterministic report-shape CI coverage | Implemented (`haxe.rust-bzq`) | `@fullofcaffeine` | closed |
| Docs navigation parity | Family spike linked from docs index with explicit status | Implemented (`haxe.rust-in3`) | `@fullofcaffeine` | closed |
