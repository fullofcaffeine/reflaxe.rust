# Feature Support Matrix

This page is the evidence-backed support map for `reflaxe.rust`.

Read it as a contract, not marketing copy:

1. A surface is only "supported" here when there is CI evidence behind it.
2. Portable support and Rust-native support are different contracts and are called out separately.
3. Target-specific packages outside the Rust lane are intentionally out of scope.
4. Compile/inventory closure is not the same as runtime semantic parity.
5. Prose docs explain evidence; they do not count as primary proof by themselves.

## Support Contract

`reflaxe.rust` uses three support classes:

| Class | Meaning |
| --- | --- |
| `portable contract` | Part of the cross-target Haxe-facing surface. Changes here must preserve portable semantics and stay covered by the portable CI gates. |
| `native Rust contract` | Supported only as a Rust-target-specific surface. This can be ergonomic and high-performance, but it is not portable by definition. |
| `out of scope` | Not part of the Rust target contract. These namespaces may exist on other Haxe targets, but they are not promised here. |

## Evidence Tiers

The matrix below is grounded in explicit CI artifacts and gates:

| Evidence tier | What it proves | What it does not prove | Source |
| --- | --- | --- | --- |
| `snapshot` | Deterministic generated Rust shape plus targeted smoke behavior | Broad runtime parity for an entire module family | `test/run-snapshots.sh`, `test/snapshot/**` |
| `semantic-diff` | Runtime behavior parity against Haxe `--interp` for targeted contracts | Blanket parity outside the covered fixtures | `python3 test/run-semantic-diff.py`, `test/semantic_diff/**` |
| `tier1 sweep` | Curated upstream stdlib compile/fmt/check coverage for the most critical portable modules | Runtime parity by itself | `bash test/run-upstream-stdlib-sweep.sh`, `test/upstream_std_modules.txt` |
| `tier2 sweep` | Broader upstream stdlib compile/fmt/check coverage and CI gate coverage | Runtime parity by itself | `bash test/run-upstream-stdlib-sweep.sh --tier tier2`, `test/upstream_std_modules_tier2.txt` |
| `candidate audit` | Machine-readable inventory closure for portable-scope upstream modules | Semantic closure | `docs/portable-stdlib-candidates.json`, `docs/portable-stdlib-candidates.md` |
| `examples/windows smoke` | Platform-sensitive end-to-end confidence on curated scenarios | Broad contract closure for the whole package family | `examples/**`, `bash scripts/ci/windows-smoke.sh` |

## Current Evidence Snapshot

Current repository-backed counts:

- Tier1 sweep list: `96` modules (`test/upstream_std_modules.txt`)
- Tier2 sweep list: `224` modules (`test/upstream_std_modules_tier2.txt`)
- Portable candidate audit: `184` importable upstream portable modules, `184` covered in Tier2, `0` missing (`docs/portable-stdlib-candidates.json`)
- Semantic-confidence rollup artifact: `docs/semantic-confidence-summary.json` + `docs/semantic-confidence-summary.md`

Important interpretation rule:

- Tier2 + candidate audit together are strong coverage/inventory signals.
- They are not, by themselves, proof that all `184` portable-scope modules are runtime-semantic-parity complete.

Portable scope roots for that candidate audit are:

- `Std`
- `StringTools`
- `Math`
- `Date`
- `haxe.*`
- `sys.*`

Target-specific namespace prefixes intentionally excluded from the portable contract are:

- `cpp.*`
- `cs.*`
- `hl.*`
- `java.*`
- `js.*`
- `jvm.*`
- `lua.*`
- `neko.*`
- `php.*`
- `python.*`
- `rust.*`

## Package Scope Matrix

| Surface | Contract status | Primary CI evidence | Notes |
| --- | --- | --- | --- |
| `Std`, `StringTools`, `Math`, `Date` | `portable contract` | Tier1 + Tier2 sweeps, snapshots, semantic-diff, candidate audit | Core portable surface with the strongest current proof depth. `test/snapshot/string_substring` covers Haxe-compatible `String.substring(...)` lowering, including `start > end` swap behavior. |
| `haxe.*` | `portable contract` | Tier1 + Tier2 sweeps, snapshots, semantic-diff, candidate audit | Broad portable lane, but proof depth still varies by family. Do not read this row as blanket runtime parity for every `haxe.*` module. |
| `sys.*` | `portable contract` on Rust-supported platforms | Tier1 + Tier2 sweeps, targeted snapshots/examples, candidate audit | Platform-sensitive by nature. Contract status is real, but proof depth is still mixed across `sys.*` families and operating-system-specific failure paths. Read `docs/systems-environment-posture.md` for the canonical systems proof-depth classification. |
| admitted `reflaxe.std` surfaces | `portable contract` | `test/semantic_diff/portable_option_result_basics`, `test/snapshot/reflaxe_std_option_result`, `test/snapshot/rust_reflaxe_std_adapters` | Compiler-admitted shared portable idiom layer. v1 currently starts with `Option` / `Result`, but canonical module definitions are not bundled by this haxelib today; future surfaces need their own admitted facade contract. |
| `rust.*` | `native Rust contract` | Rust-first snapshots/examples and contract diagnostics | Supported as target-native API. Importing these from portable app code warns by default and can error under `-D rust_portable_native_import_strict`. |
| `rust.metal.*` | `native Rust contract` (`metal` lane) | Metal snapshots, negative policy fixtures, metal report/guard checks | Typed low-level Rust escape hatch for metal code. Not portable. |
| `cpp.*`, `cs.*`, `hl.*`, `java.*`, `js.*`, `jvm.*`, `lua.*`, `neko.*`, `php.*`, `python.*` | `out of scope` | None | These namespaces are not part of the Rust backend support promise. |

## Portable Stdlib Families

The table below keeps the per-package story explicit so "supported" does not collapse into one vague word.

| Family | Status | Evidence | Notes |
| --- | --- | --- | --- |
| `haxe.io.*` | Portable contract with targeted runtime parity on key surfaces | Tier1 + Tier2 sweeps, `test/semantic_diff/bytes_extended_api`, `test/snapshot/bytes_ops`, `test/snapshot/sys_io` | `Bytes`, IO helpers, and numeric packing paths are exercised directly. |
| `haxe.Json` / `haxe.format.Json*` | Portable contract with runtime parity coverage | Tier1 + Tier2 sweeps, `test/semantic_diff/json_stringify_replacer`, `test/snapshot/haxe_crypto_smoke` | Replacer behavior is covered explicitly. |
| selected `Type.*` reflection | Qualified portable stable candidate | `npm run test:reflection-contract`, `test/semantic_diff/type_reflection_registry`, upstream `haxe.Serializer` / `haxe.Unserializer` generated-Cargo check | Static names plus closed-world public non-extern class/enum resolution, runtime name lookup, and enum-constructor listing are covered, including secondary-type naming, declaration order, null-on-missing, and single evaluation. Dynamic construction remains experimental: direct application calls are rejected with `HXRS-REFLECTION-UNSUPPORTED`, while retained framework branches fail through a Haxe-catchable error rather than `todo!()`, a fake null, or an anonymous substitute. `haxe.CallStack` is separately protected only at the API-shape level; non-empty frames and exact formatting are not yet promised. |
| `haxe.Int32` / `haxe.Int64*` | Portable contract with runtime parity coverage | Tier1 + Tier2 sweeps, `test/semantic_diff/int64_parity` | Integer helper parity is part of the stdlib gate, not best-effort. |
| `haxe.iterators.*` | Portable contract | Tier1 + Tier2 sweeps, `test/semantic_diff/map_key_value_iterator_manual`, `test/semantic_diff/anonymous_key_value_aliasing`, `test/semantic_diff/anonymous_iterator_aliasing`, `test/semantic_diff/iterator_helper_boundary`, `test/semantic_diff/array_key_value_iterator_boundary`, `test/semantic_diff/dynamic_access_iterator_boundary`, `test/semantic_diff/unicode_string_iterator_boundary` | Includes Rust-side implementations of map, DynamicAccess, ordinary string, and Unicode string iterator forms; iterator items preserve ordinary anonymous-record aliasing and identity. Mutable function-field records that structurally satisfy `hasNext` / `next` also preserve record identity, mutation, reentrant callbacks, and Haxe `for` behavior rather than being coerced into the native iterator adapter. The nominal array forms cross typed helper boundaries through direct compiler-owned adapters. DynamicAccess forms snapshot keys but retain live value lookup and use a narrow callback-backed bridge only when crossing the structural iterator ABI. Unicode string forms yield scalar code points and logical scalar keys rather than UTF-8 bytes or UTF-16 surrogate halves. These boundaries avoid references to absent upstream std modules; erased source generics use the already-specialized Haxe call type rather than a runtime carrier. |
| `sys.io.*`, `Sys`, `sys.FileSystem` | Portable contract, operation-qualified | Tier1 + Tier2 sweeps, `test/snapshot/sys_io`, `test/snapshot/sys_getenv_null`, `test/semantic_diff/sys_core_failure_paths`, `test/semantic_diff/sys_process_failure_paths`, `npm run test:portable-sys-failures` | Invalid cwd, malformed environment input, and direct-spawn failures are catchable and continue execution; stdin EOF remains distinct from typed stream errors; broken stdout/stderr are catchable rather than Rust panics. `Sys.cpuTime` and non-Windows concurrent `Sys.putEnv` remain explicitly experimental, and this evidence is not blanket cross-platform closure. |
| `sys.Http` | Portable contract | Tier1 + Tier2 sweeps, `test/semantic_diff/sys_http_callback_contract`, `test/snapshot/sys_http_smoke`, `test/snapshot/http_base_override_contract` | Request bodies, multipart, nullable header lookup, callback-surface behavior, and the local-server status/error callback boundary are part of the current Rust-target contract. Proof depth is now targeted parity plus smoke-backed request/response coverage, not blanket host/network semantic parity. |
| `sys.net.*` | Portable contract | Tier1 + Tier2 sweeps, `test/semantic_diff/sys_net_failure_paths`, `examples/chat_loopback`, `examples/sys_net_loopback` | TCP select/connect-failure behavior now has targeted parity coverage. UDP and broader platform-specific behavior still rely more on smoke/example evidence than on broad semantic-diff coverage. |
| `sys.ssl.*` | Portable contract | Tier1 + Tier2 sweeps, `test/snapshot/sys_ssl_sni` | Includes build-checked SNI certificate-selection coverage on the Rust target. Broader TLS behavior remains platform- and environment-sensitive. |
| `sys.thread.*` | Portable contract | Tier1 + Tier2 sweeps, `npm run test:thread-event-loop-lifecycle`, `test/snapshot/sys_thread_event_loop`, `test/snapshot/sys_thread_event_loop_repeat_cancel`, `test/snapshot/sys_thread_deque_basic`, `test/snapshot/sys_thread_elastic_thread_pool_smoke`, `test/snapshot/haxe_mainloop_entrypoint_basic`, `test/snapshot/haxe_mainloop_entrypoint_thread_bridge`, `examples/sys_thread_smoke`, `examples/thread_pool_smoke` | Spawned-thread liveness cleanup, dead-send rejection, repeat callback unwind/cancel state, and promise balance have isolated target-process proof. Direct `sys.thread.EventLoop` behavior also includes repeating callback `repeat(...)/cancel(...)` snapshots, and `Deque`, `FixedThreadPool`, and `ElasticThreadPool` have Rust-target smoke coverage. Broader `haxe.MainLoop` / `haxe.EntryPoint` scheduler parity remains caveat-heavy and is not claimed as `--interp`-backed semantic parity. |
| `sys.db.*` | Portable Rust-target contract | Tier2 sweep, `test/snapshot/sys_db_sqlite_smoke`, `test/snapshot/sys_db_mysql_compile` | Supported on the Rust target; current evidence is split between SQLite runtime smoke (`:memory:`) and MySQL compile-only dependency/codegen coverage, and still depends on native library availability in the destination environment. |

## Language / Profile Matrix

| Surface | Status | Evidence |
| --- | --- | --- |
| Core language lowering (control flow, classes, inheritance, properties, enums, exceptions, generics, function values) | Supported | Snapshot suite, semantic-diff suite, full harness | Exception behavior is covered on key lanes, including subtype-aware typed catch for emitted non-generic class and interface hierarchies. Generic helper payload-bound propagation is covered by `test/snapshot/generic_helper_payload_bounds`, unconstrained helpers stay bare in `test/snapshot/generic_function_type_params`, and concrete/multi-level superclass plus inherited-interface specialization is covered by `test/semantic_diff/generic_base_specialization` and `test/semantic_diff/generic_interface_specialization` without runtime erasure. Copy-like numeric array-index updates preserve Haxe evaluation/result semantics in `test/semantic_diff/array_index_updates`; typed String element append, including current-value-before-RHS ordering and clone-free statement lowering, is covered by `test/semantic_diff/array_string_element_append`; nullable primitive and reusable-reference array literals preserve typed coercion, evaluation order, and aliasing in `test/semantic_diff/nullable_array_literals`. Anonymous records retain shared aliasing, typed mutation, and identity for both the common `{ key, value }` shape and mutable function-field records that also satisfy the Haxe iterator protocol (`test/semantic_diff/anonymous_key_value_aliasing`, `test/semantic_diff/anonymous_iterator_aliasing`). Concrete, polymorphic, mutable static, accessor-backed, String, and Copy-like anonymous field updates are checked against RHS mutation of the same lvalue in `test/semantic_diff/field_compound_rhs_mutation`; the broader update surfaces remain covered by `test/semantic_diff/polymorphic_field_updates`, `test/semantic_diff/static_field_updates`, and `test/semantic_diff/static_property_updates`. Function-value coverage now includes `this.method` closures, reusable callback forwarding/storage, and mutable captured-local callback parity (`test/semantic_diff/function_value_mutable_callbacks`, `test/semantic_diff/closure_capture_mutation`, `test/semantic_diff/this_method_closure`). Remaining exact-type catch caveats are limited to generic classes or payloads without emitted subtype metadata. Haxe requires generic catch parameters to be `Dynamic`, while Rust retains concrete monomorph types; no implicit erased adapter is promised. See `docs/v1.md`. |
| `portable` profile contract | Supported | contract reports, snapshot/semantic diff coverage, portable native-import diagnostics guard | `docs/profiles.md` is explanatory guidance, not primary proof. |
| `metal` profile contract | Supported | negative metal fixtures, metal report/fallback guards, lane-diff gate | `docs/metal-profile.md` is explanatory guidance, not primary proof. |
| `rust_async` (`metal` only) | Experimental Rust-first preview | `test/snapshot/async_entry_boundary`, `test/snapshot/async_instance_method`, `test/snapshot/rust_async_tasks`, `examples/async_retry_pipeline`, async negative fixtures | Typed/codegen-backed on the documented metal + hxrt shapes, but excluded from stable-major admission. Task panic/throw mapping, cancellation/join/drop, resource release, shutdown, bounded workers, nested runtimes, adapter isolation, portable mode, `rust_no_hxrt`, async constructors, and async `main` are not promised. |
| `@:rustMetal` lanes inside portable builds | Supported | lane-diff CI gate, metal restriction pass, contract reports | `@:haxeMetal` remains a compatibility alias. Lane cleanliness is enforced, but lane cleanliness is not the same as blanket semantic closure for the entire program. |

## Source Of Truth Files

Use these files when changing support claims:

- `docs/v1.md`
- `docs/stdlib-policy.md`
- `docs/semantic-confidence-summary.json`
- `docs/semantic-confidence-summary.md`
- `test/upstream_std_modules.txt`
- `test/upstream_std_modules_tier2.txt`
- `docs/portable-stdlib-candidates.json`
- `docs/portable-stdlib-candidates.md`
- `docs/profiles.md`
- `docs/metal-profile.md`

If the support matrix changes, update the linked evidence in the same change. Do not move a surface to a stronger support class without adding the corresponding CI proof.
