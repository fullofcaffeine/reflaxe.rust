# Defines Reference (`-D ...`)

This page is a practical reference for the most relevant compiler defines.

## Core output and build

- `rust_output=<dir>`
  - Required for Rust generation. Also acts as the stable signal that Rust target compilation is active.
- `rust_crate=<name>`
  - Override generated Cargo crate name.
- `rust_no_build` or `rust_codegen_only`
  - Generate Rust only; skip Cargo invocation.
- `rust_build_release` or `rust_release`
  - Use release build mode (`cargo build --release`).
- `rust_target=<triple>`
  - Pass Cargo target triple.
- `rust_no_gitignore`
  - Do not emit generated crate `.gitignore`.
- `rustfmt`
  - Run `cargo fmt` after code generation (best effort).
- `rust_deny_warnings`
  - Emit crate-level deny warnings for generated Rust.

## Contracts and semantics

- `reflaxe_rust_profile=portable|metal`
  - Main profile switch.
- `rust_async`
  - Enable async/await surfaces (`rust.async.Future`, `rust.async.Async.*`).
  - Requires `reflaxe_rust_profile=metal`.
- `rust_async_preview`
  - Removed legacy define retained only as a migration error trigger.
  - The compiler reports an explicit error and instructs to use `rust_async`.
- `rust_string_nullable`
  - Force nullable string representation.
- `rust_string_non_nullable`
  - Force legacy non-null Rust `String` representation.
  - In `metal`, this implies strict non-null string semantics:
    `String` cannot be `null`; prefer `Null<String>` for nullable values.
- `rust_emit_upstream_std`
  - Emit upstream Haxe std modules when referenced.
- `rust_allow_unresolved_monomorph_dynamic`
  - Escape hatch that allows unresolved monomorph fallbacks to degrade to `Dynamic`.
  - Not allowed in `metal` clean mode (unless fallback is explicitly enabled).
- `rust_allow_unmapped_coretype_dynamic`
  - Escape hatch that allows unmapped `@:coreType` values to degrade to `Dynamic`.
  - Not allowed in `metal` clean mode (unless fallback is explicitly enabled).
- `rust_warn_unresolved_monomorph_std`
  - Re-enable unresolved monomorph warnings for framework/upstream std internals.
- `rust_warn_unmapped_coretype_std`
  - Re-enable unmapped `@:coreType` fallback warnings for framework/upstream std internals.
- `rust_debug_string_types`
  - Debug define for string type diagnostics.
- `rust_idiomatic`
  - Removed legacy alias define. Use `-D reflaxe_rust_profile=portable`.
- `rust_metal`
  - Removed legacy alias define. Use `-D reflaxe_rust_profile=metal`.
- `rust_debug_metal_raw`
  - Debug-only hotspot tracer for metal fallback forensics.
  - When enabled, `MetalRestrictionsPass` prints one warning per encountered raw `ERaw` snippet
    with module attribution (`metal raw expr [<module>] ...`) to help root-cause remaining fallback paths.
- `rust_metal_allow_fallback`
  - In `metal`, downgrades contract violations (including `ERaw` fallback detection) from errors to warnings.
- `rust_metal_contract_hard_error`
  - Advanced override that forces hard-error metal contract enforcement.
  - Primarily intended for policy/CI wiring where explicit hard-fail is required.
- `rust_portable_native_import_strict`
  - In `portable`, escalates native target-module import diagnostics from warnings to errors.
  - Native-target imports are always reported in `contract_report.*` artifacts.
- `rust_metal_viability_warn`
  - In `metal`, emit one compile-time viability summary warning (score + blocker counts + top modules).
  - Intended for CI/review loops while reducing fallback hotspots ahead of full report artifacts.
- `rust_metal_viability_report`
  - In `metal`, emit deterministic viability artifacts in the generated crate root:
    - `metal_report.json` (machine-readable)
    - `metal_report.md` (human-readable)
  - Uses the same typed snapshot as warnings, so reports and diagnostics stay in sync.
- `rust_contract_report`
  - Emit deterministic contract artifacts in the generated crate root:
    - `contract_report.json` (machine-readable)
    - `contract_report.md` (human-readable)
  - Includes effective contract flags (`contract`, strictness, async/no-hxrt/string mode),
    backend identity (`backendId`), native-import portability markers, and current warning/error diagnostics.
- `rust_runtime_plan_report`
  - Emit deterministic runtime-plan artifacts in the generated crate root:
    - `runtime_plan.json` (machine-readable)
    - `runtime_plan.md` (human-readable)
  - Records runtime identity (`runtimeId`), effective mode (`no_hxrt|default_features|selective`),
    selected feature set, and typed provenance entries (`module`, `define`, `dependency_edge`).
- `rust_optimizer_plan_report`
  - Emit deterministic optimizer-plan artifacts in the generated crate root:
    - `optimizer_plan.json` (machine-readable)
    - `optimizer_plan.md` (human-readable)
  - Records executed pass order, applied optimization counts, skipped-reason counts,
    and aggregate convergence metrics (`cloneElisions`, `loopOptimizations`).
- `rust_no_hxrt`
  - Metal-only minimal-runtime mode.
  - Omits bundled `hxrt` emission and `Cargo.toml` dependency.
  - Enforces a no-`hxrt` generated output contract (compile error on runtime references).
  - Incompatible with:
    - `rust_string_nullable`
    - `rust_async`
    - `rust_hxrt_default_features`, `rust_hxrt_no_feature_infer`, `rust_hxrt_features`

## Cargo command controls

- `rust_cargo_subcommand=build|check|test|clippy|run`
- `rust_cargo_cmd=<binary>`
- `rust_cargo_target_dir=<path>`
- `rust_cargo_features=feat1,feat2`
- `rust_cargo_no_default_features`
- `rust_cargo_all_features`
- `rust_cargo_jobs=<n>`
- `rust_cargo_locked`
- `rust_cargo_offline`
- `rust_cargo_quiet`
- `rust_cargo_toml=<path>`
  - Override full generated `Cargo.toml` template.
- `rust_cargo_deps_file=<path>`
  - Append dependency lines under `[dependencies]` from file.
- `rust_cargo_deps=<toml-lines>`
  - Inline dependency lines fallback.

## Interop and extra sources

- `rust_extra_src=<dir>`
  - Copy `.rs` modules into generated crate `src/` and auto-include them.

## Strictness and boundary enforcement

- `reflaxe_rust_strict`
  - Enforce strict no-injection policy for user project code.
- `reflaxe_rust_strict_examples`
  - Enforce strict policy in repo examples/snapshot paths.
- `rust_send_sync_strict`
  - Escalate Send/Sync spawn-boundary diagnostics to compile errors.
  - Useful in CI to forbid capturing borrow-only (`rust.Ref`, `rust.MutRef`, slices) or `Dynamic`
    values in `Thread.create(...)` / `Tasks.spawn(...)` closures.

## Lane metadata

- `@:haxeMetal`
  - Canonical portable-lane metadata for strict metal island enforcement.
- `@:rustMetal`
  - Compatibility alias; supported for migration, but new code should use `@:haxeMetal`.

## Notes on defaults

- If no string mode define is provided:
  - portable defaults to `rust_string_nullable`.
  - metal defaults to non-null string mode.
- `target.name` is read internally by compiler macros; users typically do not set it directly.

## Related docs

- `docs/profiles.md`
- `docs/metal-profile.md`
- `docs/async-await.md`
- `docs/workflow.md`
- `docs/interop.md`
- `docs/v1.md`
