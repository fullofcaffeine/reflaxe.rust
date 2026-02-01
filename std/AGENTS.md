# Agent Instructions for `std/`

- `std/` is framework-level Haxe code shipped with the target.
- `__rust__` injection is allowed here, but keep it as a last-resort escape hatch and hide it behind typed Haxe APIs.
- Do not expose raw `__rust__` calls to application/example code; enforce “apps call Haxe APIs, not injections”.
- When overriding Haxe stdlib modules (e.g. `haxe.io.Bytes`, `Sys`, `sys.*`), keep their public signatures compatible so other std modules typecheck.
- Some stdlib APIs are declared as `@:coreApi extern` in the eval stdlib (`std/eval/_std/**`). Target overrides must match these signatures exactly (including property accessor shapes like `var x(get, never)`), otherwise Haxe will error during typing.
- Prefer stable, typed interop surfaces:
  - declare Cargo deps via `@:rustCargo(...)` on `std/` types that need external crates
  - bind to hand-written Rust modules via `extern` + `@:native("crate::...")` instead of direct `__rust__` at callsites

- `__rust__` in `std/`:
  - Avoid `inline` functions that contain `untyped __rust__(...)`. Inlining can leak the injection into unrelated stdlib modules (including macro/eval typing) and break compilation or violate the “apps are pure” boundary rule.
