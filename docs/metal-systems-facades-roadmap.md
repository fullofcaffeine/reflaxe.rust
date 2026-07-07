# Metal Systems Facades Roadmap

This page owns the active plan for Rust-native systems surfaces: files, processes, sockets, TLS, DB
handles, and adjacent native handles. M43 delivered the first file/path slice; M44 delivered the
first owned-command process slice; M45 added a typed owned `CommandOutput` result; M46 added
explicit working-directory configuration for owned command runs.

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
| Process handles | Portable `sys.io.Process` uses `hxrt.process.ProcessHandle`; `rust.process.NativeCommands` is the app-facing owned-command facade, `rust.process.CommandOutput` carries owned status/stdout/stderr, and `rust.process.CommandEnv` carries typed environment overrides. | `hxrt` is justified for portable process streams and Haxe-style IO wrappers. The current Rust-first command facade stays no-hxrt by using explicit executable/args, explicit cwd/env overrides, and owned results. | Env removal/clearing, cwd+env convenience combinations, stdin piping, live handles, and async process remain future work. |
| Socket and TLS handles | `hxrt.net` / `hxrt.ssl` support portable sys surfaces and smoke fixtures. | Runtime ownership is justified for portable sockets/TLS and platform-sensitive setup. | Later work should separate blocking vs async, TLS setup, and no-hxrt limits. |
| DB handles | `hxrt.db` supports current SQLite smoke and MySQL compile coverage. | Runtime-heavy today; DB row/statement values are still portable/sys shaped. | Defer until file/process API families broaden beyond the first no-hxrt slices; typed DB facade is not the next slice. |
| RAII guards | Lock guards have scoped callbacks; docs define extern-island selection for heavier guards. | Simple lexical guards are scoped; complex guard internals stay in Rust islands. | File APIs should prefer owned-result helpers or scoped callbacks, not storable lifetime tokens. |

## M43 File/Path Slice

M43 started with a Rust-native file/path facade.

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

## M44 Process Slice

M44 started with owned command execution, not a live process-handle API.

Why this slice followed file/path:

- portable `sys.io.Process` already needs `hxrt.process.ProcessHandle` for live child ownership,
  Haxe `Input` / `Output` stream wrappers, shell fallback for omitted args, Haxe exceptions, and
  close/kill behavior
- a Rust-first process API can be narrower and more predictable: explicit executable, explicit args,
  owned status/stdout results, and no Haxe stream compatibility promise
- command fixtures can be deterministic if they avoid shell syntax and use the existing Rust
  toolchain executable (`rustc --version`) rather than host-specific utilities
- args must use Rust-native containers such as `rust.Vec<String>` for no-hxrt proof; ordinary Haxe
  `Array<String>` would import runtime array semantics into the metal contract

The first API family landed as `rust.process.NativeCommands`. The contract is:

- typed Haxe API under `rust.process.*`
- executable is a `String` or `rust.PathBuf` value passed directly to `std::process::Command::new`
  without shell fallback
- args are `rust.Ref<rust.Vec<String>>`, not `Array<String>`
- fallible calls return `rust.Result<..., String>` instead of throwing Haxe exceptions
- first slice proves owned status/stdout behavior with `statusCode(...)` and `stdoutUtf8(...)`
- M45 adds `outputUtf8(...) -> Result<CommandOutput, String>` so callers can inspect status,
  stdout, and stderr from one owned `std::process::Command::output()` run
- M46 adds `statusCodeInDir(...)` and `outputUtf8InDir(...)` so callers can set
  `std::process::Command::current_dir(...)` with a borrowed `rust.PathBuf`
- M47 adds `CommandEnv`, `statusCodeWithEnv(...)`, and `outputUtf8WithEnv(...)` so callers can set
  explicit `std::process::Command::env(...)` overrides through a typed Rust-native value
- no detached process, stdin pipe, live stdout/stderr streams, inherited-environment clearing/removal,
  async process, or kill/close API in the current slice
- generated Rust uses direct `std::process::Command` or a narrow typed helper module such as
  `std/rust/native/native_process_tools.rs`
- `-D reflaxe_rust_profile=metal -D rust_no_hxrt` fixture coverage proves no bundled runtime
  dependency or `hxrt::process` bridge appears for the selected subset

The first positive fixture compiles and cargo-runs a direct `rustc --version` command without
asserting the exact version string. It asserts only stable properties: status `0` and non-empty
UTF-8 stdout. The command-output fixture also asserts status `0`, non-empty stdout, and empty stderr
for `rustc --version` without asserting the exact version string. The first negative fixture rejects
app-side raw `std::process::Command` snippets as a substitute for the facade under strict metal
policy.

The cwd fixture runs `rustc --crate-type=lib --print=file-names cwd_probe.rs` from the generated
crate while setting `current_dir("..")`; without the cwd helper, `rustc` cannot find the fixture
source file and the cargo-run assertion traps.

The env fixture compiles a tiny Rust probe with `rustc`, then runs that probe through
`outputUtf8WithEnv(...)` with `CommandEnv.set(...)`. The probe prints only the overridden variable,
so the cargo-run assertion traps if `std::process::Command::env(...)` is not applied.

## Contract Fixtures

The M43 fixture bead added the initial contract before implementation:

| Fixture | Purpose |
| --- | --- |
| `test/positive/metal_no_hxrt_native_file` | Proves the current no-hxrt file/path subset compiles and cargo-builds without `hxrt`. |
| `test/negative/metal_fs_raw_escape` | Rejects app-side raw Rust as a substitute for the facade under strict policy. |
| `scripts/ci/check-metal-policy.sh` native-file output-shape case | Checks for avoidable `hxrt`, portable `FileHandle` / `sys_io` paths, and expected direct `std::fs` helper use. |
| `test/positive/metal_no_hxrt_native_process` | Proves the current no-hxrt owned-command subset compiles, cargo-builds, and cargo-runs without `hxrt`. |
| `test/positive/metal_no_hxrt_command_output` | Proves `CommandOutput` status/stdout/stderr inspection from one owned command run without `hxrt`. |
| `test/positive/metal_no_hxrt_command_cwd` | Proves explicit `Command::current_dir(...)` behavior for owned command status/output without `hxrt`. |
| `test/positive/metal_no_hxrt_command_env` | Proves explicit `Command::env(...)` overrides through `CommandEnv` without `hxrt`. |
| `test/negative/metal_process_raw_escape` | Rejects app-side raw `std::process::Command` as a substitute for the facade under strict policy. |
| `scripts/ci/check-metal-policy.sh` native-process output-shape cases | Checks for avoidable `hxrt`, `Dynamic`, raw, portable process paths, direct `std::process::Command` helper use, quiet status execution, owned stdout capture, owned `std::process::Output` conversion, direct `current_dir(cwd)` wiring, and direct `command.env(...)` wiring. |

Future expansion can add snapshots once these APIs grow beyond the current no-hxrt compile/run
contracts, but the evidence shape should stay contract-first.

## Non-Goals

This roadmap is not:

- a rewrite of portable `sys.io.*`
- a promise that all file/process/socket/TLS/DB APIs can omit `hxrt`
- a blanket cross-platform systems parity claim
- a DB/TLS/network service matrix
- an async systems runtime redesign
- a live process/pipe abstraction for metal before env/cwd/stdin semantics are designed

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
| `haxe.rust-oo3.76` | M44 Rust-native process facade and command-output proof milestone. |
| `haxe.rust-oo3.76.1` | Process-facade scope audit and deterministic fixture strategy. |
| `haxe.rust-oo3.76.2` | Contract-first process fixtures. |
| `haxe.rust-oo3.76.3` | First typed Rust-native process facade implementation. |
| `haxe.rust-oo3.76.4` | Process no-hxrt/runtime-plan and output-shape gates. |
| `haxe.rust-oo3.76.5` | Process docs, FAQ/README sync, and app-level evidence refresh. |
| `haxe.rust-oo3.77` | M45 typed command-output facade over owned `std::process::Output`. |
| `haxe.rust-oo3.77.1` | Command-output contract fixture. |
| `haxe.rust-oo3.77.2` | `rust.process.CommandOutput` extern and helper implementation. |
| `haxe.rust-oo3.77.3` | Command-output no-hxrt output-shape gate. |
| `haxe.rust-oo3.77.4` | Command-output docs and evidence refresh. |
| `haxe.rust-oo3.78` | M46 explicit command working-directory facade. |
| `haxe.rust-oo3.78.1` | Cwd command contract fixture. |
| `haxe.rust-oo3.78.2` | `statusCodeInDir` / `outputUtf8InDir` implementation. |
| `haxe.rust-oo3.78.3` | Cwd command no-hxrt output-shape gate. |
| `haxe.rust-oo3.78.4` | Cwd command docs and evidence refresh. |
| `haxe.rust-oo3.79` | M47 explicit command environment override facade. |
| `haxe.rust-oo3.79.1` | Env override command contract fixture. |
| `haxe.rust-oo3.79.2` | `CommandEnv` / `statusCodeWithEnv` / `outputUtf8WithEnv` implementation. |
| `haxe.rust-oo3.79.3` | Env command no-hxrt output-shape gate. |
| `haxe.rust-oo3.79.4` | Env command docs and evidence refresh. |

## Review Notes

This is a `thinking:xhigh` scope decision because it affects public production language and the
boundary between portable Haxe semantics, `hxrt`, and Rust-native metal APIs.

Second-pass review for `haxe.rust-oo3.75.1`: the first slice should be file/path, not process,
socket/TLS, or DB. File/path has the best ratio of production value to deterministic proof. It also
keeps the central policy honest: portable sys APIs may keep `hxrt` when Haxe semantics require it,
while metal gets typed Rust-native surfaces with no-hxrt evidence where semantics allow.

Second-pass review for `haxe.rust-oo3.76.1`: after M43, process is the right next systems slice, but
only as a narrow owned-command facade. Keep `sys.io.Process` on the portable runtime path because
live pipes, Haxe IO wrappers, omitted-args shell behavior, exceptions, and handle lifecycle semantics
are genuine runtime concerns. For the metal/no-hxrt proof, start with explicit command + args,
`rust.Vec<String>`, owned status/stdout results, and direct `std::process::Command` output-shape
gates. Defer live process handles until the owned-output contract is proven.

Second-pass review for `haxe.rust-oo3.77`: after the first owned-command proof, the smallest useful
process expansion is a typed `CommandOutput` value, not live handles. It preserves deterministic CI,
keeps portable `sys.io.Process` on the runtime path, and proves that status/stdout/stderr inspection
can stay on direct `std::process::Output` with no `hxrt` dependency.

Second-pass review for `haxe.rust-oo3.78`: explicit cwd is the next smallest process configuration
surface because it is deterministic in CI and still owned-output-only. Stdin and live handles need
separate API design because they introduce input ownership or lifecycle semantics.

Review note for `haxe.rust-oo3.79`: explicit per-command environment overrides are small enough for
the same owned-output facade because `std::process::Command::env(...)` mutates only the child
process builder, not process-global state. The first API exposes `CommandEnv.set(...)` only; inherited
environment clearing/removal and cwd+env convenience combinations remain future slices.
