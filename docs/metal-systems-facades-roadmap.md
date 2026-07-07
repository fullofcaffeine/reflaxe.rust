# Metal Systems Facades Roadmap

This page owns the active plan for Rust-native systems surfaces: files, processes, sockets, TLS, DB
handles, and adjacent native handles. M43 delivered the first file/path slice; M44 delivered the
first owned-command process slice; M45 added a typed owned `CommandOutput` result; M46 added
explicit working-directory configuration for owned command runs; M47 added explicit environment
overrides; M48 added ordered environment remove/clear operations; M49 added combined cwd+env
owned-command calls; M50 added one-shot owned stdin input; M51 added combined stdin+cwd+env
owned-command calls; M52 added the owned `CommandSpec` config record.

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
| Process handles | Portable `sys.io.Process` uses `hxrt.process.ProcessHandle`; `rust.process.NativeCommands` is the app-facing owned-command facade, `rust.process.CommandOutput` carries owned status/stdout/stderr, `rust.process.CommandEnv` carries typed environment operations, and `rust.process.CommandSpec` carries one owned command config. | `hxrt` is justified for portable process streams and Haxe-style IO wrappers. The current Rust-first command facade stays no-hxrt by using explicit executable/args, explicit cwd/env set-remove-clear/cwd+env operations, one-shot owned stdin input, combined stdin+cwd+env operations, a typed owned config record, and owned results. | Reusable/live stdin pipes, live handles, async process, richer typed error records, and kill/close lifecycle semantics remain future work. |
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
- M48 extends `CommandEnv` with ordered `remove(...)` and `clear()` operations backed by direct
  `std::process::Command::env_remove(...)` and `env_clear()` calls
- M49 adds `statusCodeInDirWithEnv(...)` and `outputUtf8InDirWithEnv(...)` so callers can combine
  explicit `current_dir(...)` with ordered `CommandEnv` mutations in the owned-output subset
- M50 adds `statusCodeWithStdin(...)` and `outputUtf8WithStdin(...)` so callers can pass one owned
  UTF-8 input string to child stdin while the helper owns the child pipe lifecycle internally
- M51 adds `statusCodeInDirWithEnvAndStdin(...)` and
  `outputUtf8InDirWithEnvAndStdin(...)` so callers can combine explicit `current_dir(...)`,
  ordered `CommandEnv` mutations, and one owned stdin string without exposing live child handles
- M52 adds `CommandSpec`, `statusCodeFromSpec(...)`, and `outputUtf8FromSpec(...)` so callers can
  keep program/args plus optional cwd, env, and stdin in one typed owned config value
- no detached process, reusable stdin pipe, live stdout/stderr streams, async process, richer typed
  error record, or kill/close API in the current slice
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

The env-ops fixture reuses the same owned-output path to prove ordered environment mutations. It
first checks `set(...); remove(...)` prevents a variable from reaching the child process, then checks
`clear(); set(...)` runs the child with a cleared inherited environment plus one explicit variable.

The cwd+env fixture compiles a Rust source file that only resolves from the fixture root while also
requiring an environment variable supplied by `CommandEnv` and rejecting one removed by
`CommandEnv.remove(...)`. It runs both `statusCodeInDirWithEnv(...)` and
`outputUtf8InDirWithEnv(...)`, so the same no-hxrt helper path proves the combined builder shape.

The stdin fixture compiles a small Rust probe with `rustc`, then runs the probe with
`statusCodeWithStdin(...)` and `outputUtf8WithStdin(...)`. The probe succeeds only when the exact
owned UTF-8 string reaches child stdin and then reports owned stdout/stderr through
`CommandOutput`, so this remains a one-shot owned-output contract rather than a live pipe API.

The stdin+cwd+env fixture feeds Rust source to `rustc -` through
`statusCodeInDirWithEnvAndStdin(...)` and `outputUtf8InDirWithEnvAndStdin(...)`. The status call
writes an rlib into a cwd-relative fixture subdirectory; the output call then consumes that rlib via
a cwd-relative `--extern` path while also requiring `CommandEnv` to supply one variable and remove
another. This proves composition of cwd, env, stdin, and owned output without adding a live process
handle.

The command-spec fixture repeats the same deterministic stdin+cwd+env proof through
`CommandSpec`, `statusCodeFromSpec(...)`, and `outputUtf8FromSpec(...)`. The Rust helper owns cloned
program/args plus optional cwd, `CommandEnv`, and stdin data, then builds a fresh
`std::process::Command` for each owned status/output run.

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
| `test/positive/metal_no_hxrt_command_env_ops` | Proves ordered `CommandEnv.remove(...)` and `CommandEnv.clear()` behavior without `hxrt`. |
| `test/positive/metal_no_hxrt_command_cwd_env` | Proves combined explicit cwd plus ordered `CommandEnv` behavior without `hxrt`. |
| `test/positive/metal_no_hxrt_command_stdin` | Proves one-shot owned stdin input for command status/output without `hxrt`. |
| `test/positive/metal_no_hxrt_command_stdin_cwd_env` | Proves combined one-shot stdin input, explicit cwd, and ordered `CommandEnv` behavior without `hxrt`. |
| `test/positive/metal_no_hxrt_command_spec` | Proves typed `CommandSpec` config values can combine program/args, optional cwd, env, and stdin without `hxrt`. |
| `test/negative/metal_process_raw_escape` | Rejects app-side raw `std::process::Command` as a substitute for the facade under strict policy. |
| `scripts/ci/check-metal-policy.sh` native-process output-shape cases | Checks for avoidable `hxrt`, `Dynamic`, raw, portable process paths, direct `std::process::Command` helper use, quiet status execution, owned stdout capture, owned `std::process::Output` conversion, direct `current_dir(cwd)` wiring, direct `command.env(...)` / `env_remove(...)` / `env_clear()` wiring, composed cwd+env helper wiring, direct `Stdio::piped` / `write_all` / `wait_with_output` stdin wiring, composed stdin+cwd+env helper wiring, and `CommandSpec` owned config storage plus `command_from_spec` builder wiring. |

Future expansion can add snapshots once these APIs grow beyond the current no-hxrt compile/run
contracts, but the evidence shape should stay contract-first.

## Non-Goals

This roadmap is not:

- a rewrite of portable `sys.io.*`
- a promise that all file/process/socket/TLS/DB APIs can omit `hxrt`
- a blanket cross-platform systems parity claim
- a DB/TLS/network service matrix
- an async systems runtime redesign
- a live process/pipe abstraction for metal before stdin and lifecycle semantics are designed

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
| `haxe.rust-oo3.80` | M48 command environment removal/clear facade. |
| `haxe.rust-oo3.80.1` | Env remove/clear command contract fixture. |
| `haxe.rust-oo3.80.2` | `CommandEnv.remove` / `CommandEnv.clear` implementation. |
| `haxe.rust-oo3.80.3` | Env remove/clear no-hxrt output-shape gate. |
| `haxe.rust-oo3.80.4` | Env remove/clear docs and evidence refresh. |
| `haxe.rust-oo3.81` | M49 combined cwd+env owned-command facade. |
| `haxe.rust-oo3.81.1` | Cwd+env command contract fixture. |
| `haxe.rust-oo3.81.2` | `statusCodeInDirWithEnv` / `outputUtf8InDirWithEnv` implementation. |
| `haxe.rust-oo3.81.3` | Cwd+env no-hxrt output-shape gate. |
| `haxe.rust-oo3.81.4` | Cwd+env docs and evidence refresh. |
| `haxe.rust-oo3.82` | M50 one-shot stdin-input owned-command facade. |
| `haxe.rust-oo3.82.1` | Stdin-input command contract fixture. |
| `haxe.rust-oo3.82.2` | `statusCodeWithStdin` / `outputUtf8WithStdin` implementation. |
| `haxe.rust-oo3.82.3` | Stdin-input no-hxrt output-shape gate. |
| `haxe.rust-oo3.82.4` | Stdin-input docs and evidence refresh. |
| `haxe.rust-oo3.83` | M51 combined stdin+cwd+env owned-command facade. |
| `haxe.rust-oo3.83.1` | Stdin+cwd+env command contract fixture. |
| `haxe.rust-oo3.83.2` | `statusCodeInDirWithEnvAndStdin` / `outputUtf8InDirWithEnvAndStdin` implementation. |
| `haxe.rust-oo3.83.3` | Stdin+cwd+env no-hxrt output-shape gate. |
| `haxe.rust-oo3.83.4` | Stdin+cwd+env docs and evidence refresh. |
| `haxe.rust-oo3.84` | M52 typed command-spec owned-command facade. |
| `haxe.rust-oo3.84.1` | CommandSpec command contract fixture. |
| `haxe.rust-oo3.84.2` | `CommandSpec` / `statusCodeFromSpec` / `outputUtf8FromSpec` implementation. |
| `haxe.rust-oo3.84.3` | CommandSpec no-hxrt output-shape gate. |
| `haxe.rust-oo3.84.4` | CommandSpec docs and evidence refresh. |

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
process builder, not process-global state. The first API exposed `CommandEnv.set(...)` only; ordered
environment clearing/removal and cwd+env combinations were left for later slices; M48 handled
remove/clear and M49 handled cwd+env.

Review note for `haxe.rust-oo3.80`: env removal and clearing stay in the same owned-output
`CommandEnv` value because they are still child process builder mutations, not process-global state.
The operation list is intentionally ordered so `set(...); remove(...)` and `clear(); set(...)`
preserve Rust `std::process::Command` semantics. Cwd+env convenience combinations were left as a
separate follow-up because they combine two already-proven builder dimensions.

Review note for `haxe.rust-oo3.81`: combining cwd and env stays in the owned-output command subset
because it only composes `std::process::Command::current_dir(...)` with ordered environment builder
mutations. The implementation intentionally reuses the existing `command_in_dir(...)` and
`apply_env(...)` helpers instead of introducing a broader command configuration object. Stdin, live
handles, async process, richer typed error records, and kill/close lifecycle semantics remain
separate design slices. M52 later adds the typed owned config record after the individual builder
dimensions are proven.

Review note for `haxe.rust-oo3.82`: one-shot stdin input stays in the owned-output command subset
because the helper owns the child process and pipe lifecycle internally, writes one `String` into
`Stdio::piped()` stdin, closes that pipe before waiting, and returns only status or
`CommandOutput`. This is not a live `stdin` stream API. Reusable stdin pipes, stdin combined with
cwd/env builder dimensions, async process, richer typed error records, and kill/close lifecycle
semantics remain separate design slices. M51 handles stdin+cwd+env composition and M52 handles the
typed owned config record.

Review note for `haxe.rust-oo3.83`: stdin+cwd+env combinations remain a composition of already
proven owned-command builder dimensions. The helper builds a direct `std::process::Command` with
`current_dir(...)` and ordered `CommandEnv` mutations, then hands that configured command to the
same one-shot stdin writer used by M50. This still returns only status or owned `CommandOutput`;
reusable/live stdin pipes, async process, live handles, richer typed error records, and kill/close
lifecycle semantics remain separate design slices. M52 follows by replacing further combination
growth with a typed owned config record.

Review note for `haxe.rust-oo3.84`: `CommandSpec` is the right next step after proving the separate
owned-command builder dimensions. It owns cloned program/args plus optional cwd, `CommandEnv`, and
stdin data, then builds a fresh `std::process::Command` for each status/output run. This keeps the
API typed and no-hxrt while avoiding more method-combination growth. It is still not a live process
handle, reusable pipe, async API, shell wrapper, or typed process-error taxonomy.
