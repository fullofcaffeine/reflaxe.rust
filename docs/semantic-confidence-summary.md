# Semantic Confidence Summary

This file is generated deterministically by `node scripts/ci/generate-semantic-confidence-summary.js --write`.

## Why

Reviewers need a machine-generated answer to a narrow question: what is compile-covered, what is backed by targeted semantic/runtime parity, and what is still only snapshot/smoke confidence?

## What

This summary rolls up the current evidence buckets without pretending that Tier2 inventory closure or a green harness automatically imply blanket runtime parity.

## How

- Reads Tier1/Tier2 module lists and the portable stdlib candidate audit.
- Discovers semantic-diff / lane-diff / snapshot case counts directly from the repo.
- Categorizes explicit high-risk buckets with file-backed evidence references.
- Emits stable JSON/Markdown with no timestamps or machine-local paths.

## Coverage Counts

- Tier1 sweep modules: `96`
- Tier2 sweep modules: `224`
- Portable candidate importable modules: `184`
- Portable candidate covered in Tier2: `184`
- Portable candidate missing from Tier2: `0`
- Portable semantic-diff cases: `23`
- Lane semantic-diff cases: `2`
- Snapshot cases: `138`
- Compile/inventory buckets: `2`
- Targeted semantic/runtime buckets: `7`
- Snapshot/smoke-only buckets: `7`

## Portable Scope

- Included roots: `Std`, `StringTools`, `Math`, `Date`, `haxe.`, `sys.`
- Excluded target-specific prefixes: `cpp.`, `cs.`, `hl.`, `java.`, `js.`, `jvm.`, `lua.`, `neko.`, `php.`, `python.`, `rust.`

## Compile / Inventory Closure

### Portable stdlib inventory closure
- Class: `compile_inventory`
- Scope: Portable upstream std roots (`Std`, `StringTools`, `Math`, `Date`, `haxe.*`, `sys.*`)
- Evidence:
  - `test/upstream_std_modules.txt`
  - `test/upstream_std_modules_tier2.txt`
  - `docs/portable-stdlib-candidates.json`
  - `scripts/ci/audit-upstream-stdlib-candidates.js`
- Commands:
  - `bash test/run-upstream-stdlib-sweep.sh`
  - `bash test/run-upstream-stdlib-sweep.sh --tier tier2`
  - `npm run guard:stdlib-candidates`
  - `npm run guard:stdlib-candidate-gap`
- Notes: Strong inventory and compile/fmt/check closure. Not blanket runtime semantic parity.

### Family std governance sync
- Class: `compile_inventory`
- Scope: Local family bootstrap + pin synchronization
- Evidence:
  - `family/family_std_pin.json`
  - `test/portable_allowlist.json`
  - `test/portable_conformance_tier1.json`
  - `tools/family_std_sync.py`
  - `family/reflaxe.family.std/tools/verify_family_std.py`
- Commands:
  - `npm run test:family-stdlib-bootstrap`
  - `npm run test:family-stdlib-sync`
- Notes: Governance and contract sync proof. Not runtime proof by itself.

## Targeted Semantic / Runtime Parity

### Portable core contract semantics
- Class: `targeted_semantic_parity`
- Scope: Null strings, typed/dynamic exceptions, class/interface subtype-aware catches, generic base/interface specialization, polymorphic/static field updates, virtual dispatch, env vars, function-value parity, portable Option/Result
- Evidence:
  - `test/semantic_diff/null_string_concat`
  - `test/semantic_diff/exceptions_typed_dynamic`
  - `test/semantic_diff/typed_catch_interface`
  - `test/semantic_diff/typed_catch_subclass`
  - `test/semantic_diff/generic_base_specialization`
  - `test/semantic_diff/generic_interface_specialization`
  - `test/semantic_diff/polymorphic_field_updates`
  - `test/semantic_diff/static_field_updates`
  - `test/semantic_diff/virtual_dispatch`
  - `test/semantic_diff/sys_getenv_null`
  - `test/semantic_diff/function_value_mutable_callbacks`
  - `test/semantic_diff/closure_capture_mutation`
  - `test/semantic_diff/this_method_closure`
  - `test/semantic_diff/portable_option_result_basics`
  - `test/snapshot/array_shift_nullable_class_return`
- Commands:
  - `npm run test:semantic-diff`
  - `bash test/run-snapshots.sh --case array_shift_nullable_class_return`
- Notes: These are the current backbone portable semantic fixtures, not a claim about every portable surface.

### Portable vs `@:rustMetal` lane stability
- Class: `targeted_semantic_parity`
- Scope: Lane-clean programs must keep portable semantics when metal lanes are introduced
- Evidence:
  - `test/semantic_diff_lanes/lane_clean_arithmetic`
  - `test/semantic_diff_lanes/lane_clean_dispatch`
- Commands:
  - `npm run test:semantic-diff:lanes`
- Notes: Lane cleanliness is enforced separately; this bucket proves semantic stability for lane-clean programs.

### Dynamic / reflection / exception boundary behavior
- Class: `targeted_semantic_parity`
- Scope: High-risk dynamic receiver, reflection, and thrown Dynamic payload paths
- Evidence:
  - `test/semantic_diff/reflect_dynamic_receivers`
  - `test/semantic_diff/exception_dynamic_payload`
  - `test/semantic_diff/typed_catch_interface`
  - `test/semantic_diff/typed_catch_subclass`
  - `test/snapshot/reflect_basic`
  - `test/snapshot/reflect_compare_sort`
  - `test/snapshot/catch_dynamic`
- Commands:
  - `npm run test:semantic-diff`
  - `bash test/run-snapshots.sh --case reflect_basic`
  - `bash test/run-snapshots.sh --case reflect_compare_sort`
  - `bash test/run-snapshots.sh --case catch_dynamic`
- Notes: Targeted proof only. Emitted non-generic class and interface hierarchies now have subtype-aware typed catch parity; exact-type limits remain for generic classes and payloads without emitted subtype metadata.

### Portable stdlib runtime hotspots
- Class: `targeted_semantic_parity`
- Scope: Bytes, Json replacer, Int64, String substring, and iterator runtime behavior
- Evidence:
  - `test/semantic_diff/bytes_extended_api`
  - `test/semantic_diff/json_stringify_replacer`
  - `test/semantic_diff/int64_parity`
  - `test/semantic_diff/map_key_value_iterator_manual`
  - `test/snapshot/string_substring`
- Commands:
  - `npm run test:semantic-diff`
  - `bash test/run-snapshots.sh --case string_substring`
- Notes: Focused runtime parity on stdlib families that recently moved from stubs/workarounds to real support. String.substring coverage is snapshot-backed generated Rust plus stdout proof for bounded ASCII and start/end swap behavior.

### Process failure / exit behavior
- Class: `targeted_semantic_parity`
- Scope: stdout/stderr/exit-code and kill handling in portable process flows
- Evidence:
  - `test/semantic_diff/sys_process_failure_paths`
- Commands:
  - `python3 test/run-semantic-diff.py --case sys_process_failure_paths`
- Notes: Targeted parity only. This does not imply blanket cross-platform process semantics.

### Network failure-path behavior
- Class: `targeted_semantic_parity`
- Scope: TCP select/connect-failure behavior on portable socket flows
- Evidence:
  - `test/semantic_diff/sys_net_failure_paths`
- Commands:
  - `python3 test/run-semantic-diff.py --case sys_net_failure_paths`
- Notes: TCP failure-path parity is covered. UDP and broader platform-specific behavior still sit in the smoke bucket.

### HTTP callback / status / error boundary behavior
- Class: `targeted_semantic_parity`
- Scope: Local-server callback, status, body, and connection-failure behavior for portable `sys.Http`
- Evidence:
  - `test/semantic_diff/sys_http_callback_contract`
  - `test/snapshot/sys_http_smoke`
  - `test/snapshot/http_base_override_contract`
- Commands:
  - `python3 test/run-semantic-diff.py --case sys_http_callback_contract`
  - `bash test/run-snapshots.sh --case sys_http_smoke`
  - `bash test/run-snapshots.sh --case http_base_override_contract`
- Notes: Targeted local-server proof for `onStatus(...)`, `onData(...)`, and connection-failure `onError(...)` routing. Multipart/request-assembly confidence still relies on the snapshot/smoke bucket, and this is not blanket host/network semantic parity.

## Snapshot / Smoke Only

### Generic helper payload-bound shape
- Class: `snapshot_or_smoke_only`
- Scope: Generated Rust signatures for method-level generics that mention bounded generated class payloads
- Evidence:
  - `test/snapshot/generic_helper_payload_bounds`
  - `test/snapshot/generic_function_type_params`
- Commands:
  - `bash test/run-snapshots.sh --case generic_helper_payload_bounds`
  - `bash test/run-snapshots.sh --case generic_function_type_params`
- Notes: Snapshot-backed generated-shape proof. Helper methods returning or reading generated class payloads propagate required class bounds, while unconstrained Option<T> helpers remain bare.

### HTTP portable smoke coverage
- Class: `snapshot_or_smoke_only`
- Scope: Portable HTTP request/response shape and generated Rust behavior
- Evidence:
  - `test/snapshot/sys_http_smoke`
  - `test/snapshot/http_base_override_contract`
- Commands:
  - `bash test/run-snapshots.sh --case sys_http_smoke`
  - `bash test/run-snapshots.sh --case http_base_override_contract`
- Notes: Snapshot-backed smoke confidence covering multipart/request assembly, duplicate response headers, nullable missing-header lookup, and the HttpBase callback contract. Combine with the targeted semantic `sys_http_callback_contract` fixture for the current honest proof boundary.

### SSL/TLS snapshot smoke coverage
- Class: `snapshot_or_smoke_only`
- Scope: SNI certificate selection and generated Rust/runtime shape
- Evidence:
  - `test/snapshot/sys_ssl_sni`
- Commands:
  - `bash test/run-snapshots.sh --case sys_ssl_sni`
- Notes: Snapshot-backed smoke confidence for the generated/buildable SNI certificate-selection path. Not blanket TLS parity.

### Rust-first async subset
- Class: `snapshot_or_smoke_only`
- Scope: Documented `metal` + `hxrt` async contract (`Async.blockOn`, async helpers, generated-class instance methods)
- Evidence:
  - `test/snapshot/async_entry_boundary`
  - `test/snapshot/async_instance_method`
  - `test/snapshot/async_retry`
  - `test/snapshot/async_select`
  - `test/snapshot/rust_async_tasks`
  - `examples/async_retry_pipeline`
  - `test/negative/async_main_boundary`
  - `test/negative/async_constructor_contract`
  - `test/negative/async_preview_removed`
- Commands:
  - `bash test/run-snapshots.sh --case async_entry_boundary`
  - `bash test/run-snapshots.sh --case async_instance_method`
  - `bash test/run-snapshots.sh --case rust_async_tasks`
  - `bash scripts/ci/check-metal-policy.sh`
- Notes: Backed by dedicated entry-boundary and receiver-shape fixtures plus negative contract guards. This is a stable Rust-first subset, not a blanket async claim across profiles/runtime modes.

### Thread/EventLoop/thread-pool scheduler proof
- Class: `snapshot_or_smoke_only`
- Scope: Direct `sys.thread.EventLoop`, thread-pool helpers, and narrower MainLoop proof on the Rust target
- Evidence:
  - `test/snapshot/sys_thread_event_loop`
  - `test/snapshot/sys_thread_event_loop_repeat_cancel`
  - `test/snapshot/sys_thread_deque_basic`
  - `test/snapshot/sys_thread_elastic_thread_pool_smoke`
  - `test/snapshot/haxe_mainloop_entrypoint_basic`
  - `test/snapshot/haxe_mainloop_entrypoint_thread_bridge`
  - `examples/sys_thread_smoke`
  - `examples/thread_pool_smoke`
- Commands:
  - `bash test/run-snapshots.sh --case sys_thread_event_loop`
  - `bash test/run-snapshots.sh --case sys_thread_event_loop_repeat_cancel`
  - `bash test/run-snapshots.sh --case sys_thread_deque_basic`
  - `bash test/run-snapshots.sh --case sys_thread_elastic_thread_pool_smoke`
  - `bash test/run-snapshots.sh --case haxe_mainloop_entrypoint_basic`
  - `bash test/run-snapshots.sh --case haxe_mainloop_entrypoint_thread_bridge`
  - `bash scripts/ci/windows-smoke.sh`
  - `npm run test:all`
- Notes: Direct EventLoop ops now include repeating callback `repeat(...)/cancel(...)` proof, and `Deque`, `FixedThreadPool`, and `ElasticThreadPool` have Rust-target smoke proof. Read `docs/concurrency-posture.md` for the canonical stable/preview/caveat classification. Broader `haxe.MainLoop` / `haxe.EntryPoint` semantics are still not claimed as `--interp`-backed semantic parity.

### Database/native-environment smoke coverage
- Class: `snapshot_or_smoke_only`
- Scope: DB bindings that depend on native libraries and destination environment setup
- Evidence:
  - `test/snapshot/sys_db_mysql_compile`
  - `test/snapshot/sys_db_sqlite_smoke`
- Commands:
  - `bash test/run-snapshots.sh --case sys_db_mysql_compile`
  - `bash test/run-snapshots.sh --case sys_db_sqlite_smoke`
- Notes: SQLite currently has runtime smoke proof via the `:memory:` snapshot, while MySQL is compile-only dependency/codegen coverage. Useful environment-sensitive evidence, not broad runtime parity.

### Platform-sensitive Windows smoke
- Class: `snapshot_or_smoke_only`
- Scope: Curated sys IO/net/thread scenarios on Windows
- Evidence:
  - `scripts/ci/windows-smoke.sh`
  - `.github/workflows/ci.yml`
  - `.github/workflows/weekly-ci-evidence.yml`
- Commands:
  - `bash scripts/ci/windows-smoke.sh`
- Notes: Important platform confidence signal. Still a curated smoke subset, not blanket Windows parity.

## Discovered Semantic-Diff Suites

- Portable semantic-diff cases (23): `bytes_extended_api`, `closure_capture_mutation`, `exception_dynamic_payload`, `exceptions_typed_dynamic`, `function_value_mutable_callbacks`, `generic_base_specialization`, `generic_interface_specialization`, `int64_parity`, `json_stringify_replacer`, `map_key_value_iterator_manual`, `null_string_concat`, `polymorphic_field_updates`, `portable_option_result_basics`, `reflect_dynamic_receivers`, `static_field_updates`, `sys_getenv_null`, `sys_http_callback_contract`, `sys_net_failure_paths`, `sys_process_failure_paths`, `this_method_closure`, `typed_catch_interface`, `typed_catch_subclass`, `virtual_dispatch`
- Lane semantic-diff cases (2): `lane_clean_arithmetic`, `lane_clean_dispatch`

## Interpretation Rule

Do not strengthen release/support language from the compile/inventory section alone. Stronger claims require the targeted semantic/runtime section to move with it, or the surface must stay explicitly qualified as snapshot/smoke-only.

For the canonical `sys.Http` / `sys.ssl.*` / `sys.db.*` / platform-sensitive classification, read `docs/systems-environment-posture.md`.

