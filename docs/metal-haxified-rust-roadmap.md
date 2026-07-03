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
   - Native representations should be used when semantics match: `Option`, `Result`, `Vec`, references, slices, strings, paths, handles, and RAII-style guards.
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
