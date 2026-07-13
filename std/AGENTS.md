# Agent Instructions for `std/`

- `std/` is framework-level Haxe code shipped with the target.
- `__rust__` injection is allowed here, but keep it as a last-resort escape hatch and hide it behind typed Haxe APIs.
- Do not expose raw `__rust__` calls to application/example code; enforce “apps call Haxe APIs, not injections”.
- `@:rustAllowRaw` is for narrow low-level authority islands when strict boundary enforcement would otherwise reject a necessary raw bridge.
  It does not weaken `metal` / `@:rustMetal`; those paths must still become typed instead of relying on raw fallback.
- Reflaxe convention: target std/support roots are declared in `haxelib.json` `reflaxe.stdPaths`;
  package builds flatten those roots, and paths ending in `_std` become packaged `.cross.hx` files.
- Rust-target instance: upstream-colliding Haxe stdlib overrides live under `std/rust/_std/**`
  in the source checkout
  (for example `std/rust/_std/haxe/Exception.hx`, `std/rust/_std/Sys.hx`, and
  `std/rust/_std/sys/io/File.hx`). Do not add new upstream-colliding overrides directly under
  `std/haxe/**`, `std/sys/**`, or top-level `std/*.hx`.
- Top-level support namespaces such as `std/haxe/**` and `std/sys/**` are not deprecated, but they
  are for Rust-target support modules/native helper files that do not shadow upstream std modules.
- Shared Haxe declarations that exist only to connect framework std modules belong under
  `std/rust/_internal/**`. Application imports of `rust._internal.*` are compiler errors. Do not
  place a semantic app-facing operation there; give it a documented `rust.*` facade and classify it
  in `docs/public-compatibility-manifest.json` instead.
- When overriding Haxe stdlib modules (e.g. `haxe.io.Bytes`, `Sys`, `sys.*`), keep their public signatures compatible so other std modules typecheck.
- For upstream nominal iterator overrides, preserve the upstream evaluation model rather than merely
  matching `hasNext` / `next` signatures. In particular, `DynamicAccess` iterators capture keys once but
  read values lazily from the live source; do not replace that contract with an eager array snapshot.
  Keep the Haxe override typed and let the compiler own any required nominal-to-structural adapter.
- Some stdlib APIs are declared as `@:coreApi extern` in the eval stdlib (`std/eval/_std/**`). Target overrides must match these signatures exactly (including property accessor shapes like `var x(get, never)`), otherwise Haxe will error during typing.
- Prefer stable, typed interop surfaces:
  - declare Cargo deps via `@:rustCargo(...)` on `std/` types that need external crates
  - bind to hand-written Rust modules via `extern` + `@:native("crate::...")` instead of direct `__rust__` at callsites
- `std/rust/native/*.rs` is for narrow typed Rust-native facade backing code, not a second runtime.
  Before adding or expanding one of these helpers:
  - prefer compiler lowering if the behavior can be emitted directly from typed AST, literals,
    metadata, or existing Rust primitives
  - classify the helper as `permanent-native-facade`, `lowering-candidate`, or
    `experimental-scaffold`
  - update `docs/native-facade-manifest.json` with the helper's owner, runtime contract
    (`no-hxrt` or explicit `hxrt-bridge`), allowed imports/dependency prefixes, forbidden growth,
    evidence owner, and code-line review budget
  - document the owning Haxe extern/facade and why lowering is insufficient today
  - keep dependencies/imports narrow and Rust-shaped
  - forbid undeclared `hxrt`, `Dynamic`, `Any`, type-erased handles, broad portable semantics,
    generic registries, reflection-like dispatch, and allocation-heavy adapters
  - add generated call-site inspection, cargo/rustfmt evidence, and a policy fixture that proves the
    intended no-hxrt output shape
  - run `npm run guard:native-facade-manifest`
- Before adding or expanding `std/hxrt/**` externs or runtime-backed helpers, prove the value cannot
  be produced by compiler lowering from typed AST/metadata/literals/existing target primitives.
  Do not add `hxrt` APIs for compile-time-known facts such as optional field status, literal defaults,
  static access paths, borrow-region syntax, or generic dispatch shape.
  If runtime support is genuinely required, keep the extern narrow, typed, documented, and covered by
  both runtime/helper tests and generated-callsite fixtures.

- `__rust__` in `std/`:
  - Avoid `inline` functions that contain `untyped __rust__(...)`. Inlining can leak the injection into unrelated stdlib modules (including macro/eval typing) and break compilation or violate the “apps are pure” boundary rule.
