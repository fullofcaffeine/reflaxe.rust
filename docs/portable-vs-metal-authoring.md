# Portable vs Metal Authoring

This page is the short answer for performance-oriented teams choosing how to write source code.

Use it when the question is not "what do the contracts mean?" but:

- how should I write modules in each contract,
- when is portable already the right authoring style,
- and when should I switch to metal on purpose?

## Why this exists

`reflaxe.rust` has two public contracts:

- `portable`
- `metal`

The compiler can optimize portable lowering aggressively when semantics match, but that does not
mean the two contracts should be authored the same way.

This guide keeps the authoring choice explicit.

The long-term `metal` direction is haxified Rust: use Haxe constructs and typed compiler surfaces to
author Rust-native code, while generated Rust remains idiomatic and reviewable. See
[Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md).

## What decides the lowering

The profile is the policy preset. The consumed API surface is what tells the compiler which
semantics must be preserved.

- ordinary Haxe/std APIs keep portable Haxe semantics,
- `reflaxe.std.*` APIs can be portable facades with Rust-native representations on this backend,
- `rust.*` / `rust.metal.*` APIs are explicit native-lane source choices,
- `@:haxeMetal` turns a selected module into a strict native-lane island.

This means the portable/metal boundary is not only a folder or module split. It is visible in
imports, metadata, and reports. Portable code can lower to native Rust shapes when its chosen facade
permits that; it must not receive Rust-native semantics by accident.

## Portable-first authoring

Write portable-first code when:

- the module should keep Haxe semantics first,
- cross-target intent still matters,
- shared portable idioms are enough,
- or the backend is already able to lower the code to Rust-native shapes efficiently.

What that looks like:

- ordinary Haxe control flow and data flow,
- std/runtime APIs,
- `reflaxe.std` abstractions where they preserve portable intent while lowering well on Rust,
- no backend-local imports unless you intentionally want native-lane coupling.

Current example anchors:

- `examples/chat_loopback/profile/PortableRuntime.hx`
- `examples/profile_storyboard/profile/PortableRuntime.hx`
- `examples/hello`

Practical expectation:

- portable code can still compile to native-feeling Rust representations when semantics match,
- but portable authoring should not reach for `rust.*` just because the current backend could lower
  it nicely.

## Metal-first authoring

Write metal-first code when:

- the source contract itself should be Rust-first,
- you want native Rust-facing APIs in source,
- portability is no longer the goal for that module,
- or measured hotspots still need a Rust-first contract after portable-preserving optimizations are
  exhausted.

What that looks like:

- explicit `rust.*` / `rust.metal.*` usage where appropriate,
- stricter app-boundary policy,
- typed low-level abstractions instead of raw app-side injection,
- source that intentionally reads more like Rust-flavored Haxe than portable Haxe.
- Haxe abstracts, enums, interfaces, metadata, macros, and typed extern facades that model Rust
  concepts directly instead of scattering raw Rust snippets.

Current example anchors:

- `examples/metal_first_dataflow/Harness.hx`
- `examples/profile_storyboard/profile/MetalRuntime.hx`
- `examples/chat_loopback/profile/MetalRuntime.hx`

What metal demonstrates that portable examples intentionally do not:

- explicit native-lane authoring,
- Rust-first API choice as part of the source contract,
- and performance-oriented source decisions that are not pretending to stay backend-agnostic.

## Using `reflaxe.std` vs `rust.*`

Use `reflaxe.std` when:

- you want a portable idiom surface,
- the abstraction should stay cross-backend in meaning,
- and you want the backend to map it to the best native representation available when semantics
  match.

Use `rust.*` when:

- you are writing native-lane Rust-first code,
- the source contract should explicitly depend on Rust-facing APIs,
- or the module belongs in `metal` rather than portable.

Rule of thumb:

- `reflaxe.std` is for portable source that can still lower efficiently.
- `rust.*` is for explicit native-lane source.
- `hxrt` should appear only when source semantics require runtime support, not because the compiler
  took an easier implementation path.

## Performance expectations

Do not use this guide to infer blanket near-handwritten-Rust parity.

What is justified today:

- portable can already lower some abstractions to native Rust representations,
- metal remains the primary Rust-first performance contract,
- JSON is the only currently evidence-backed future hotspot family for additional performance work.

What is not justified:

- claiming every portable module is already equivalent to hand-written Rust,
- treating `reflaxe.std` as a free pass to import native-lane APIs,
- or assuming metal is required whenever performance matters.

Near-term guidance:

- use `metal` where a module needs Rust-native runtime/tool behavior, strict host-boundary
  semantics, or production-shaped performance now,
- keep `portable` for DTOs, codecs, fixtures, schema/protocol validation, config, and pure state
  when those surfaces are Haxe-semantics-first,
- and treat portable-to-metal performance convergence as a compiler goal wherever Rust lowering can
  preserve Haxe semantics.

If a consumer needs `metal` mainly because portable output is currently too slow or awkward, reduce
the gap to a generic haxe.rust fixture, benchmark, or contract test. Do not add project-specific
compiler shortcuts to make one downstream codebase look good.

## Quick decision rule

1. Start portable.
2. Stay portable if:
   - the source should remain portable,
   - the measured cost is acceptable,
   - and the backend is already lowering the hot abstractions well.
3. Move to metal if:
   - the source contract should become Rust-first,
   - or the measured hotspot still needs a native-lane design after portable-preserving work is exhausted.

## Read next

- `docs/portable-near-native-guidance.md`
- `docs/profiles.md`
- `docs/metal-profile.md`
- `docs/metal-haxified-rust-roadmap.md`
- `docs/examples-matrix.md`
