# Metal Haxified Rust Roadmap

This document records the product direction for `metal` after the July 2, 2026 contract discussion.

Tracker anchor: `haxe.rust-oo3.74` ("Milestone 42 - Metal as haxified Rust").

## North Star

`metal` should be haxified Rust:

- Rust-native capability and semantics where the source contract asks for them.
- Haxe-native syntax, types, abstracts, enums, metadata, and macros where they can express the idea cleanly.
- Small typed DSLs only where Haxe has no good native construct.
- Handwritten Rust only behind typed extern/facade islands when Rust's lifetime/type language is too expressive to model directly in Haxe.
- Generated Rust that is readable, rustfmt-friendly, warning-clean, and close to what a Rust developer would write.

This is not "portable Haxe plus a few Rust APIs." It is the explicit Rust-native authoring lane.

## Capability-Driven Portable Facades

A later layer can support cross-target development without adding a third profile: portable-shaped
Haxe APIs whose Rust backend lowers through native Rust representations when the facade contract
permits it.

This is different from silently treating ordinary portable code as `metal`, and it is also different
from requiring users to draw a hard module boundary by hand. The compiler should resolve typed
consumption into explicit, reportable surface contracts:

- ordinary Haxe/std APIs keep the Haxe semantics they already promise,
- admitted `reflaxe.std` facade surfaces can have declared native Rust representation contracts,
- `rust.*` / `rust.metal.*` APIs are explicit Rust-native source contracts,
- `@:haxeMetal` marks strict Rust-native islands inside a portable build.

The source API stays cross-target and intentionally portable-shaped when the user chooses a facade.
The Rust implementation can still use metal internals: native `Option`/`Result`/`Vec`, typed
handles, scoped borrows, RAII guards, extern islands, and no/low-`hxrt` paths where semantics allow.
Other targets can use their own implementation of the same Haxe-facing API. Existing Haxe apps,
including JS-first codebases, can migrate by adopting the facade layer first and then letting the
Rust target specialize behind it.

The design constraint is explicitness: users should be able to tell from imports, metadata, and
report artifacts whether they are writing ordinary portable Haxe, Rust-native source, or a portable
API whose Rust backend has a native representation.

The implementation rule is compile-time specialization first:

- The compiler should recognize typed facade symbols, abstracts, metadata, and macros and lower them
  directly to native Rust where the facade contract permits it.
- Runtime support is a narrow semantic fallback, not the default implementation strategy.
- If `hxrt` is needed, the compiler/report should explain why: object identity, Haxe reference
  semantics, `Dynamic`, reflection, anonymous runtime objects, exceptions, shared mutable closure
  cells, nullable compatibility, or a platform abstraction that genuinely needs a shared helper.
- Today, `rust_no_hxrt` is metal-only. Future portable-facade no-runtime support requires a
  source/typed-AST eligibility pass before lowering, followed by the existing generated-code
  `NoHxrtPass` guard. Eligible facade code should compile, while unsupported semantics fail with
  actionable diagnostics instead of linking `hxrt` implicitly.

The implementation must not treat a namespace as admitted just because it is named `reflaxe.std`.
Admission is per symbol/module/version and should be represented in a compiler-readable
`SurfaceContract`-style registry. At minimum, each admitted facade needs a stable `surfaceId`, source
contract kind, facade version, portable semantics, Rust representation, no-hxrt eligibility, and
fallback policy.

## Non-Goals

- Do not claim Haxe can expose Rust's full lifetime syntax, HRTB model, const-generic surface, or macro system one-to-one.
- Do not normalize app-side `untyped __rust__` as the metal API.
- Do not accept stringly typed mini-DSLs that are raw Rust snippets in disguise.
- Do not silently change portable modules into native-lane modules to improve output shape.
- Do not treat `hxrt`, `Dynamic`, broad reflection, clone-heavy lowering, or raw fallback as acceptable final metal output when typed Rust-native alternatives are possible.

## Design Rules

1. Prefer real Haxe constructs first.
   - `abstract` / newtype-style APIs for Rust newtypes and transparent wrappers.
   - Haxe enums and enum abstracts for Rust enums, mode sets, and flag-like domains.
   - Interfaces and metadata for trait-facing surfaces when the mapping is explicit.
   - `typedef` schemas for boundary records rather than untyped maps.

2. Use metadata and macros for typed target contracts.
   - Examples: `@:native`, `@:rustCargo`, `@:rustExtraSrc`, `@:rustImpl`, `@:rustGeneric`.
   - New metadata must document Why / What / How and produce inspectable generated Rust.

3. Keep DSLs typed and narrow.
   - A DSL should produce compiler-owned structure or call a typed native facade.
   - A DSL should have negative fixtures and actionable diagnostics.
   - A DSL should not bypass profile, strict-boundary, or metal-island checks.

4. Keep raw Rust behind authority boundaries.
   - App/business code should not need direct `untyped __rust__`.
   - Framework/runtime code may use raw authority only where the typed surface is missing and the boundary is documented.
   - `rust.metal.Code` remains a controlled escape hatch, not the design center for application authoring.

5. Treat emitted Rust as a product artifact.
   - Metal output should be rustfmt-clean and warning-clean.
   - Native representations should be used when semantics match: admitted `Option`/`Result`
     facades, explicit Rust-native `Vec`, future admitted collection facades, references, slices,
     strings, paths, handles, and RAII-style guards.
   - Avoidable `hxrt`, `Dynamic`, raw `ERaw`, clone noise, and borrow-guard bloat are compiler/API gaps.

## Capability Map

| Rust concept | Preferred Haxe shape | Current direction |
| --- | --- | --- |
| Owned values | Concrete Haxe values / extern abstracts | Lower to owned Rust values where semantics permit. |
| Shared Haxe references | `HxRef<T>` runtime handle | Keep for portable Haxe reference semantics; avoid in metal-only value paths when owned Rust values fit. |
| Immutable borrow | `rust.Ref<T>`, scoped helpers | Expand non-escape checks and diagnostics. |
| Mutable borrow | `rust.MutRef<T>`, scoped helpers | Expand non-escape and alias checks before Rust compile. |
| Slices | `rust.Slice<T>`, `rust.MutSlice<T>` | Prefer callback-scoped slice APIs and no-clone Array/Vec views. |
| Options/results | `rust.Option`, `rust.Result`, `reflaxe.std` adapters | Keep native Rust representation; make portable/native crossings explicit. |
| Traits/impls | Interfaces, metadata, externs | Extend trait/bound/where/associated-type modeling. |
| Crates/modules | `@:rustCargo`, `@:rustExtraSrc`, extern facades | Keep Cargo and module ownership declarative and deterministic. |
| Lifetime-heavy APIs | Typed extern island | Handwrite Rust internals, expose small typed Haxe facade. |
| Unsafe Rust libraries | Safe wrapper facade | Contain `unsafe` in handwritten Rust with tests and HaxeDoc; do not expose raw unsafe app APIs. |

## Compiler Improvement Plan

### 1. Contract And Fixture Baseline

Bead: `haxe.rust-oo3.74.1`

- Specify metal as haxified Rust in public docs.
- Keep capability reach separate from syntax parity.
- Add examples showing Haxe constructs that intentionally lower to Rust-native shapes.
- Record the second-pass review requirement before closing the milestone.

### 2. Scoped Lifetime And Borrow Regions

Bead: `haxe.rust-oo3.74.2`

- Treat `Borrow.withRef`, `Borrow.withMut`, `SliceTools.with`, and `MutSliceTools.with` as the current lexical-region baseline.
- Add or design static non-escape checks for `Ref`, `MutRef`, `Slice`, and `MutSlice`.
- Evaluate phantom region types only where they improve diagnostics without making ordinary use painful.
- Extend Send/Sync diagnostics so spawned closures reject borrow-only captures before generated Rust fails.

### 3. Traits, Impl Blocks, And Generic Bounds

Bead: `haxe.rust-oo3.74.3`

- Audit `@:rustImpl`, `@:rustGeneric`, Haxe interfaces, externs, and abstract helpers.
- Define the next typed surface for where-clauses, marker traits, trait objects, associated types, and derived impls.
- Prefer typed metadata over raw impl body strings wherever the Rust shape is common and inspectable.
- Add regression fixtures that prove generic helper methods propagate required bounds cleanly.

### 4. Rust-Native Type Surface Audit

Bead: `haxe.rust-oo3.74.4`

- Build a gap matrix for `rust.*` and native/hxrt facades.
- Cover values, refs, slices, Vec/HashMap, Option/Result, strings, paths, OS strings, time, native handles, RAII guards, iterators, async tasks, and concurrency primitives.
- Mark each entry as supported, partial, or missing.
- For every partial/missing row, decide whether the fix belongs in compiler lowering, std facade, hxrt, or handwritten Rust extern support.
- Current audit: [Metal type surface gap matrix](metal-type-surface-gap-matrix.md).

### 5. Typed Mini-DSL Authority

Bead: `haxe.rust-oo3.74.5`

- Define when Haxe-native syntax is insufficient and a DSL is justified.
- Require typed inputs/outputs, diagnostics, and generated-Rust shape tests.
- Replace common raw snippets with typed helpers or constrained DSL nodes.
- Keep `rust.metal.Code` available for narrow low-level bridges, not normal app authoring.

### 6. Contract-First Metal Capability Fixtures

Bead: `haxe.rust-oo3.74.8`

- Start with failing contracts before implementation.
- Include positive and negative fixtures for borrows/lifetimes, traits/bounds, typed DSLs, extern islands, no-raw policy, no-hxrt, and idiomatic output.
- Keep fixture names product-neutral.
- Use [Metal capability fixture plan](metal-capability-fixtures.md) as the working matrix for fixture names, existing evidence, missing contracts, and owning harnesses.

### 7. Idiomatic Metal Output Gates

Bead: `haxe.rust-oo3.74.6`

- Add a metal idiom fixture suite focused on emitted Rust shape after the contract fixtures exist.
- Fail on rustfmt or warning regressions.
- Fail on unexpected `hxrt`, `Dynamic`, or raw `ERaw` in metal-clean fixtures unless an explicit allowlist entry documents why the runtime/fallback is required.
- Use deterministic baseline counters for clone noise, borrow-guard scope, and native-representation expectations; increases must fail unless the baseline is intentionally updated with rationale and fixture evidence.
- Connect this to the existing benchmark-corpus bead `haxe.rust-oo3.73`.

### 8. Extern And Lifetime-Island Cookbook

Bead: `haxe.rust-oo3.74.7`

- Document how to bind Rust APIs that need lifetimes, HRTB, const generics, macro-heavy setup, or unsafe internals.
- Show the pattern: handwritten Rust module, typed Haxe extern/facade, Cargo metadata, tests.
- Include at least one snapshot/example that exercises a lifetime-heavy helper through a typed facade.

### 9. Capability-Driven Portable Facades

Bead: `haxe.rust-oo3.74.9`

- Design portable-shaped API surfaces that compile across targets while the Rust target lowers
  through native Rust representations when the facade contract admits it.
- Define facade admission rules: cross-target source contract, explicit Rust specialization, no
  hidden `rust.*` import requirement, and no silent switch from ordinary portable semantics to
  Rust-native semantics.
- Specify compiler-owned metadata/intrinsics for native Rust representations and no-hxrt
  eligibility.
- Require deterministic fallback reports that explain every runtime dependency and make
  `rust_no_hxrt` failures actionable.
- Do not close this bead on docs alone. Closure requires at least one concrete compiler/report
  fixture that proves consumed facade surfaces, native representation decisions, or deterministic
  runtime fallback reasons.

Required implementation artifacts:

- `SurfaceContractRegistry` or equivalent: classifies ordinary Haxe, admitted portable facade,
  Rust-native, and metal-island surfaces by stable IDs.
- `NativeRepresentationPlan`: records selected Rust shapes such as `Option<T>`, `Result<T,E>`, or
  runtime fallback representations with reasons.
- `RuntimeRequirementLedger`: records semantic runtime requirements before final codegen using
  stable reason kinds, not free-form strings.
- `NoHxrtEligibilityPass`: source/typed-AST gate for no-runtime eligibility before lowering. The
  first metal-only implementation is `NoHxrtEligibilityAnalyzer`; portable `rust_no_hxrt` remains
  future work until positive portable-facade fixtures exist.
- Existing `NoHxrtPass`: final emitted-code validator that rejects generated `hxrt` references.
- Extended `contract_report.*` / `runtime_plan.*` fixtures that prove deterministic ordering,
  source/module attribution, consumed surfaces, selected representations, and fallback blockers.
  The first concrete wave includes `test/snapshot/portable_facade_native_option_result`,
  `test/snapshot/portable_facade_contract_report`,
  `test/positive/portable_native_typed_report`, `test/negative/portable_native_typed_strict`,
  and `test/negative/runtime_fallback_reason_dynamic`.
- Output-shape gates for admitted facades. The first concrete gate is in
  `scripts/ci/check-metal-policy.sh` and asserts that
  `test/snapshot/portable_facade_native_option_result` emits native Rust `Option<i32>` /
  `Result<i32, i32>` in the generated user module without routing those values through
  `hxrt::dynamic`, `hxrt::array`, raw `__rust__`, or raw `ERaw` markers.

Tracker children created from the Oracle review:

- `haxe.rust-oo3.74.9.2`: surface contract registry and report schema.
- `haxe.rust-oo3.74.9.3`: semantic runtime requirement ledger.
- `haxe.rust-oo3.74.9.4`: no-hxrt eligibility pass split from emitted-code guard.
- `haxe.rust-oo3.74.9.5`: first portable facade report fixtures.
- `haxe.rust-oo3.74.9.6`: deferred portable Vec facade admission.
- `haxe.rust-oo3.74.9.7`: typed surface usage reporting beyond textual import scans.
- `haxe.rust-oo3.74.9.8`: portable facade output-shape gates.

## Tracker Sweep

The tracker was migrated to the modern embedded Beads database on July 2, 2026 and recovered from the tracked JSONL export.

Current recovered inventory before adding this milestone:

- 567 issue records imported into the modern Beads DB.
- 553 closed.
- 14 open.
- 13 ready.
- 1 blocked.

The open pre-existing beads remain relevant. They are concrete compiler/runtime gaps rather than stale planning work:

- anonymous structure/runtime correctness: `haxe.rust-i8li`, `haxe.rust-kilb`, `haxe.rust-yrs1`
- option/null/default lowering: `haxe.rust-362`, `haxe.rust-3oju`
- ownership/clone/assign-op lowering: `haxe.rust-fzl`, `haxe.rust-ojj`
- generic bounds/static path/codegen gaps: `haxe.rust-akfm`, `haxe.rust-3f0g`
- std/codegen missing lowers: `haxe.rust-7xia`, `haxe.rust-fz20`, `haxe.rust-gn0`
- root roadmap and performance corpus: `haxe.rust-oo3`, `haxe.rust-oo3.73`

The new milestone does not supersede those beads. It gives them a broader metal-authoring direction and adds the missing compiler/API roadmap.

## Review Requirement

This milestone is `thinking:xhigh` because it changes the metal contract direction and can shape public authoring guidance.

Before closure:

- get an Oracle/GPT-5.5 Pro-style second-pass review if available, or
- record an explicit written second-pass design review in Beads comments/design notes.

The review should answer:

- Does this preserve the portable/metal contract boundary?
- Does it avoid promising full Rust lifetime syntax in Haxe?
- Are mini-DSLs constrained enough to avoid becoming raw Rust strings?
- Are output-quality gates concrete enough to prevent "haxified Rust" from becoming marketing language?
