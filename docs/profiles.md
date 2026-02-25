# Contracts, Capabilities, and Lanes

`reflaxe.rust` uses an explicit **contract** selector plus opt-in **capabilities** and **lanes**.
This keeps semantics reviewable in CI while still allowing incremental optimization work.

## Contract selector

```bash
-D reflaxe_rust_profile=portable|metal
```

- `portable` (default): portability-first Haxe semantics.
- `metal`: Rust-first contract with strict boundary defaults.

No profile aliases are supported.

## Contract: `portable`

Use `portable` when you want:

- predictable Haxe behavior and compatibility,
- low migration friction for existing Haxe projects,
- production-ready output hygiene without Rust-first restrictions.

Default behavior:

- nullable string representation (`rust_string_nullable`) unless explicitly overridden.
- pass pipeline includes normalize + mut inference + clone elision.

## Contract: `metal`

Use `metal` when you want:

- Rust-first authoring/performance direction,
- strict app-boundary policy by default (`reflaxe_rust_strict` auto-enabled),
- explicit fallback control (`rust_metal_allow_fallback`).

Default behavior:

- non-null Rust `String` representation unless explicitly overridden.
- pass pipeline includes portable passes + borrow-scope stage + metal restrictions.
- contract violations hard-error unless fallback mode is explicitly enabled.
- optional minimal runtime via `-D rust_no_hxrt`.

## Lanes: Metal Islands in Portable Builds

You can enforce metal-clean checks on selected modules while the project contract remains `portable`.

Canonical metadata:

```haxe
@:haxeMetal
class HotPath {
  public static function run(v:Int):Int {
    return v + 1;
  }
}
```

Compatibility alias:

- `@:rustMetal` is still accepted.
- New code should use `@:haxeMetal`.

Both metadata names enforce the same strict island checks in `portable`.

## Capabilities and gates

- `-D rust_async` requires `-D reflaxe_rust_profile=metal`.
- `-D rust_no_hxrt` requires `metal` and cannot be combined with `rust_async`.

## Contract and runtime plan reports

Opt-in deterministic report artifacts:

```bash
-D rust_contract_report
-D rust_runtime_plan_report
```

Generated artifacts:

- `contract_report.json` / `contract_report.md`
- `runtime_plan.json` / `runtime_plan.md`

The report schemas include explicit identity fields:

- `backendId` (for both reports)
- `runtimeId` (runtime plan report)
- `contract` (`portable` or `metal`)

## Migration notes

Removed report define names:

- `rust_profile_contract_report` -> `rust_contract_report`
- `rust_hxrt_plan_report` -> `rust_runtime_plan_report`

Removed report artifact names:

- `profile_contract.*` -> `contract_report.*`
- `hxrt_plan.*` -> `runtime_plan.*`

## Validation

- Profile/lane policy checks: `scripts/ci/check-metal-policy.sh`
- Snapshot matrix: `test/snapshot/*`
- Full local CI-style run: `npm run test:all`
