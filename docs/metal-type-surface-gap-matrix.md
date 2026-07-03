# Metal Type Surface Gap Matrix

This is the Rust-native type-surface audit for `haxe.rust-oo3.74.4`.

The matrix covers `rust.*`, `reflaxe.std`, and `hxrt`/native handle surfaces needed for haxified
Rust authoring. It is intentionally conservative: a surface is only "supported" when the Haxe API,
Rust representation, and fixture evidence are all present.

## Status Labels

| Status | Meaning |
| --- | --- |
| `supported` | Typed Haxe surface exists, Rust representation is intentional, and there is fixture/example evidence. |
| `partial` | Useful surface exists, but coverage, diagnostics, no-hxrt eligibility, ergonomics, or output-shape gates are incomplete. |
| `missing` | No adequate first-party typed surface exists yet. |

## Audit Rules

- Do not accept `Dynamic`, raw app-side `__rust__`, or stringly mini-DSLs as final metal APIs.
- Prefer compiler-recognized typed symbols, extern abstracts/classes, metadata, and narrow native helper modules.
- Treat `hxrt` as a semantic fallback or platform/runtime owner, not as the default implementation path for Rust-native values.
- For portable facades with Rust specialization, require explicit facade contracts and fallback
  reasons instead of silently switching ordinary portable code into metal semantics.

## Matrix

| Area | Haxe construct | Intended Rust representation | Status | Existing evidence | Missing compiler/runtime/API work |
| --- | --- | --- | --- | --- | --- |
| Owned primitives and structs | Concrete Haxe values, typed classes when value semantics are enough | Rust owned values (`i32`, `f64`, `bool`, `String`, structs) | partial | Broad snapshot/semantic suite; `test/positive/metal_no_hxrt_minimal` | Clearer value-vs-reference planner for classes; no-hxrt eligibility report for value-only metal/facade code. |
| Haxe reference semantics | `HxRef<T>` / generated class references | `hxrt::cell::HxRef<T>` and trait-object handles | supported as portable/runtime fallback | OO/class snapshots; AGENTS runtime model; broad snapshots using generated classes | Keep out of metal-only value paths where owned Rust values fit; report when `HxRef` is required by object identity, inheritance, or mutation semantics. |
| Immutable borrows | `rust.Ref<T>`, `rust.Borrow.withRef` | `&T` | partial | `test/snapshot/rust_borrow_ref`, `test/snapshot/rust_vec`, `docs/lifetime-encoding.md` | Static non-escape checks; negative fixtures for escaped refs and borrow-only captures; better diagnostics before Rust compile. |
| Mutable borrows | `rust.MutRef<T>`, `rust.Borrow.withMut` | `&mut T` | partial | `test/snapshot/rust_borrow_mut`, `test/snapshot/rust_vec` | Alias/escape checks; clearer mutation-region model; negative fixtures for storing/returning `MutRef<T>`. |
| Immutable slices | `rust.Slice<T>`, `rust.SliceTools`, `rust.ArrayBorrow` | `&[T]` | partial | `test/snapshot/rust_array_slice_views`, `test/snapshot/rust_for_vec_slice`, `docs/array.md` | No-clone slice-view fixtures; non-escape checks; output gates that distinguish borrowed views from cloned arrays. |
| Mutable slices | `rust.MutSlice<T>`, `rust.MutSliceTools` | `&mut [T]` | partial | `test/snapshot/rust_mut_slice`, `test/snapshot/rust_array_slice_views` | Alias/non-escape checks; stronger fixtures for mutation without clone; metal-island diagnostics for leaked mutable slices. |
| Native vectors | `rust.Vec<T>`, `rust.VecTools`, `IterTools.fromVec` | `Vec<T>` and Rust iterators | supported, with gaps | `test/snapshot/rust_vec`, `test/snapshot/rust_array_vec_bridge`, `test/snapshot/rust_for_vec_slice` | More no-hxrt/portable-facade fixtures; reduce clone noise in iterator and get/set patterns where ownership allows. |
| Native hash maps | `rust.HashMap<K,V>`, `rust.HashMapTools` | `std::collections::HashMap<K,V>` | supported, with gaps | `test/snapshot/rust_hashmap`; typed helper modules under `std/rust/native/*hash_map*` | Expand borrowed-entry APIs; no-hxrt coverage; clearer bounds diagnostics for `Eq + Hash + Clone` helper use. |
| Rust Option/Result | `rust.Option<T>`, `rust.Result<T,E>`, tools | Native `Option<T>` / `Result<T,E>` | supported | `test/snapshot/rust_result_option_tools`, `test/snapshot/rust_vec`, examples using `rust.Option`/`rust.Result` | Ergonomic propagation operators/macros remain future work; richer error enums and Result bridges need trait/bound fixtures. |
| Portable Option/Result facades | `reflaxe.std.Option<T>`, `reflaxe.std.Result<T,E>` | Native Rust `Option<T>` / `Result<T,E>` on Rust target; portable representation elsewhere | supported for v1 slice | `test/snapshot/reflaxe_std_option_result`, `test/snapshot/rust_reflaxe_std_adapters`, `test/snapshot/portable_facade_native_option_result`, `test/snapshot/portable_facade_contract_report`, `docs/reflaxe-std-adoption-contract.md` | Generalize into more capability-driven portable facades; keep semantic fallback-reason fixtures with each new admitted surface. |
| Rust strings | `String`, `rust.Str`, `rust.StrTools`, `rust.StringTools` | `String`, `&str`, or `hxrt::string::HxString` depending on contract | partial | string snapshots; `std/rust/native/rust_string_tools*.rs`; nullable-string policy docs | Finish clear boundary reports for `String` vs `HxString`; no-hxrt string subset; reduce hardcoded raw `String` assumptions in native/runtime APIs. |
| Paths | `rust.PathBuf`, `rust.PathBufTools` | `std::path::PathBuf` | supported, narrow | `test/snapshot/rust_path_time`, `test/snapshot/path_directory` | Add borrowed `Path`/`&Path` surface; OS-string/path conversion edge fixtures; no-hxrt path subset. |
| OS strings | `rust.OsString`, `rust.OsStringTools` | `std::ffi::OsString` | partial | helper modules under `std/rust/native/os_string_tools*.rs`; path/time snapshots cover adjacent flows | Add focused OS string fixture; define borrowed `OsStr` shape; document platform encoding constraints. |
| Time | `rust.SystemTime`, `rust.Instant`, `rust.Duration`, tools | `std::time::{SystemTime, Instant, Duration}` | supported, narrow | `test/snapshot/rust_path_time`, `test/positive/metal_no_hxrt_minimal` | More negative/error-path coverage for `SystemTimeError`; facade/no-hxrt eligibility docs. |
| Iterators | `rust.Iter<T>`, `rust.IterTools`, `Vec.iterator`, `Slice.iterator`, map iterators | Rust `Iterator` chains where possible | partial | `test/snapshot/rust_for_vec_slice`, `test/snapshot/rust_vec`, iterator helpers | Stronger typed iterator facade; avoid clone-heavy `.cloned()` where borrowed iteration is the contract; trait-bound diagnostics. |
| Traits and bounds | Haxe interfaces, `@:rustImpl`, `@:rustGeneric`, extern helpers | Rust traits, impl blocks, trait objects, and inline generic bounds | partial | `test/snapshot/rust_impl_meta`, `test/snapshot/generics_interface`, `test/snapshot/metal_trait_impl_bounds`, `test/snapshot/metal_trait_object_boundary`, `docs/metal-trait-impl-bound-model.md` | Full `where` clauses, associated types, derive helpers, object-safety diagnostics, and orphan-rule diagnostics remain future work. |
| Async tasks | `rust.async.*` | Tokio/future-backed tasks plus `hxrt` async runtime handles | partial | `test/snapshot/rust_async_tasks`, `test/snapshot/async_*`, `examples/async_retry_pipeline`, `docs/async-contract.md` | `rust_no_hxrt` async remains unsupported; future/lifetime surface design; clearer split between metal async and portable facade async. |
| Concurrency primitives | `rust.concurrent.Channel/Mutex/RwLock/Task`, helper modules | Runtime-owned typed handles over Rust concurrency primitives | partial | `test/snapshot/rust_concurrent`; `std/hxrt/concurrent/*` | Decide which primitives can be no-hxrt native values; RAII guard surface for lock guards; deterministic Send/Sync diagnostics. |
| Process handles | `hxrt.process.ProcessHandle`, `std/sys/io/Process` style overrides | Runtime-owned process handle wrapping `std::process` | partial | sys/process snapshots and semantic failure-path tests | Rust-native `rust.process` facade is missing; no-hxrt process subset unclear; typed exit/status/stdout API needed. |
| File handles | `hxrt.fs.FileHandle`, `rust.fs.NativeFile` | Runtime/file handle over `std::fs::File` | partial | sys.io and filesystem snapshots | Rust-native file/path facade should avoid Dynamic and broad hxrt where possible; RAII file handle API and no-hxrt subset need design. |
| Socket/TLS handles | `hxrt.net.SocketHandle`, `hxrt.ssl.*Handle` | Runtime-owned TCP/UDP/TLS handles | partial | `test/snapshot/sys_ssl_sni`, sys.net/sys.ssl sweeps/examples | Rust-native socket facade is missing; async/blocking split and no-hxrt subset need design; TLS unsafe/native setup remains facade-owned. |
| Database handles | `hxrt.db.*Handle` and native drivers | Runtime-owned SQLite/MySQL handles | partial | `test/snapshot/sys_db_sqlite_smoke`, `test/snapshot/sys_db_mysql_compile` | Rust-native typed DB facade is missing; row/statement types still runtime-heavy; no-hxrt DB story likely out of initial scope. |
| RAII guards | Planned lock/file/socket guard facades | Rust guard/drop types (`MutexGuard`, file/socket owners, scoped locks) | missing | Existing runtime handles imply ownership but do not expose guard types | Design guard lifetimes with scoped callbacks or extern islands; add negative fixtures for escaped guards. |
| Native handles in portable facades | Planned facade layer over admitted `reflaxe.std`/future package surfaces | Target-specific native implementation behind cross-target API | partial concept | `reflaxe.std.Option/Result` adoption docs and fixtures | Define per-surface admission rules, metadata/intrinsics, no-hxrt eligibility, and fallback-reason reports (`haxe.rust-oo3.74.9`). |
| Serde/JSON native interop | `rust.serde.SerdeJson`, `hxrt.json.NativeJson` | `serde_json` plus typed runtime conversion where needed | partial | `test/snapshot/serde_json`, `examples/serde_json`, JSON std snapshots | Typed schema/derive layer is missing; avoid `Dynamic` except real JSON boundary; no-hxrt JSON subset needs explicit limits. |
| Raw metal code | `rust.metal.Code.expr/stmt` | Scoped raw bridge for missing typed surfaces | partial escape hatch | `test/snapshot/metal_typed_injection`, `test/negative/metal_stringly_dsl_app_api`, `test/negative/metal_dsl_bypasses_policy` | Requires framework ownership or an owning class tagged `@:rustAllowRaw`; replace common raw snippets with typed facades/DSL nodes; keep app-side stringly APIs rejected by policy. |

## Priority Gaps

1. Borrow/region diagnostics: refs, mutable refs, slices, and guards need non-escape checks before Rust compile.
2. Capability-driven portable facades: generalize the `reflaxe.std.Option/Result` pattern through per-surface contracts without hiding runtime fallback.
3. RAII guard modeling: lock/file/socket guard lifetimes need typed scoped patterns or extern islands.
4. No-hxrt eligibility reports: metal/facade code needs deterministic reasons whenever `hxrt` is still required.
5. Iterator and collection output shape: reduce avoidable clones and borrow-guard bloat under explicit metal/facade contracts.
6. Rust-native systems facades: process, file, socket, TLS, and DB handles need typed Rust-first APIs distinct from portable sys semantics.

## Tracker Mapping

| Follow-up | Owns |
| --- | --- |
| `haxe.rust-oo3.74.2` | Borrow/region diagnostics for refs, mut refs, slices, and guards. |
| `haxe.rust-oo3.74.3` | Traits, bounds, iterator traits, and guard trait surfaces. |
| `haxe.rust-oo3.74.5` | Typed DSL replacement for common raw snippets. |
| `haxe.rust-oo3.74.6` | Idiomatic-output and no-hxrt/ERaw/Dynamic/clone/borrow guard gates. |
| `haxe.rust-oo3.74.7` | Extern islands for lifetime-heavy and unsafe/native internals. |
| `haxe.rust-oo3.74.9` | Capability-driven portable facade admission rules, native Rust representation contracts, and fallback-reason reports. |
