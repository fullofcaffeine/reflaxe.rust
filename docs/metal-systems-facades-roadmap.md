# Metal Systems Facades Roadmap

This page owns the M43 plan for Rust-native systems surfaces: files, processes, sockets, TLS, DB
handles, and adjacent native handles.

## Why

M42 proved the first haxified-Rust layer: typed borrows, scoped guard patterns, contract reports,
output-shape gates, and typed interop islands. The next production gap is lower-level systems
authority.

The important split is:

- portable `sys.*` APIs preserve Haxe semantics and may need `hxrt`
- metal/native facades expose Rust-shaped ownership, RAII, and no/low-runtime paths when the source
  contract is Rust-first

Do not make portable `sys.io.File`, `sys.io.Process`, sockets, TLS, or DB handles pretend to be
no-runtime APIs when Haxe compatibility needs cloneable handles, nullable strings, dynamic payloads,
exceptions, or platform abstraction. Instead, add typed Rust-native surfaces beside them.

## Current Inventory

| Surface | Current state | Runtime posture | Next ownership |
| --- | --- | --- | --- |
| Paths and OS strings | `rust.PathBuf`, `rust.PathBufTools`, `rust.OsString`, and `rust.OsStringTools` exist with typed native helper modules. | Narrow metal paths can stay close to direct Rust. Portable nullable strings may still use `hxrt::string::HxString`. | Add borrowed `Path` / `OsStr` shapes and no-hxrt path fixtures as needed. |
| File handles | Portable `sys.io.File*` uses `hxrt.fs.FileHandle`; `rust.fs.NativeFile` is an internal typing-only binding; `rust.fs.NativeFiles` is the first app-facing native helper facade. | `hxrt` is required for Haxe `Input` / `Output` handle semantics, but not for the current Rust-first owned/scoped file helper subset. | M43 first slice: expand the typed Rust-native file/path facade and keep its no-hxrt output evidence. |
| Process handles | Portable `sys.io.Process` uses `hxrt.process.ProcessHandle`; no app-facing `rust.process` facade exists. | `hxrt` is justified for portable process streams and Haxe-style IO wrappers. A Rust-first `Command` / `Output` facade can be narrower. | Follow after file/path, once command/environment fixture stability is designed. |
| Socket and TLS handles | `hxrt.net` / `hxrt.ssl` support portable sys surfaces and smoke fixtures. | Runtime ownership is justified for portable sockets/TLS and platform-sensitive setup. | Later M43/M44 work should separate blocking vs async, TLS setup, and no-hxrt limits. |
| DB handles | `hxrt.db` supports current SQLite smoke and MySQL compile coverage. | Runtime-heavy today; DB row/statement values are still portable/sys shaped. | Defer until file/process no-hxrt patterns are proven; typed DB facade is not the first slice. |
| RAII guards | Lock guards have scoped callbacks; docs define extern-island selection for heavier guards. | Simple lexical guards are scoped; complex guard internals stay in Rust islands. | File APIs should prefer owned-result helpers or scoped callbacks, not storable lifetime tokens. |

## First Slice

M43 should start with a Rust-native file/path facade.

Why this slice first:

- file/path work is deterministic in CI and does not need network, TLS, database services, or shell
  command availability
- the repo already has `rust.PathBuf` helpers and an internal `rust.fs.NativeFile` binding
- portable `sys.io.File` already documents why `hxrt` is needed, so the native facade can be clearly
  separate instead of blurring contracts
- file handles exercise real Rust RAII and native ownership without requiring full lifetime syntax

The first implementation bead introduced `rust.fs.NativeFiles` as the initial API name. The contract
for this slice is:

- typed Haxe API under `rust.fs.*`
- no app-side `untyped __rust__`
- no portable `sys.io.FileInput` / `FileOutput` compatibility promise
- no broad `Dynamic` boundary
- generated Rust uses direct `std::fs` / `std::io` helpers or a narrow typed extern module
- `-D reflaxe_rust_profile=metal -D rust_no_hxrt` fixture coverage where the selected operations
  do not require Haxe runtime semantics

## Contract Fixtures

The M43 fixture bead added the initial contract before implementation:

| Fixture | Purpose |
| --- | --- |
| `test/positive/metal_no_hxrt_native_file` | Proves the current no-hxrt file/path subset compiles and cargo-builds without `hxrt`. |
| `test/negative/metal_fs_raw_escape` | Rejects app-side raw Rust as a substitute for the facade under strict policy. |
| `scripts/ci/check-metal-policy.sh` native-file output-shape case | Checks for avoidable `hxrt`, portable `FileHandle` / `sys_io` paths, and expected direct `std::fs` helper use. |

Future expansion can add a snapshot fixture once the API grows beyond the current no-hxrt compile
contract, but the evidence shape should stay contract-first.

## Non-Goals

M43 is not:

- a rewrite of portable `sys.io.*`
- a promise that all file/process/socket/TLS/DB APIs can omit `hxrt`
- a blanket cross-platform systems parity claim
- a DB/TLS/network service matrix
- an async systems runtime redesign

If a Haxe-compatible API needs runtime handles, keep the runtime path and report why. If a metal API
can use direct Rust ownership, add the typed facade and prove the emitted shape.

## Tracker Mapping

| Bead | Owns |
| --- | --- |
| `haxe.rust-oo3.75` | M43 systems-facade and no-hxrt proof milestone. |
| `haxe.rust-oo3.75.1` | This audit and first-slice decision. |
| `haxe.rust-oo3.75.2` | Contract-first fixtures for the selected file/path facade. |
| `haxe.rust-oo3.75.3` | First typed Rust-native systems facade implementation. |
| `haxe.rust-oo3.75.4` | No-hxrt/runtime-plan and output-shape gates. |
| `haxe.rust-oo3.75.5` | Public docs, FAQ/README sync, and app-level evidence refresh. |

## Review Notes

This is a `thinking:xhigh` scope decision because it affects public production language and the
boundary between portable Haxe semantics, `hxrt`, and Rust-native metal APIs.

Second-pass review for `haxe.rust-oo3.75.1`: the first slice should be file/path, not process,
socket/TLS, or DB. File/path has the best ratio of production value to deterministic proof. It also
keeps the central policy honest: portable sys APIs may keep `hxrt` when Haxe semantics require it,
while metal gets typed Rust-native surfaces with no-hxrt evidence where semantics allow.
