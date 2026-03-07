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
- pass pipeline includes normalize + mut inference + clone elision + borrow-scope tightening.
- metal restrictions pass is still executed so `@:haxeMetal` lanes enforce strict island rules.
- strict app-boundary mode is not auto-enabled; add `-D reflaxe_rust_strict` to reject raw app-side `untyped __rust__(...)`.

Portable idiom guidance:

- Prefer portable shared surfaces (`reflaxe.std`) for cross-target Option/Result style flows.
- On Rust, `reflaxe.std.Option/Result` are expected to lower to the same native Rust
  `Option/Result` representations used by `rust.Option` / `rust.Result`.
  The difference is API contract and portability intent, not a wrapper runtime type.
- Keep `rust.*` imports as explicit Rust-native lane APIs.
- portable native-import diagnostics remain reviewable in contract reports (and can be enforced with
  `-D rust_portable_native_import_strict`).

## Contract: `metal`

Use `metal` when you want:

- Rust-first authoring/performance direction,
- strict app-boundary policy by default (`reflaxe_rust_strict` auto-enabled),
- explicit fallback control (`rust_metal_allow_fallback`).

Interop note (beginner-friendly):

- Use typed `extern`/`@:native` APIs and framework facades for Rust interop.
- Use `rust.metal.Code` only behind typed framework/library APIs.
- Avoid direct app-side `untyped __rust__(...)`; metal treats that as a contract violation by default.

Default behavior:

- non-null Rust `String` representation unless explicitly overridden.
- non-null string contract: `String` cannot be `null` in metal-clean mode.
  Use `Null<String>` for nullable values, or explicitly enable `-D rust_string_nullable` when portability semantics are required.
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
- Portable contract tracks native-target imports (`rust.*`, `cpp.*`, etc.) as portability signals:
  - default: warning + contract-report marker (`nativeImportHits`),
  - strict: `-D rust_portable_native_import_strict` turns those warnings into errors.

## Contract and runtime plan reports

Opt-in deterministic report artifacts:

```bash
-D rust_contract_report
-D rust_runtime_plan_report
-D rust_optimizer_plan_report
```

Generated artifacts:

- `contract_report.json` / `contract_report.md`
- `runtime_plan.json` / `runtime_plan.md`
- `optimizer_plan.json` / `optimizer_plan.md`

The report schemas include explicit identity fields:

- `backendId` (for both reports)
- `runtimeId` (runtime plan report)
- `contract` (`portable` or `metal`)
- `familyStdPin` (pin metadata from `family/family_std_pin.json` when visible from the compile root)

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

## Related contract docs

- `docs/reflaxe-std-adoption-contract.md`
