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
| Immutable borrows | `rust.Ref<T>`, `rust.Borrow.withRef` | `&T` | partial | `test/snapshot/rust_borrow_ref`, `test/snapshot/rust_vec`, `test/positive/borrow_literal_derivation`, `test/positive/borrow_alias_derivation`, `test/positive/borrow_wrapper_derivation`, `test/negative/metal_ref_escape`, `test/negative/metal_ref_return_escape`, `test/negative/metal_ref_assignment_escape`, `test/negative/metal_ref_literal_escape`, `test/negative/metal_ref_closure_escape`, `test/negative/metal_ref_alias_tail_escape`, `test/negative/metal_ref_alias_return_escape`, `test/negative/metal_ref_alias_field_storage_escape`, `test/negative/metal_ref_alias_closure_storage_escape`, `test/negative/metal_ref_option_wrapper_escape`, `test/negative/metal_ref_object_wrapper_escape`, `test/negative/metal_ref_helper_wrapper_escape`, `test/negative/metal_ref_throw_escape`, `test/negative/send_sync_borrow_capture`, `docs/lifetime-encoding.md` | Richer alias provenance through helper-call side effects and unknown closure variables. |
| Mutable borrows | `rust.MutRef<T>`, `rust.Borrow.withMut` | `&mut T` | partial | `test/snapshot/rust_borrow_mut`, `test/snapshot/rust_vec`, `test/positive/borrow_mut_disjoint_scopes`, `test/negative/metal_mut_ref_escape`, `test/negative/metal_mut_ref_nested_overlap` | Field/static source provenance and richer source-equivalence checks beyond local same-source mutable scopes. |
| Immutable slices | `rust.Slice<T>`, `rust.SliceTools`, `rust.ArrayBorrow` | `&[T]` | partial | `test/snapshot/rust_array_slice_views`, `test/snapshot/rust_for_vec_slice`, `test/negative/metal_slice_escape`, `test/negative/metal_slice_alias_return_escape`, `scripts/ci/check-metal-policy.sh` slice-view output-shape gate, `docs/array.md` | Slice-specific wrapper/helper fixtures and richer source provenance. |
| Mutable slices | `rust.MutSlice<T>`, `rust.MutSliceTools` | `&mut [T]` | partial | `test/snapshot/rust_mut_slice`, `test/snapshot/rust_array_slice_views`, `test/positive/borrow_mut_disjoint_scopes`, `test/negative/metal_mut_slice_escape`, `test/negative/metal_mut_slice_nested_overlap`, `test/negative/metal_mut_region_sibling_overlap`, `scripts/ci/check-metal-policy.sh` slice-view output-shape gate | Field/static source provenance; metal-island diagnostics for leaked mutable slices. |
| Native vectors | `rust.Vec<T>`, `rust.VecTools`, `IterTools.fromVec` | `Vec<T>` and Rust iterators | supported, with gaps | `test/snapshot/rust_vec`, `test/snapshot/rust_array_vec_bridge`, `test/snapshot/rust_for_vec_slice` | More no-hxrt/portable-facade fixtures; reduce clone noise in iterator and get/set patterns where ownership allows. |
| Native hash maps | `rust.HashMap<K,V>`, `rust.HashMapTools` | `std::collections::HashMap<K,V>` | supported, with gaps | `test/snapshot/rust_hashmap`; typed helper modules under `std/rust/native/*hash_map*` | Expand borrowed-entry APIs; no-hxrt coverage; clearer bounds diagnostics for `Eq + Hash + Clone` helper use. |
| Rust Option/Result | `rust.Option<T>`, `rust.Result<T,E>`, tools | Native `Option<T>` / `Result<T,E>` | supported | `test/snapshot/rust_result_option_tools`, `test/snapshot/rust_vec`, examples using `rust.Option`/`rust.Result` | Ergonomic propagation operators/macros remain future work; richer error enums and Result bridges need trait/bound fixtures. |
| Portable Option/Result facades | `reflaxe.std.Option<T>`, `reflaxe.std.Result<T,E>` | Native Rust `Option<T>` / `Result<T,E>` on Rust target; portable representation elsewhere | supported for v1 slice | `test/snapshot/reflaxe_std_option_result`, `test/snapshot/rust_reflaxe_std_adapters`, `test/snapshot/portable_facade_native_option_result`, `test/snapshot/portable_facade_contract_report`, `docs/reflaxe-std-adoption-contract.md` | Generalize into more capability-driven portable facades; keep semantic fallback-reason fixtures with each new admitted surface. |
| Rust strings | `String`, `rust.Str`, `rust.StrTools`, `rust.StringTools` | `String`, `&str`, or `hxrt::string::HxString` depending on contract | partial | string snapshots; `test/negative/send_sync_str_capture`; `std/rust/native/rust_string_tools*.rs`; nullable-string policy docs | Finish clear boundary reports for `String` vs `HxString`; no-hxrt string subset; reduce hardcoded raw `String` assumptions in native/runtime APIs. |
| Paths | `rust.PathBuf`, `rust.PathBufTools` | `std::path::PathBuf` | supported, narrow | `test/snapshot/rust_path_time`, `test/snapshot/path_directory` | Add borrowed `Path`/`&Path` surface; OS-string/path conversion edge fixtures; no-hxrt path subset. |
| OS strings | `rust.OsString`, `rust.OsStringTools` | `std::ffi::OsString` | partial | helper modules under `std/rust/native/os_string_tools*.rs`; path/time snapshots cover adjacent flows | Add focused OS string fixture; define borrowed `OsStr` shape; document platform encoding constraints. |
| Time | `rust.SystemTime`, `rust.Instant`, `rust.Duration`, tools | `std::time::{SystemTime, Instant, Duration}` | supported, narrow | `test/snapshot/rust_path_time`, `test/positive/metal_no_hxrt_minimal` | More negative/error-path coverage for `SystemTimeError`; facade/no-hxrt eligibility docs. |
| Iterators | `rust.Iter<T>`, `rust.IterTools`, `Vec.iterator`, `Slice.iterator`, map iterators | Rust `Iterator` chains where possible | partial | `test/snapshot/rust_for_vec_slice`, `test/snapshot/rust_vec`, iterator helpers | Stronger typed iterator facade; avoid clone-heavy `.cloned()` where borrowed iteration is the contract; trait-bound diagnostics. |
| Traits and bounds | Haxe interfaces, `@:rustImpl`, `@:rustGeneric`, extern helpers | Rust traits, impl blocks, trait objects, and inline generic bounds | partial | `test/snapshot/rust_impl_meta`, `test/snapshot/generics_interface`, `test/snapshot/metal_trait_impl_bounds`, `test/snapshot/metal_trait_object_boundary`, `docs/metal-trait-impl-bound-model.md` | Full `where` clauses, associated types, derive helpers, object-safety diagnostics, and orphan-rule diagnostics remain future work. |
| Async tasks | `rust.async.*` | Tokio/future-backed tasks plus `hxrt` async runtime handles | partial | `test/snapshot/rust_async_tasks`, `test/snapshot/async_*`, `examples/async_retry_pipeline`, `docs/async-contract.md` | `rust_no_hxrt` async remains unsupported; future/lifetime surface design; clearer split between metal async and portable facade async. |
| Concurrency primitives | `rust.concurrent.Channel/Mutex/RwLock/Task`, helper modules | Runtime-owned typed handles over Rust concurrency primitives | partial | `test/snapshot/rust_concurrent`; `test/positive/metal_raii_guard_scoped`; `test/negative/metal_raii_guard_escape`; `std/hxrt/concurrent/*` | Decide which primitives can be no-hxrt native values; broader Send/Sync diagnostics. |
| Process handles | `hxrt.process.ProcessHandle`, `std/sys/io/Process` style overrides, `rust.process.NativeCommands`, `rust.process.CommandOutput`, `rust.process.CommandEnv`, `rust.process.CommandSpec`, `rust.process.CommandError`, `rust.process.CommandChild` | Runtime-owned process handle wrapping `std::process`; Rust-native owned-command and narrow live-child facades over direct `std::process::Command` / `std::process::Output` / `std::process::Child` | partial | sys/process snapshots and semantic failure-path tests; `std/rust/process/NativeCommands.hx`; `std/rust/process/CommandOutput.hx`; `std/rust/process/CommandEnv.hx`; `std/rust/process/CommandSpec.hx`; `std/rust/process/CommandError.hx`; `std/rust/process/CommandChild.hx`; `test/positive/metal_no_hxrt_native_process`; `test/positive/metal_no_hxrt_command_output`; `test/positive/metal_no_hxrt_command_cwd`; `test/positive/metal_no_hxrt_command_env`; `test/positive/metal_no_hxrt_command_env_ops`; `test/positive/metal_no_hxrt_command_cwd_env`; `test/positive/metal_no_hxrt_command_stdin`; `test/positive/metal_no_hxrt_command_stdin_cwd_env`; `test/positive/metal_no_hxrt_command_spec`; `test/positive/metal_no_hxrt_command_error`; `test/positive/metal_no_hxrt_command_child`; `test/negative/metal_process_raw_escape`; [Metal systems facades roadmap](metal-systems-facades-roadmap.md) | Rust-first owned-command subset is supported for explicit executable, `rust.Vec<String>` args, explicit cwd, typed env set/remove/clear operations, combined cwd+env calls, one-shot owned stdin input, combined stdin+cwd+env calls, typed owned command specs, owned status/stdout/stderr result, opt-in typed IO/stdin/UTF-8/lifecycle command errors, a narrow live child with write/close stdin, wait, and kill/wait, no shell fallback, and no-hxrt output-shape gates. Reusable stdin pipes, live stdout/stderr streams, detached handles, async process, shell fallback, and portable Process parity remain future work. |
| File handles | `hxrt.fs.FileHandle`, `rust.fs.NativeFile`, `rust.fs.NativeFiles` | Runtime/file handle over `std::fs::File`; Rust-native helper facade over direct `std::fs` operations | partial | sys.io and filesystem snapshots; `test/positive/metal_no_hxrt_native_file`; `test/negative/metal_fs_raw_escape`; [Metal systems facades roadmap](metal-systems-facades-roadmap.md) | M43 first slice now has a typed Rust-native file/path facade distinct from portable `sys.io.*`; continue expanding file ownership/RAII APIs while keeping no-hxrt output-shape gates. |
| Socket/TLS handles | `hxrt.net.SocketHandle`, `hxrt.ssl.*Handle`, `rust.net.NativeTcp`, `rust.net.TcpListener`, `rust.net.TcpStream`, `rust.net.NativeUdp`, `rust.net.UdpSocket`, `rust.net.SocketAddr`, `rust.net.SocketError` | Runtime-owned portable TCP/UDP/TLS handles for `sys.*`; Rust-native blocking TCP and UDP wrappers over direct `std::net` for narrow metal slices; typed loopback socket addresses; typed opt-in TCP/UDP error records; TCP byte streams and UDP byte datagrams as validated `Vec<Int>` / native `Vec<u8>` | partial | `test/snapshot/sys_ssl_sni`, sys.net/sys.ssl sweeps/examples; `std/rust/net/NativeTcp.hx`; `std/rust/net/TcpListener.hx`; `std/rust/net/TcpStream.hx`; `std/rust/net/NativeUdp.hx`; `std/rust/net/UdpSocket.hx`; `std/rust/net/SocketAddr.hx`; `std/rust/net/SocketError.hx`; `test/positive/metal_no_hxrt_native_tcp`; `test/positive/metal_no_hxrt_native_udp`; `test/positive/metal_no_hxrt_socket_error`; `test/positive/metal_no_hxrt_udp_bytes`; `test/positive/metal_no_hxrt_tcp_bytes`; `test/positive/metal_no_hxrt_socket_addr`; `examples/metal_native_net`; `scripts/ci/check-metal-policy.sh` native TCP/UDP/socket-error/UDP-byte/TCP-byte/socket-address output-shape gates | Current Rust-native socket facades are localhost blocking TCP and localhost blocking UDP with typed loopback addresses, UTF-8 plus typed byte payloads, and opt-in invalid-input/IO/UTF-8 `SocketError` categories. Arbitrary host/address APIs, DNS, external networking, live stream adapters, async networking, TLS setup, portable `sys.net` parity, and richer platform-specific error categories remain future work. |
| Database handles | `hxrt.db.*Handle` and native drivers | Runtime-owned SQLite/MySQL handles | partial | `test/snapshot/sys_db_sqlite_smoke`, `test/snapshot/sys_db_mysql_compile` | Rust-native typed DB facade is missing; row/statement types still runtime-heavy; no-hxrt DB story likely out of initial scope. |
| RAII guards | Scoped lock guard callbacks and future file/socket/transaction facades | Rust guard/drop types (`MutexGuard`, `RwLock*Guard`, file/socket owners, scoped locks) | partial | `test/positive/metal_raii_guard_scoped`; `test/negative/metal_raii_guard_escape`; `docs/raii-guard-lifetime-islands.md`; HXRT concurrent tests | Extend scoped-callback or extern-island pattern to file/socket/transaction APIs; no-hxrt subset remains future work. |
| Native handles in portable facades | Planned facade layer over admitted `reflaxe.std`/future package surfaces | Target-specific native implementation behind cross-target API | partial concept | `reflaxe.std.Option/Result` adoption docs and fixtures | Define per-surface admission rules, metadata/intrinsics, no-hxrt eligibility, and fallback-reason reports (`haxe.rust-oo3.74.9`). |
| Serde/JSON native interop | `rust.serde.SerdeJson`, `hxrt.json.NativeJson` | `serde_json` plus typed runtime conversion where needed | partial | `test/snapshot/serde_json`, `examples/serde_json`, JSON std snapshots | Typed schema/derive layer is missing; avoid `Dynamic` except real JSON boundary; no-hxrt JSON subset needs explicit limits. |
| Raw metal code | `rust.metal.Code.expr/stmt` | Scoped raw bridge for missing typed surfaces | partial escape hatch | `test/snapshot/metal_typed_injection`, `test/negative/metal_stringly_dsl_app_api`, `test/negative/metal_dsl_bypasses_policy` | Requires framework ownership or an owning class tagged `@:rustAllowRaw`; replace common raw snippets with typed facades/DSL nodes; keep app-side stringly APIs rejected by policy. |

## Priority Gaps

1. Borrow/region diagnostics: direct `Ref`/`MutRef`/`Slice`/`MutSlice` escapes, first-wave aliases, wrapper/throw packaging, local same-source mutable overlaps, and scoped lock guard escapes now have Haxe-source diagnostics; richer source provenance still needs typed checks before Rust compile.
2. Capability-driven portable facades: generalize the `reflaxe.std.Option/Result` pattern through per-surface contracts without hiding runtime fallback.
3. RAII guard modeling: lock guards have scoped callbacks; file/socket/transaction guard lifetimes need typed scoped patterns or extern islands.
4. No-hxrt eligibility reports: metal/facade code needs deterministic reasons whenever `hxrt` is still required.
5. Iterator and collection output shape: reduce avoidable clones and borrow-guard bloat under explicit metal/facade contracts.
6. Rust-native systems facades: process, file, socket, TLS, and DB handles need typed Rust-first APIs distinct from portable sys semantics. M43 shipped the file/path first slice because it was deterministic in CI and could prove owned RAII plus no-hxrt eligibility; M44 shipped a narrow owned-command process slice before live handles, sockets, TLS, or DB; M45 added one-run `CommandOutput` status/stdout/stderr proof; M46 added explicit cwd configuration; M47 added explicit env overrides; M48 added env remove/clear operations; M49 added combined cwd+env owned-command calls; M50 added one-shot owned stdin input; M51 added combined stdin+cwd+env owned-command calls; M52 added typed owned `CommandSpec` records; M53 added opt-in typed `CommandError` records; M54 added narrow `CommandChild` lifecycle; M55 added the first blocking localhost TCP facade; M56 added the first blocking localhost UDP datagram facade; M57 added opt-in typed `SocketError` records for TCP/UDP invalid-input, IO, and UTF-8 categories; M58 added typed UDP byte datagrams without `haxe.io.Bytes` or `hxrt`; M59 added typed TCP byte streams under the same no-hxrt byte validation contract; M60 added typed loopback `SocketAddr` values and a no-hxrt metal networking example.

## Tracker Mapping

| Follow-up | Owns |
| --- | --- |
| `haxe.rust-oo3.74.2` | Borrow/region diagnostics for refs, mut refs, slices, and guards. |
| `haxe.rust-oo3.74.3` | Traits, bounds, iterator traits, and guard trait surfaces. |
| `haxe.rust-oo3.74.5` | Typed DSL replacement for common raw snippets. |
| `haxe.rust-oo3.74.6` | Idiomatic-output and no-hxrt/ERaw/Dynamic/clone/borrow guard gates. |
| `haxe.rust-oo3.74.7` | Extern islands for lifetime-heavy and unsafe/native internals, with cookbook docs and `test/snapshot/metal_extern_lifetime_island`. |
| `haxe.rust-oo3.74.9` | Capability-driven portable facade admission rules, native Rust representation contracts, and fallback-reason reports. |
| `haxe.rust-oo3.74.14` | Wrapper/helper/object/throw borrow-token escape checks. |
| `haxe.rust-oo3.74.15` | No-clone Array slice-view output-shape gate. |
| `haxe.rust-oo3.74.16` | Scoped RAII lock guard callbacks and lifetime-island selection rules. |
| `haxe.rust-oo3.75` | Rust-native systems facades and no-hxrt proof. |
| `haxe.rust-oo3.75.1` | Systems-facade audit and file/path first-slice decision. |
| `haxe.rust-oo3.75.2` | Contract-first fixtures for the selected file/path facade. |
| `haxe.rust-oo3.75.3` | First typed Rust-native systems facade implementation. |
| `haxe.rust-oo3.75.4` | No-hxrt/runtime-plan and output-shape gates for the facade. |
| `haxe.rust-oo3.75.5` | Docs/FAQ/README and app-level evidence refresh. |
| `haxe.rust-oo3.76` | Rust-native process facade and command-output proof. |
| `haxe.rust-oo3.76.1` | Process facade scope audit and deterministic fixture strategy. |
| `haxe.rust-oo3.76.2` | Contract-first process fixtures. |
| `haxe.rust-oo3.76.3` | First typed Rust-native process facade implementation. |
| `haxe.rust-oo3.76.4` | Process no-hxrt/runtime-plan and output-shape gates. |
| `haxe.rust-oo3.76.5` | Process docs/FAQ/README and app-level evidence refresh. |
| `haxe.rust-oo3.77` | Typed command-output facade and no-hxrt proof. |
| `haxe.rust-oo3.77.1` | Command-output contract fixture. |
| `haxe.rust-oo3.77.2` | `rust.process.CommandOutput` implementation. |
| `haxe.rust-oo3.77.3` | Command-output output-shape gate. |
| `haxe.rust-oo3.78` | Explicit command cwd facade and no-hxrt proof. |
| `haxe.rust-oo3.78.1` | Cwd command contract fixture. |
| `haxe.rust-oo3.78.2` | `statusCodeInDir` / `outputUtf8InDir` implementation. |
| `haxe.rust-oo3.78.3` | Cwd command output-shape gate. |
| `haxe.rust-oo3.79` | Explicit command env override facade and no-hxrt proof. |
| `haxe.rust-oo3.79.1` | Env override command contract fixture. |
| `haxe.rust-oo3.79.2` | `CommandEnv` / env-aware command helper implementation. |
| `haxe.rust-oo3.79.3` | Env command output-shape gate. |
| `haxe.rust-oo3.80` | Explicit command env remove/clear facade and no-hxrt proof. |
| `haxe.rust-oo3.80.1` | Env remove/clear command contract fixture. |
| `haxe.rust-oo3.80.2` | `CommandEnv.remove` / `CommandEnv.clear` implementation. |
| `haxe.rust-oo3.80.3` | Env remove/clear output-shape gate. |
| `haxe.rust-oo3.81` | Combined cwd+env owned-command facade and no-hxrt proof. |
| `haxe.rust-oo3.81.1` | Cwd+env command contract fixture. |
| `haxe.rust-oo3.81.2` | `statusCodeInDirWithEnv` / `outputUtf8InDirWithEnv` implementation. |
| `haxe.rust-oo3.81.3` | Cwd+env output-shape gate. |
| `haxe.rust-oo3.82` | Owned stdin-input command facade and no-hxrt proof. |
| `haxe.rust-oo3.82.1` | Stdin-input command contract fixture. |
| `haxe.rust-oo3.82.2` | `statusCodeWithStdin` / `outputUtf8WithStdin` implementation. |
| `haxe.rust-oo3.82.3` | Stdin-input output-shape gate. |
| `haxe.rust-oo3.83` | Combined stdin+cwd+env owned-command facade and no-hxrt proof. |
| `haxe.rust-oo3.83.1` | Stdin+cwd+env command contract fixture. |
| `haxe.rust-oo3.83.2` | `statusCodeInDirWithEnvAndStdin` / `outputUtf8InDirWithEnvAndStdin` implementation. |
| `haxe.rust-oo3.83.3` | Stdin+cwd+env output-shape gate. |
| `haxe.rust-oo3.84` | Typed owned command-spec facade and no-hxrt proof. |
| `haxe.rust-oo3.84.1` | CommandSpec command contract fixture. |
| `haxe.rust-oo3.84.2` | `CommandSpec` / `statusCodeFromSpec` / `outputUtf8FromSpec` implementation. |
| `haxe.rust-oo3.84.3` | CommandSpec output-shape gate. |
| `haxe.rust-oo3.85` | Typed command-error owned-command facade and no-hxrt proof. |
| `haxe.rust-oo3.85.1` | CommandError command contract fixture. |
| `haxe.rust-oo3.85.2` | `CommandError` / detailed command and output helper implementation. |
| `haxe.rust-oo3.85.3` | CommandError output-shape gate. |
| `haxe.rust-oo3.86` | Narrow live command-child lifecycle facade and no-hxrt proof. |
| `haxe.rust-oo3.86.1` | CommandChild lifecycle contract fixture. |
| `haxe.rust-oo3.86.2` | `CommandChild` / `spawnChildFromSpec` implementation. |
| `haxe.rust-oo3.86.3` | CommandChild output-shape gate. |
| `haxe.rust-oo3.87` | Blocking localhost TCP facade and no-hxrt proof. |
| `haxe.rust-oo3.87.1` | Native TCP localhost round-trip contract fixture. |
| `haxe.rust-oo3.87.2` | `rust.net.NativeTcp`, `TcpListener`, and `TcpStream` implementation. |
| `haxe.rust-oo3.87.3` | Native TCP output-shape gate. |
| `haxe.rust-oo3.88` | Blocking localhost UDP datagram facade and no-hxrt proof. |
| `haxe.rust-oo3.88.1` | Native UDP localhost datagram round-trip contract fixture. |
| `haxe.rust-oo3.88.2` | `rust.net.NativeUdp` and `UdpSocket` implementation. |
| `haxe.rust-oo3.88.3` | Native UDP output-shape gate. |
| `haxe.rust-oo3.89` | Typed socket-error TCP/UDP facade and no-hxrt proof. |
| `haxe.rust-oo3.89.1` | SocketError contract fixture. |
| `haxe.rust-oo3.89.2` | `rust.net.SocketError` and Detailed TCP/UDP implementation. |
| `haxe.rust-oo3.89.3` | SocketError output-shape gate. |
| `haxe.rust-oo3.90` | UDP byte datagram facade and no-hxrt proof. |
| `haxe.rust-oo3.91` | TCP byte stream facade and no-hxrt proof. |
| `haxe.rust-oo3.92` | Typed socket address facade, no-hxrt output-shape proof, and metal networking example. |
| `haxe.rust-oo3.93` | Native helper manifest and growth guard follow-up. |
| `haxe.rust-oo3.94` | Compiler-generated native wrapper facility spike. |
| `haxe.rust-oo3.95` | SocketAddr lowering-candidate graduation follow-up. |
| `haxe.rust-oo3.96` | Resource lifecycle native facade review follow-up. |
