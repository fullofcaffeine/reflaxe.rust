# Metal Trait, Impl, And Bound Model

This page defines the current `metal` contract for Rust trait-facing surfaces. The compiler now keeps
generated traits, impl headers, receivers, where clauses, and associated items as structural Rust IR;
the remaining roadmap here is mainly about safe, typed Haxe-facing authoring APIs.

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

## Compiler IR Boundary

Generated Haxe interfaces, class-polymorphism traits, base/interface impls, and inherent impls use
typed `RTrait` / `RImpl` declarations. Their trait paths, target types, generics, supertraits,
receivers, parameters, return types, where predicates, and associated functions/types/constants are
therefore visible to compiler passes. Ownership and no-`hxrt` policy use the shared structural path
visitor instead of scanning printed Rust.

`@:rustImpl` remains a real metadata boundary, but it is narrower than before:

- the trait string is parsed immediately into a structural `RustPath`;
- an optional `forType` string is parsed immediately into `RustType`;
- the compiler owns and prints the `impl ... for ...` header;
- only a non-empty user-supplied inner body remains `metadata-owned:trait-implementation` raw text.

The structural factories also enforce the context Rust assigns to each form. Trait associated types
are declarations without defaults on stable Rust, while trait-impl associated types are definitions
with a value and no declaration bounds. Generic associated-type definitions print `where` after their
value so warning-denied builds use Rust's preferred syntax. Relaxing an implicit size requirement is
represented only as `?Sized`, and only type parameters or associated-type declarations admit it; the
IR cannot construct a generalized `?Clone`, a relaxed supertrait, or an unproven relaxed where bound.
Executable passes treat associated constant initializers as bodies, alongside trait defaults and impl
methods, so cleanup and ownership rewrites do not stop at the associated-item boundary.

This internal support does not by itself create a new public Haxe syntax for associated types or
where clauses. It makes those future surfaces possible without another printer-string migration.

## Missing Haxe-Facing Typed Surfaces

These are not full source-authoring surfaces yet:

- public typed metadata/macros for `where` clauses distinct from inline generic declarations,
- public typed metadata/macros for associated types and associated consts,
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

- `test/compiler/RustStructuralTraitImplContract.hx` and
  `test/scripts/rust-structural-trait-impls.test.js`
  prove structural traits/impls, where predicates, associated items, deterministic printing,
  rustc-clean output, pass traversal, and fail-closed no-`hxrt` analysis.

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
