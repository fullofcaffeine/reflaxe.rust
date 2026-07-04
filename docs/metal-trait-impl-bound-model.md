# Metal Trait, Impl, And Bound Model

This page defines the current `metal` contract for Rust trait-facing surfaces and the next compiler
shapes that should replace raw impl snippets over time.

## Current Surfaces

`metal` can express Rust trait concepts through four existing Haxe-facing surfaces:

1. Haxe `interface` declarations.
   - Source contract: Haxe interface dispatch.
   - Rust shape: generated Rust traits plus trait-object handles for interface-typed values.
   - Best use: ordinary polymorphic Haxe APIs that should still compile as Rust trait calls.
2. `@:rustImpl(...)` metadata on emitted Haxe classes/enums.
   - Source contract: attach a Rust trait impl to a local generated type.
   - Rust shape: an extra `impl Trait for Type { ... }` block.
   - Best use: marker traits or narrow hand-authored impl bodies such as `Display`.
3. `@:rustGeneric(...)` metadata on classes and fields.
   - Source contract: override the Rust generic declaration/bounds used at that boundary.
   - Rust shape: generic parameter declarations such as `T: Clone + Send + Sync`.
   - Best use: extern/native helpers and generated types that need explicit Rust trait bounds.
4. `extern`/`@:native(...)` facades backed by `@:rustExtraSrc(...)` or `-D rust_extra_src=...`.
   - Source contract: a typed Haxe API over a Rust implementation island.
   - Rust shape: hand-written Rust owns the lifetime-heavy or bound-heavy internals.
   - Best use: APIs whose lifetimes, HRTB, const generics, or macro-heavy implementation are not
     directly representable in Haxe yet.

## Admission Rules

Use these rules before adding a new trait-facing API:

- Prefer a Haxe `interface` when the Haxe semantic contract is normal dynamic dispatch.
- Prefer `@:rustGeneric` when the only missing piece is a Rust trait bound on an admitted generic
  class, method, or extern helper.
- Prefer `@:rustImpl("path::Trait")` for marker traits with empty impl blocks.
- Treat `@:rustImpl("path::Trait", "fn ...")` as a narrow metadata escape hatch. It is allowed for
  local generated types, but broad app-side impl-body strings should become typed metadata or an
  extern island.
- Use an extern island when the Rust API requires lifetimes, HRTB, associated types, const generics,
  macros, or unsafe setup that Haxe cannot model directly.
- Do not hide Rust trait requirements behind `Dynamic`, broad `Any` payloads, app-side `__rust__`,
  or stringly mini-DSLs.

## Missing Typed Shapes

These are not full compiler-owned surfaces yet:

- `where` clauses distinct from inline generic declarations,
- associated types and associated consts,
- trait object bounds beyond the generated Haxe-interface path,
- blanket impls and negative impls,
- derive helpers beyond current `@:rustDerive(...)` strings,
- object-safety diagnostics before Rust compile,
- orphan-rule diagnostics before Rust compile.

The planned direction is to admit typed metadata/macros such as future `@:rustWhere`,
`@:rustAssociatedType`, or trait-object helpers only when they can produce deterministic compiler
structure and stable diagnostics. Until then, extern islands are the correct boundary for complex
Rust-only trait systems.

## Fixture Evidence

Current contract fixtures:

- `test/snapshot/rust_impl_meta`
  proves the baseline `@:rustImpl(...)` metadata output.
- `test/snapshot/generics_interface`
  proves generic Haxe interfaces lower through Rust trait-object handles.
- `test/snapshot/metal_trait_impl_bounds`
  proves a metal fixture can combine `@:rustImpl`, class-level bounds, and a bounded extern helper.
- `test/snapshot/metal_trait_object_boundary`
  proves a metal fixture can use Haxe interfaces as Rust trait-object boundaries.
- `test/snapshot/generic_helper_payload_bounds`
  proves generic helper methods propagate generated class payload bounds into their Rust signatures.

Every new trait-facing surface should add either a generated Rust shape fixture or a negative policy
fixture before being documented as admitted.
