# Metal Typed DSL Authority

This page defines when `metal` may use a small DSL instead of ordinary Haxe constructs, metadata,
or typed extern/facade APIs.

## Rule

Prefer this order:

1. Haxe language constructs: classes, abstracts, enums, interfaces, typedefs, properties, and typed
   function APIs.
2. Typed metadata/macros that feed compiler-owned structure, such as `@:native`, `@:rustCargo`,
   `@:rustExtraSrc`, `@:rustImpl`, and future typed trait/bound metadata.
3. Typed Rust-native facades under `rust.*`, `hxrt.*`, or a documented `std/` wrapper.
4. A narrow DSL only when Haxe syntax cannot express the Rust concept cleanly.
5. `rust.metal.Code` only as a scoped raw bridge while a real typed surface is missing.

A DSL is not admitted just because it is convenient. It must improve correctness, diagnostics, or
ergonomics while keeping the emitted Rust inspectable.

## Admission Contract

An accepted metal DSL must have:

- typed Haxe inputs and typed Haxe outputs,
- stable compiler-owned semantics, not arbitrary Rust syntax as a string,
- actionable diagnostics when used outside its supported shape,
- a generated-Rust shape fixture or policy fixture,
- rustfmt-friendly emitted Rust,
- no bypass around `portable`, `metal`, `@:rustMetal`, `rust_no_hxrt`, or strict app-boundary rules.

If the DSL lowers to raw Rust internally, it is still a raw-authority boundary. The owning API must
document why the raw boundary exists and what typed shape callers should use instead.

## `rust.metal.Code`

`rust.metal.Code.expr(...)` and `rust.metal.Code.stmt(...)` are controlled escape hatches. They are
not the final metal authoring API.

Allowed use:

- framework/compiler-owned code,
- a narrow project-local owning class tagged with `@:rustAllowRaw`,
- temporary low-level bridges that expose a typed Haxe API to the rest of the app.

Rejected use:

- direct application/business logic calls,
- broad helper modules that become an app-side Rust string DSL,
- attempts to bypass `@:rustMetal` or metal-clean raw-fallback checks.

For `rust.metal.Code`, the current early macro guard checks framework ownership or
`@:rustAllowRaw` on the local class. The broader raw `__rust__` scanners still treat
`@:rustAllowRaw` as a module/type authority after typing.

`@:rustAllowRaw` only permits the call through the strict boundary scanner. It does not make the
result metal-clean. If the generated Rust still contains raw `ERaw`, metal and `@:rustMetal` policy
passes can still reject it unless the build explicitly enables fallback for the fixture under test.

## Replacement Patterns

| Repeated raw snippet | Preferred replacement |
| --- | --- |
| Simple native method call | Typed extern/facade with `@:native(...)`. |
| Cargo dependency setup | `@:rustCargo(...)` on the owning facade type. |
| Extra Rust helper module | `@:rustExtraSrc(...)` / `@:rustExtraSrcDir(...)` plus typed extern API. |
| Option/Result construction or matching | `rust.Option`, `rust.Result`, or admitted `reflaxe.std` facade. |
| Borrow/slice view | `rust.Borrow.withRef`, `Borrow.withMut`, `SliceTools.with`, `MutSliceTools.with`. |
| Async task/future boundary | `rust.async.*` typed surfaces and async metadata. |
| Trait/impl boilerplate | Typed metadata or future compiler-owned trait/bound model, not raw impl strings by default. |
| Unsafe/lifetime-heavy library | Handwritten Rust island behind a small typed Haxe extern/facade. |

When a raw snippet appears repeatedly, treat it as a missing compiler/runtime/std surface. Add a
generic fixture and close that gap rather than teaching apps to keep using the snippet.

## Fixtures

Current policy evidence:

- `test/negative/metal_stringly_dsl_app_api`
  rejects direct app-side `rust.metal.Code.expr(...)` without scoped raw authority.
- `test/negative/metal_dsl_bypasses_policy`
  proves `rust.metal.Code` plus `@:rustAllowRaw` still cannot bypass `@:rustMetal` raw-fallback
  restrictions.
- `test/snapshot/metal_typed_injection`
  remains an explicit fallback fixture for the controlled bridge itself; it is tagged
  `@:rustAllowRaw` and compiled with `rust_metal_allow_fallback`.

Future typed DSL work should add positive fixtures that do not require `rust.metal.Code` at all.
