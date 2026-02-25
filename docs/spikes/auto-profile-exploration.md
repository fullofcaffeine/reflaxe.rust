# Spike: Auto Profile Exploration (`portable|metal` vs `auto`)

Date: 2026-02-24  
Scope bead: `haxe.rust-rir`

## Decision

`KEEP_TWO_PROFILES`:

- Keep explicit `portable` and `metal` as first-class semantic contracts.
- Do not replace them with inferred behavior.
- If an `auto` mode is explored later, keep it explicit opt-in and non-semantic by default.

## Why

This is a semantic boundary problem, not only an optimization toggle:

- `portable` vs `metal` affects contract rules (strict boundary, reflection/dynamic policy, string nullability defaults, `rust_no_hxrt` eligibility).
- Inferred global mode changes create unstable behavior across edits/dependency churn.
- CI/snapshot workflows are easier to reason about when contract selection is explicit and reviewable.

## Local Evidence (repo)

- Profile contract is explicit and hard-cut in `src/reflaxe/rust/ProfileResolver.hx`.
- Define compatibility gates are profile-aware in `src/reflaxe/rust/CompilerInit.hx`.
- Metal contract analysis is explicit in `src/reflaxe/rust/analyze/ProfileContractAnalyzer.hx`.
- Runtime feature inference is additive and typed in `src/reflaxe/rust/analyze/HxrtFeatureAnalyzer.hx`.
- Runtime plan selection and deterministic feature ordering are in `src/reflaxe/rust/emit/ProjectEmitter.hx`.
- `@:haxeMetal` islands (with `@:rustMetal` compatibility alias) are enforced in portable pass flow via
  `src/reflaxe/rust/passes/PassRunner.hx` plus `MetalRestrictionsPass`.

## External Decision Context

- Oracle reference thread:
  - https://chatgpt.com/g/g-p-69965383a564819188b44c7003bcc173-processed-oracle-queries/c/699d17bd-de6c-8324-a993-828df9a30b00

## Contract Boundary: What may be inferred vs must be explicit

Must stay explicit (contract-declared):

- semantic profile (`portable` or `metal`)
- strict app boundary policy
- dynamic/reflection allowances
- nullable string mode contract
- `rust_no_hxrt` contract

May be inferred (additive planning):

- `hxrt` feature slicing from used modules/defines
- dependency edges between runtime features
- report artifacts that explain selected runtime features

## If `auto` is explored later (constraints)

`auto` must be:

- explicit (`-D reflaxe_rust_profile=auto`), never silent
- deterministic (same input graph => same report and output)
- report-first (always emit resolved contract/runtime plan in artifacts)
- non-semantic by default (runtime/dependency planning only)

Hard boundaries for any `auto` experiment:

- no silent semantic flips
- no implicit downgrade of metal restrictions
- no hidden fallback enablement
- no profile shifts based on transitive dependency churn without explicit diagnostics

## Risk Register (top 5)

1. Hidden semantic drift if `auto` infers contract behavior.  
   Mitigation: keep contract selection explicit; keep inference additive only.

2. CI/snapshot instability from usage-driven global mode switching.  
   Mitigation: deterministic report artifacts and explicit profile selector in fixtures.

3. User confusion over effective behavior.  
   Mitigation: emit resolved profile/runtime plan artifacts and warnings when fallback is active.

4. Performance regressions masked by fallback paths.  
   Mitigation: maintain metal-clean default and explicit fallback opt-in (`rust_metal_allow_fallback`).

5. Documentation drift between contract and implementation.  
   Mitigation: tie profile contract docs to tested fixtures and update docs in the same PR as behavior changes.

## Recommended Next Steps

1. Keep shipping with `portable|metal` as the public contract.
2. Continue improving `metal` viability reporting and fallback reduction.
3. If `auto` spike is revisited, run as an explicit experimental profile with strict guardrails above, then evaluate via snapshots/perf deltas before any productization decision.
