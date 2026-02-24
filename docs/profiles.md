# Profiles (`-D reflaxe_rust_profile=...`)

This target exposes two profile contracts only:

- `portable` (default): Haxe-portable semantics first.
- `metal`: Rust-first performance profile with strict typed boundaries.

## Profile selector

```bash
-D reflaxe_rust_profile=portable|metal
```

No profile aliases are supported.

## Choosing a Profile

### `portable`

Use when you want:

- predictable Haxe semantics,
- the lowest migration friction from existing Haxe code,
- portability-first behavior with production-grade codegen hygiene.

Default behavior:

- nullable string representation (`rust_string_nullable`) unless explicitly overridden.
- pass pipeline includes normalize + mut inference + clone elision.

Metal islands in portable:

- You can mark specific modules/fields with `@:rustMetal` to opt those modules into strict
  metal-clean checks without switching the whole project to `metal`.
- Island checks are strict by design (compile errors on dynamic/reflection/raw fallback blockers).
- Use this for incremental migration of hot paths.

### `metal`

Use when you want:

- Rust-first authoring and performance focus,
- strict app-boundary policy by default (`reflaxe_rust_strict` auto-enabled),
- explicit control over fallback behavior.

Default behavior:

- non-null Rust `String` representation unless explicitly overridden.
- pass pipeline includes portable passes + borrow-scope stage + metal restrictions.
- profile contract violations hard-error unless `-D rust_metal_allow_fallback` is set.
- optional minimal-runtime mode via `-D rust_no_hxrt` (enforces no generated `hxrt` references).

## Async profile gate

`-D rust_async` requires:

```bash
-D reflaxe_rust_profile=metal
```

Async is incompatible with `-D rust_no_hxrt` because async lowering currently targets `hxrt::async_`.

## Metal clean vs fallback

- **Metal clean (default)**: contract violations are compile errors.
- **Metal fallback** (`-D rust_metal_allow_fallback`): same violations become warnings.
- Fallback mode emits one aggregate warning per compile with total `ERaw` fallback count and top modules.

Use fallback only while actively removing remaining non-metal-clean boundaries.

## `@:rustMetal` island metadata

Supported declaration points:

- type level: `class`, `enum`, `typedef`, `abstract`
- field level: methods/vars inside classes (or abstract impl fields)

Example:

```haxe
@:rustMetal
class HotPath {
  public static function run(v:Int):Int {
    return v + 1;
  }
}
```

In `portable`, this enforces metal-clean contracts for the `HotPath` module only.

## String representation defaults

- `portable` defaults to `rust_string_nullable`.
- `metal` defaults to non-null string mode.

Explicit overrides:

- `-D rust_string_nullable`
- `-D rust_string_non_nullable`

## Contract report artifact

For deterministic CI/review evidence, emit profile and runtime-plan artifacts with:

```bash
-D rust_profile_contract_report
-D rust_hxrt_plan_report
```

This writes:

- `profile_contract.json` / `profile_contract.md`
- `hxrt_plan.json` / `hxrt_plan.md`

## Where profile behavior is validated

- Snapshot matrix under `test/snapshot/*`.
- Profile delta case: `test/snapshot/profile_differentiation`.
- Full CI-style local validation: `npm run test:all`.

## Migration note

`idiomatic` and `rusty` profile selectors were removed. See `docs/rusty-profile.md` for migration mapping.
