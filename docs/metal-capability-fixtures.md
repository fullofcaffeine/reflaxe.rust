# Metal Capability Fixture Plan

This document is the contract-first fixture plan for `haxe.rust-oo3.74` ("Metal as haxified Rust").

It exists so metal compiler work starts from explicit positive and negative contracts rather than
from ad hoc lowering changes.

Use [Metal type surface gap matrix](metal-type-surface-gap-matrix.md) to decide whether a fixture
is proving an already-supported surface, closing a partial surface, or defining a missing surface.

## Rules

- Add or update the fixture before changing compiler/runtime behavior.
- Keep fixture names product-neutral.
- Prefer typed Haxe source and typed Rust-facing APIs over raw snippets.
- Add both positive and negative cases when a capability can fail by silently escaping the metal contract.
- Every metal-clean output-shape claim needs a generated Rust audit surface: snapshot diff, report artifact, rustfmt/warning gate, fallback baseline, or no-hxrt guard.
- If a fixture requires temporary fallback, record that fallback in the fixture name, hxml, or policy baseline. Do not let fallback look metal-clean.

## Existing Harness Owners

| Harness | Owns |
| --- | --- |
| `test/run-snapshots.sh` | Generated Rust shape, rustfmt, cargo build, targeted stdout snapshots. |
| `scripts/ci/check-metal-policy.sh` | Negative metal policy diagnostics, profile reports, contract reports, report determinism. |
| `scripts/ci/check-metal-fallback-counts.sh` | Deterministic ERaw fallback counts for curated metal examples/snapshots. |
| `scripts/ci/check-metal-idiom-counts.sh` | Deterministic clone/borrow/hxrt/Dynamic/native-shape counters for curated metal idiom fixtures. |
| `test/negative/**` | Compile-time rejections for raw Rust, Dynamic/reflection, no-hxrt misuse, borrow capture, and metal islands. |
| `test/positive/**` | Small positive compile contracts, especially no-hxrt and strict profile checks. |
| `test/semantic_diff/**` | Runtime parity where Haxe interp is a valid oracle. This is usually secondary for Rust-native metal APIs. |
| `examples/**` | End-to-end Rust-first app surfaces and `@:rustTest`-backed native test suites. |

## Capability Matrix

| Capability area | Existing evidence | Missing contract-first fixtures | Gate owner |
| --- | --- | --- | --- |
| Scoped borrows and slices | `test/snapshot/rust_vec`, `test/snapshot/borrow_scope_tightening`, `test/snapshot/rust_array_slice_views` output-shape gate in `scripts/ci/check-metal-policy.sh`, `test/positive/borrow_literal_derivation`, `test/positive/borrow_alias_derivation`, `test/positive/borrow_wrapper_derivation`, `test/positive/borrow_mut_disjoint_scopes`, `test/negative/send_sync_borrow_capture`, `test/negative/send_sync_str_capture`, `test/negative/metal_ref_escape`, `test/negative/metal_ref_return_escape`, `test/negative/metal_ref_assignment_escape`, `test/negative/metal_ref_literal_escape`, `test/negative/metal_ref_closure_escape`, `test/negative/metal_ref_alias_tail_escape`, `test/negative/metal_ref_alias_return_escape`, `test/negative/metal_ref_alias_field_storage_escape`, `test/negative/metal_ref_alias_closure_storage_escape`, `test/negative/metal_ref_option_wrapper_escape`, `test/negative/metal_ref_object_wrapper_escape`, `test/negative/metal_ref_helper_wrapper_escape`, `test/negative/metal_ref_throw_escape`, `test/negative/metal_mut_ref_escape`, `test/negative/metal_mut_ref_nested_overlap`, `test/negative/metal_slice_escape`, `test/negative/metal_slice_alias_return_escape`, `test/negative/metal_mut_slice_escape`, `test/negative/metal_mut_slice_nested_overlap`, `test/negative/metal_mut_region_sibling_overlap` | Richer source provenance and richer unknown-closure flow | snapshot + negative policy + output-shape |
| Traits, impls, and bounds | `test/snapshot/rust_impl_meta`, `test/snapshot/generics_interface`, `test/snapshot/metal_trait_impl_bounds`, `test/snapshot/metal_trait_object_boundary` | `test/negative/metal_trait_bound_missing`, associated-type and richer where-clause fixtures | snapshot + cargo build |
| Typed mini-DSL authority | `test/snapshot/metal_typed_injection`, `test/negative/metal_stringly_dsl_app_api`, `test/negative/metal_dsl_bypasses_policy`, raw app-side negative fixtures | `test/snapshot/metal_typed_dsl_contract` | snapshot + metal policy |
| Extern and lifetime islands | `@:native`, `@:rustCargo`, `@:rustExtraSrc` examples, `docs/extern-lifetime-island-cookbook.md`, `test/snapshot/metal_extern_lifetime_island` | `test/negative/metal_extern_unsafe_surface`, richer cookbook example with cargo test | snapshot + example smoke |
| RAII guards | `docs/raii-guard-lifetime-islands.md`, `test/positive/metal_raii_guard_scoped`, `test/negative/metal_raii_guard_escape`, HXRT concurrent scoped-guard tests | File/socket/transaction scoped facade fixtures | positive/negative + runtime tests |
| no-hxrt minimal runtime | `test/positive/metal_no_hxrt_minimal`, `test/positive/metal_no_hxrt_native_file`, `test/negative/metal_no_hxrt_runtime_boundary`, `test/negative/metal_no_hxrt_requires_metal`, `test/negative/metal_no_hxrt_dynamic_boundary`, `test/negative/metal_no_hxrt_reflection_boundary`, `test/negative/metal_no_hxrt_platform_boundary` | `test/snapshot/metal_no_hxrt_option_result_values`, future portable no-hxrt facade subset fixtures | positive/negative + cargo check |
| Rust-native systems facades | `docs/metal-systems-facades-roadmap.md`, `std/rust/fs/NativeFiles.hx`, `std/rust/process/NativeCommands.hx`, `std/rust/process/CommandOutput.hx`, `std/rust/process/CommandEnv.hx`, `std/rust/process/CommandSpec.hx`, `std/rust/process/CommandError.hx`, `std/rust/process/CommandChild.hx`, `std/rust/net/NativeTcp.hx`, `std/rust/net/TcpListener.hx`, `std/rust/net/TcpStream.hx`, `std/rust/net/NativeUdp.hx`, `std/rust/net/UdpSocket.hx`, `std/rust/net/SocketError.hx`, `test/positive/metal_no_hxrt_native_file`, `test/negative/metal_fs_raw_escape`, `test/positive/metal_no_hxrt_native_process`, `test/positive/metal_no_hxrt_command_output`, `test/positive/metal_no_hxrt_command_cwd`, `test/positive/metal_no_hxrt_command_env`, `test/positive/metal_no_hxrt_command_env_ops`, `test/positive/metal_no_hxrt_command_cwd_env`, `test/positive/metal_no_hxrt_command_stdin`, `test/positive/metal_no_hxrt_command_stdin_cwd_env`, `test/positive/metal_no_hxrt_command_spec`, `test/positive/metal_no_hxrt_command_error`, `test/positive/metal_no_hxrt_command_child`, `test/positive/metal_no_hxrt_native_tcp`, `test/positive/metal_no_hxrt_native_udp`, `test/positive/metal_no_hxrt_socket_error`, `test/negative/metal_process_raw_escape` | TLS/DB after file/process/TCP/UDP patterns are proven; reusable stdin pipes, live output streams, detached handles, async, shell fallback, arbitrary host/address networking, byte-buffer datagrams, and TLS remain future work | positive/negative + output-shape + cargo check/run |
| Dynamic/reflection boundaries | `test/negative/metal_dynamic_access`, `test/negative/metal_reflect`, `test/negative/metal_type_reflection` | `test/negative/metal_dynamic_dsl_payload`, `test/negative/metal_reflect_trait_boundary` | metal policy |
| Metal islands in portable builds | `test/negative/metal_island_*`, contract report cases | `test/snapshot/portable_with_metal_trait_island`, `test/negative/metal_island_lifetime_escape` | metal policy + contract report |
| Idiomatic output shape | fallback baseline, metal idiom count baseline, rustfmt/cargo build in snapshots, portable facade output-shape gate, slice-view output-shape gate | Broader value/module-path fixture coverage such as future `test/snapshot/metal_idiom_values` | snapshot + fallback/count baselines + output-shape |
| Capability-driven portable facades | `test/snapshot/reflaxe_std_option_result`, `test/snapshot/rust_reflaxe_std_adapters`, `test/snapshot/portable_facade_native_option_result`, `test/snapshot/portable_facade_contract_report`, `test/positive/portable_native_typed_report`, `test/negative/portable_native_typed_strict`, `test/negative/runtime_fallback_reason_dynamic`, `docs/reflaxe-std-adoption-contract.md` | Future portable no-hxrt eligibility fixtures and future admitted collection facades such as a portable `Vec` contract. | snapshot + report + output-shape + no-hxrt eligibility |

## First Wave

Implement these before broad compiler work in the milestone:

1. `test/negative/metal_ref_escape`
   - Proves `rust.Ref<T>` cannot directly escape its lexical region in metal-clean code.
   - Implemented as a metal-policy negative case owned by `scripts/ci/check-metal-policy.sh`.

2. `test/negative/metal_mut_ref_escape`
   - Proves `rust.MutRef<T>` cannot directly escape its lexical region in metal-clean code.
   - Implemented as a metal-policy negative case owned by `scripts/ci/check-metal-policy.sh`.

3. `test/negative/metal_slice_escape`
   - Proves `rust.Slice<T>` cannot directly escape its lexical region in metal-clean code.
   - Implemented as a metal-policy negative case owned by `scripts/ci/check-metal-policy.sh`.

4. `test/negative/metal_mut_slice_escape`
   - Proves `rust.MutSlice<T>` cannot directly escape its lexical region in metal-clean code.
   - Implemented as a metal-policy negative case owned by `scripts/ci/check-metal-policy.sh`.

5. `test/snapshot/metal_trait_impl_bounds`
   - Proves one Haxe-facing trait/impl/bound shape lowers to warning-clean Rust.
   - Implemented as a metal snapshot with `@:rustImpl`, class-level `@:rustGeneric`, and a bounded
     extern helper backed by hand-written Rust.

6. `test/snapshot/metal_trait_object_boundary`
   - Proves Haxe interfaces remain the admitted trait-object boundary for ordinary Haxe polymorphism
     in metal output.
   - Implemented as a metal snapshot with a Haxe interface, implementation class, and interface-typed
     call boundary.

7. `test/negative/metal_stringly_dsl_app_api`
   - Proves app-level stringly Rust DSLs do not bypass typed `rust.metal` authority policy.
   - Implemented as a metal-policy negative case that rejects direct app-side
     `rust.metal.Code.expr(...)` without `@:rustAllowRaw`.

8. `test/negative/metal_dsl_bypasses_policy`
   - Proves scoped raw authority still does not bypass metal-island raw fallback restrictions.
   - Implemented as a metal-policy negative case with `@:rustAllowRaw` + `@:haxeMetal`.

9. `test/snapshot/metal_extern_lifetime_island`
   - Proves a lifetime-heavy Rust helper can sit in a handwritten Rust module behind a typed Haxe facade.
   - Expected owner: `test/run-snapshots.sh` plus a narrow example/cargo test if runtime behavior matters.

10. `scripts/ci/check-metal-idiom-counts.sh`
   - Proves native `Option`, `Result`, `Vec`, slice, and borrow-shaped fixtures keep deterministic
     clone/borrow/hxrt/Dynamic/raw fallback counters.
   - Uses existing fixture families (`rust_vec`, `rust_array_slice_views`,
     `portable_facade_native_option_result`, and `metal_no_hxrt_minimal`) so the first idiom gate is
     tied to real generated output instead of a synthetic fixture.
   - Expected owner: `test/run-snapshots.sh`, `scripts/ci/check-metal-fallback-counts.sh`, and
     `scripts/ci/check-metal-idiom-counts.sh`.

Capability-driven portable-facade work should add, in order:

This first wave covers admitted `reflaxe.std` facade surfaces. It is not a blanket claim
that upstream Haxe stdlib APIs are Rust-native facades: upstream `Std`, `haxe.*`,
`sys.*`, `Array<T>`, and similar APIs need their own explicit std-lowering contracts,
fixtures, or runtime fallback reasons before they can be treated as native Rust shapes.

- `test/snapshot/portable_facade_native_option_result`
  - Proves admitted portable facade source lowers to native Rust `Option` and `Result` on the Rust target.
  - Implemented as a minimal Rust-output snapshot that avoids unrelated `Sys.println` / string output noise.
  - Also owned by a metal-policy output-shape gate: the generated user module must contain native
    Rust `Option<i32>` / `Result<i32, i32>` signatures and constructors, and must not route those
    values through `hxrt::dynamic`, `hxrt::array`, raw `__rust__`, or raw `ERaw` markers.
- `test/snapshot/portable_facade_contract_report`
  - Proves `contract_report.*` records consumed facade surfaces, stable surface IDs, selected native representations, and no hidden `rust.*` import requirement.
  - Implemented as a deterministic report snapshot plus a metal-policy case that checks surface IDs,
    native representation reasons, `requiresRustImport: false`, and no source-text or typed native-import hits.
- `test/positive/portable_native_typed_report`
  - Proves `contract_report.*` records user-source typed `rust.*` usage even when no `import rust.*`
    line exists.
  - Implemented as a metal-policy report case that checks `nativeImportHits` is empty while
    `nativeImportHitsTyped` records the fully-qualified `rust.Option` surface.
- `test/negative/portable_native_typed_strict`
  - Proves typed native usage participates in strict portable boundary enforcement, not only report
    rendering.
  - Implemented as a metal-policy negative case that rejects fully-qualified `rust.Option` usage
    under `-D rust_portable_native_import_strict`.
- `test/negative/runtime_fallback_reason_dynamic`
  - Proves `runtime_plan.*` records a stable semantic fallback reason such as `dynamic` before generated code happens to reference `hxrt`.
  - Implemented as a runtime-plan policy fixture that records `reasonKind: dynamic` for
    `haxe.DynamicAccess`.
- Future `test/positive/portable_facade_no_hxrt_subset`
  - Proves a portable facade subset can compile with `rust_no_hxrt` only after positive eligibility fixtures exist. Today `rust_no_hxrt` remains metal-only.
- Future `test/negative/portable_facade_no_hxrt_dynamic_fallback`
  - Proves unsupported portable semantics fail under future portable `rust_no_hxrt` with a diagnostic that names the runtime fallback reason.
- Future `test/snapshot/portable_facade_native_vec`
  - Proves a portable collection facade lowers to Rust `Vec<T>` only after a concrete `reflaxe.std` collection contract is admitted. Do not use this fixture to imply ordinary Haxe `Array<T>` is a no-runtime `Vec<T>` facade.

## Failure Policy

- New negative fixtures must fail before implementation unless they document an already-existing rejection.
- Positive snapshots may start as compile-only contracts, but they must still run through rustfmt and cargo build.
- A metal-clean fixture must not pass by enabling `rust_metal_allow_fallback` unless the fixture name and acceptance text explicitly make fallback the behavior under test.
- Increases in ERaw fallback counts, generated hxrt use in no-hxrt fixtures, Dynamic usage, or borrow-guard bloat are regressions unless the owning bead updates a deterministic baseline with rationale.
- Runtime semantic-diff is required only when Haxe interp is a valid oracle. Rust-native ownership, borrow, no-hxrt, and extern-island contracts should prefer generated Rust shape plus cargo/rustfmt/policy gates.

## Beads Mapping

| Bead | Fixture responsibility |
| --- | --- |
| `haxe.rust-oo3.74.2` | Borrow/lifetime positive and negative fixtures. |
| `haxe.rust-oo3.74.3` | Trait, impl, where-bound, associated-type, and trait-object fixtures. |
| `haxe.rust-oo3.74.4` | Type-surface gap matrix and fixture coverage status per type. |
| `haxe.rust-oo3.74.5` | Typed DSL positive and negative fixtures. |
| `haxe.rust-oo3.74.6` | Idiomatic-output gates and deterministic fail/baseline thresholds. |
| `haxe.rust-oo3.74.7` | Extern/lifetime-island cookbook fixture and example. |
| `haxe.rust-oo3.74.9` | Capability-driven portable facade lowering, no-hxrt eligibility, and fallback-reason fixtures. |
| `haxe.rust-oo3.74.9.2` | Surface contract schema and consumed-surface report fields. |
| `haxe.rust-oo3.74.9.3` | Semantic runtime fallback reason schema and `runtime_plan.*` ledger fields. |
| `haxe.rust-oo3.74.9.4` | Source/typed-AST no-hxrt eligibility fixtures before future portable no-runtime support. |
| `haxe.rust-oo3.74.9.5` | First Option/Result portable facade report fixtures. |
| `haxe.rust-oo3.74.9.6` | Deferred portable Vec facade admission criteria. |
| `haxe.rust-oo3.74.9.7` | Typed native/facade surface usage reporting. |
| `haxe.rust-oo3.74.9.8` | Portable facade output-shape gates. |
| `haxe.rust-oo3.74.14` | Wrapper/helper/object/throw borrow-token escape fixtures. |
| `haxe.rust-oo3.74.15` | No-clone Array slice-view output-shape gate. |
| `haxe.rust-oo3.74.16` | Scoped RAII guard callbacks and lifetime-island selection rules. |
| `haxe.rust-oo3.75` | Rust-native systems facades and no-hxrt proof. |
| `haxe.rust-oo3.75.2` | Native file/path contract fixtures and raw-escape negative fixture. |
| `haxe.rust-oo3.75.3` | `rust.fs.NativeFiles` typed facade and narrow Rust helper module. |
| `haxe.rust-oo3.75.4` | Native file no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.75.5` | Systems-facade docs, FAQ, README, and evidence refresh. |
| `haxe.rust-oo3.76.2` | Native process owned-command contract fixtures and raw-escape negative fixture. |
| `haxe.rust-oo3.76.3` | First `rust.process` typed facade and narrow Rust helper module. |
| `haxe.rust-oo3.76.4` | Native process no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.77.1` | Native command-output status/stdout/stderr contract fixture. |
| `haxe.rust-oo3.77.2` | `rust.process.CommandOutput` typed facade and helper implementation. |
| `haxe.rust-oo3.77.3` | Command-output no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.78.1` | Native command cwd behavior contract fixture. |
| `haxe.rust-oo3.78.2` | `statusCodeInDir` / `outputUtf8InDir` typed facade implementation. |
| `haxe.rust-oo3.78.3` | Command cwd no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.79.1` | Native command env override behavior contract fixture. |
| `haxe.rust-oo3.79.2` | `CommandEnv` / env-aware typed facade implementation. |
| `haxe.rust-oo3.79.3` | Command env no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.80.1` | Native command env remove/clear behavior contract fixture. |
| `haxe.rust-oo3.80.2` | `CommandEnv.remove` / `CommandEnv.clear` typed facade implementation. |
| `haxe.rust-oo3.80.3` | Command env remove/clear no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.81.1` | Native command cwd+env behavior contract fixture. |
| `haxe.rust-oo3.81.2` | `statusCodeInDirWithEnv` / `outputUtf8InDirWithEnv` typed facade implementation. |
| `haxe.rust-oo3.81.3` | Command cwd+env no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.82.1` | Native command stdin-input behavior contract fixture. |
| `haxe.rust-oo3.82.2` | `statusCodeWithStdin` / `outputUtf8WithStdin` typed facade implementation. |
| `haxe.rust-oo3.82.3` | Command stdin-input no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.83.1` | Native command stdin+cwd+env behavior contract fixture. |
| `haxe.rust-oo3.83.2` | `statusCodeInDirWithEnvAndStdin` / `outputUtf8InDirWithEnvAndStdin` typed facade implementation. |
| `haxe.rust-oo3.83.3` | Command stdin+cwd+env no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.84.1` | Native command-spec behavior contract fixture. |
| `haxe.rust-oo3.84.2` | `CommandSpec` / `statusCodeFromSpec` / `outputUtf8FromSpec` typed facade implementation. |
| `haxe.rust-oo3.84.3` | CommandSpec no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.85.1` | Native command-error behavior contract fixture. |
| `haxe.rust-oo3.85.2` | `CommandError` / detailed command and output helpers typed facade implementation. |
| `haxe.rust-oo3.85.3` | CommandError no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.86.1` | Native command-child lifecycle behavior contract fixture. |
| `haxe.rust-oo3.86.2` | `CommandChild` / `spawnChildFromSpec` typed facade implementation. |
| `haxe.rust-oo3.86.3` | CommandChild no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.87.1` | Native TCP localhost round-trip behavior contract fixture. |
| `haxe.rust-oo3.87.2` | `rust.net.NativeTcp`, `TcpListener`, and `TcpStream` typed facade implementation. |
| `haxe.rust-oo3.87.3` | Native TCP no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.88.1` | Native UDP localhost datagram round-trip behavior contract fixture. |
| `haxe.rust-oo3.88.2` | `rust.net.NativeUdp` and `UdpSocket` typed facade implementation. |
| `haxe.rust-oo3.88.3` | Native UDP no-hxrt output-shape gate in the metal policy script. |
| `haxe.rust-oo3.89.1` | SocketError typed TCP/UDP error contract fixture. |
| `haxe.rust-oo3.89.2` | `rust.net.SocketError` and Detailed TCP/UDP typed facade implementation. |
| `haxe.rust-oo3.89.3` | SocketError no-hxrt output-shape gate in the metal policy script. |

## Closeout Checklist For New Metal Capability Fixtures

- Fixture source is typed Haxe unless the boundary under test is explicitly a framework/native facade.
- The hxml states the intended contract: `portable`, `metal`, `@:haxeMetal`, `rust_no_hxrt`, fallback allowed, or fallback forbidden.
- Diagnostics anchor to project source for negative cases where possible.
- Generated Rust is inspected for ownership, allocation, module paths, `Dynamic`, `hxrt`, raw `ERaw`, clone noise, and borrow-guard scope.
- The owning script runs locally and is wired to the relevant aggregate guard before the bead closes.
