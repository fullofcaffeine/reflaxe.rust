# Metal Contract (`-D reflaxe_rust_profile=metal`)

`metal` is the Rust-first contract for performance-sensitive code paths.

## Goals

- Keep Rust-first APIs and typed native surfaces.
- Enforce strict app-boundary rules by default.
- Make fallback usage explicit and measurable.

## Select metal contract

```bash
-D reflaxe_rust_profile=metal
```

No profile aliases are supported.

## Boundary policy

In `metal`, strict app boundary mode is enabled by default (`reflaxe_rust_strict`):

- raw app-side `untyped __rust__(...)` is rejected,
- typed framework-owned facades remain allowed,
- controlled typed escapes are available via:
  - `rust.metal.Code.expr(...)`
  - `rust.metal.Code.stmt(...)`

## Metal lanes in portable projects

Portable projects can still lock specific modules to metal-clean rules with lane metadata.

Canonical lane metadata:

```haxe
@:haxeMetal
class CriticalPath {
  public static function run(v:Int):Int {
    return v + 1;
  }
}
```

Compatibility alias:

- `@:rustMetal` is accepted as an alias.
- Prefer `@:haxeMetal` in new code.

Behavior in portable:

- tagged modules are treated as strict metal islands,
- dynamic/reflection/raw-fallback blockers error immediately.

## Metal clean vs fallback

- default (`metal` clean): violations are compile errors.
- fallback mode: `-D rust_metal_allow_fallback` downgrades violations to warnings.

Fallback diagnostics are aggregated once per compile with:

- total `ERaw` fallback count,
- affected module count,
- top modules by fallback count.

## Viability summary and artifacts

Warning summary:

```bash
-D rust_metal_viability_warn
```

Deterministic viability artifacts:

```bash
-D rust_metal_viability_report
```

Outputs:

- `metal_report.json`
- `metal_report.md`

## Contract/runtime reports (family tooling)

To emit deterministic contract/runtime planning artifacts:

```bash
-D rust_contract_report
-D rust_runtime_plan_report
```

Outputs:

- `contract_report.json`, `contract_report.md`
- `runtime_plan.json`, `runtime_plan.md`

## Minimal runtime mode (`rust_no_hxrt`)

`metal` can opt into a no-runtime contract:

```bash
-D rust_no_hxrt
```

Effects:

- skips bundled `hxrt` crate emission,
- omits `hxrt` dependency in generated `Cargo.toml`,
- enforces no `hxrt` references in generated code.

Constraints:

- requires `metal`,
- incompatible with `rust_string_nullable`,
- incompatible with `rust_async`,
- incompatible with `rust_hxrt_*` feature-selection defines.
