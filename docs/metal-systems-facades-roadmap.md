# Metal Systems Facades Roadmap

This page owns the active plan for Rust-native systems surfaces: files, processes, sockets, TLS, DB
handles, and adjacent native handles. M43 delivered the first file/path slice; M44 delivered the
first owned-command process slice; M45 added a typed owned `CommandOutput` result; M46 added
explicit working-directory configuration for owned command runs; M47 added explicit environment
overrides; M48 added ordered environment remove/clear operations; M49 added combined cwd+env
owned-command calls; M50 added one-shot owned stdin input; M51 added combined stdin+cwd+env
owned-command calls; M52 added the owned `CommandSpec` config record; M53 added opt-in typed
`CommandError` records for owned-command IO/stdin/UTF-8 failures; M54 added the narrow
`CommandChild` live lifecycle handle; M55 added the first blocking localhost TCP facade; M56 added
the first blocking localhost UDP datagram facade; M57 added opt-in typed `SocketError` records for
TCP/UDP invalid-input, IO, and UTF-8 failures; M58 added UDP byte datagrams; M59 added TCP byte
streams; M60 added typed loopback `SocketAddr` values and a public no-hxrt metal networking
example.

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
| Process handles | Portable `sys.io.Process` uses `hxrt.process.ProcessHandle`; `rust.process.NativeCommands` is the app-facing owned-command facade, `rust.process.CommandOutput` carries owned status/stdout/stderr, `rust.process.CommandEnv` carries typed environment operations, `rust.process.CommandSpec` carries one owned command config, `rust.process.CommandError` carries opt-in typed error categories, and `rust.process.CommandChild` carries the narrow live child lifecycle handle. | `hxrt` is justified for portable process streams and Haxe-style IO wrappers. The current Rust-first command facade stays no-hxrt by using explicit executable/args, explicit cwd/env set-remove-clear/cwd+env operations, one-shot owned stdin input, combined stdin+cwd+env operations, a typed owned config record, owned results, typed IO/stdin/UTF-8/lifecycle error records, and a narrow live child that supports write-and-close stdin, wait, and kill/wait. | Reusable stdin pipes, live stdout/stderr streams, detached handles, async process, shell fallback, and portable `Process` parity remain future work. |
| Socket and TLS handles | `hxrt.net` / `hxrt.ssl` support portable sys surfaces and smoke fixtures. `rust.net.NativeTcp`, `rust.net.TcpListener`, and `rust.net.TcpStream` provide the first Rust-native blocking localhost TCP slice with UTF-8 and byte-stream payload methods; `rust.net.NativeUdp` and `rust.net.UdpSocket` provide the first Rust-native blocking localhost UDP datagram slice with UTF-8 and byte payload methods; `rust.net.SocketAddr` carries typed loopback addresses across bind/connect/send APIs; `rust.net.SocketError` provides the first opt-in typed TCP/UDP error categories. | Runtime ownership is justified for portable sockets/TLS and platform-sensitive setup. The current Rust-first TCP and UDP facades stay no-hxrt by wrapping direct `std::net` handles for deterministic loopback proofs, typed loopback address values, typed byte validation, and typed invalid-input/IO/UTF-8 error records. `SocketAddr` is explicitly a `lowering-candidate` native facade helper, not a second runtime. | Broader host/address APIs, DNS, external networking, live stream adapters, async networking, TLS setup, richer socket taxonomy beyond the first categories, and portable `sys.net` parity remain future work. |
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
- compatibility fallible calls return `rust.Result<..., String>` instead of throwing Haxe
  exceptions; opt-in `Detailed` calls return `rust.Result<..., CommandError>`
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
- M53 adds `CommandError`, `statusCodeDetailedFromSpec(...)`, `outputUtf8DetailedFromSpec(...)`,
  `stdoutUtf8Detailed()`, and `stderrUtf8Detailed()` so callers can opt into typed IO/stdin/UTF-8
  error categories while the original String-error methods remain source-compatible
- M54 adds `CommandChild` and `spawnChildFromSpec(...)` for a narrow live lifecycle handle with
  piped stdin, null stdout/stderr, one write-and-close stdin operation, `wait()`, and
  `killAndWait()`
- no detached process, reusable stdin pipe, live stdout/stderr streams, async process, shell
  fallback, or portable `sys.io.Process` parity in the current slice
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

The command-error fixture proves the opt-in typed error path. It checks a missing executable through
`statusCodeDetailedFromSpec(...)` as an IO error, then compiles a tiny probe that emits invalid
UTF-8 bytes and checks `stdoutUtf8Detailed()` returns a UTF-8 `CommandError`. The fixture does not
parse message strings for control flow.

The command-child fixture proves the narrow live lifecycle path. It compiles a tiny Rust probe that
blocks until stdin closes, then starts it through `spawnChildFromSpec(...)`. One child receives
`writeStdinAndClose(...)` and exits successfully through `wait()`; another blocked child is reaped
through `killAndWait()`. The fixture uses null stdout/stderr and does not expose live output streams
or reusable stdin pipes.

## M55 Native TCP Slice

M55 starts socket work with a blocking localhost TCP facade, not portable `sys.net.Socket` parity.

Why this slice follows file/process:

- local TCP loopback is deterministic enough for CI when it binds `127.0.0.1:0` and avoids external
  hosts, DNS, TLS, and service dependencies
- portable `sys.net.Socket` already has runtime-shaped stream wrappers and platform behavior, so the
  Rust-native surface must remain clearly separate
- a typed `rust.net.*` facade proves direct `std::net` handle ownership without committing to async,
  UDP, arbitrary host/address APIs, TLS, or broad stream adapters yet

The first API family landed as `rust.net.NativeTcp`, `rust.net.TcpListener`, and
`rust.net.TcpStream`. The contract is:

- typed Haxe API under `rust.net.*`
- bind/connect are explicitly localhost-only in this slice
- `bindLocalhost(0)` asks the OS for an ephemeral port and `localPort()` reports it for deterministic
  fixtures
- `accept()` returns one typed stream from the listener backlog
- `writeUtf8AndShutdownWrite(...)` writes one UTF-8 payload and shuts down only the write half
- `readToString()` reads UTF-8 text until EOF
- M57 adds `SocketError` and opt-in `Detailed` TCP methods so invalid facade inputs, IO failures,
  and UTF-8 decode failures can be handled without parsing String errors
- M59 adds `writeBytesAndShutdownWrite(...)` / `readBytes()` plus `Detailed` variants for byte
  streams represented as `rust.Vec<Int>` values; send bytes are validated as `0...255` before
  conversion to Rust `u8`
- no portable `sys.net.Socket` compatibility promise
- no TLS, UDP, async networking, DNS/host resolution, live stream adapter, or broader socket-error
  taxonomy in the current slice
- generated Rust uses direct `std::net` helpers in `std/rust/native/native_tcp_tools.rs`
- `-D reflaxe_rust_profile=metal -D rust_no_hxrt` fixture coverage proves no bundled runtime
  dependency or `hxrt::net` bridge appears for the selected subset

The native TCP fixture binds an ephemeral localhost listener, connects a client, accepts the server
stream, then exchanges one UTF-8 payload in each direction by pairing
`writeUtf8AndShutdownWrite(...)` with `readToString()`. It does not require threads, shell commands,
external network access, or a portable socket wrapper.

## M56 Native UDP Slice

M56 adds socket work for blocking localhost UDP datagrams, not portable `sys.net` UDP parity.

Why this slice follows TCP:

- two UDP sockets bound to `127.0.0.1:0` are deterministic enough for CI without external hosts,
  DNS, TLS, service dependencies, or threads
- datagram ownership is different enough from TCP streams to deserve its own typed facade and
  output-shape proof
- the narrow helper proved direct `std::net::UdpSocket` ownership before M58 added the first byte
  datagram API, and without committing to arbitrary host/address APIs, async networking, or TLS

The first API family landed as `rust.net.NativeUdp` and `rust.net.UdpSocket`. The contract is:

- typed Haxe API under `rust.net.*`
- bind/send are explicitly localhost-only in this slice
- `bindLocalhost(0)` asks the OS for an ephemeral port and `localPort()` reports it for
  deterministic fixtures
- `sendUtf8ToLocalhost(...)` sends one UTF-8 datagram to `127.0.0.1:<port>`
- `recvUtf8(...)` receives one datagram into an explicitly sized buffer and decodes it as UTF-8
- M57 adds `SocketError` and opt-in `Detailed` UDP methods so invalid facade inputs, IO failures,
  and UTF-8 decode failures can be handled without parsing String errors
- M58 adds `sendBytesToLocalhost(...)` / `recvBytes(...)` plus `Detailed` variants for byte
  datagrams represented as `rust.Vec<Int>` values; send bytes are validated as `0...255` before
  conversion to Rust `u8`
- no portable `sys.net.Socket` compatibility promise
- no TCP stream semantics, TLS, async networking, DNS/host resolution, live stream adapter,
  arbitrary host/address API, or broader socket-error taxonomy in the current slice
- generated Rust uses direct `std::net` helpers in `std/rust/native/native_udp_tools.rs`
- `-D reflaxe_rust_profile=metal -D rust_no_hxrt` fixture coverage proves no bundled runtime
  dependency or `hxrt::net` bridge appears for the selected subset

The native UDP fixture binds two ephemeral localhost sockets, reads both assigned ports, then sends
one UTF-8 datagram in each direction with `sendUtf8ToLocalhost(...)` and `recvUtf8(...)`. It does
not require threads, shell commands, external network access, or a portable socket wrapper.

## M57 Typed Socket Error Slice

M57 adds a typed error record to the existing localhost TCP/UDP facades. It does not broaden the
networking surface.

Why this slice follows TCP and UDP:

- callers need recovery policy without parsing diagnostic strings
- invalid facade inputs can be proven deterministically with out-of-range ports and receive sizes
- UTF-8 receive errors can be proven on localhost with a tiny typed test-only extern island that
  sends invalid UDP bytes; M58 later replaces that test-only workaround with the first public UDP
  byte datagram API
- the existing String-error methods stay source-compatible, and typed errors are opt-in through
  `Detailed` methods

The API family is `rust.net.SocketError` plus `Detailed` variants on the TCP/UDP helpers. The first
taxonomy is deliberately small:

- `isInvalidInput()` covers facade contract failures such as invalid port values or non-positive UDP
  receive buffer sizes
- `isIo()` covers native `std::io::Error` paths
- `isUtf8()` covers UTF-8 receive/decode failures
- `message()` is for diagnostics only; callers should branch on the typed predicates first

M57 itself is still not portable `sys.net.Socket`, arbitrary host/address networking, TLS, async
networking, DNS, live stream adapters, or a complete socket error hierarchy.

## M58 UDP Byte Datagram Slice

M58 adds byte datagrams to the existing localhost UDP facade. It does not broaden the networking
surface beyond localhost blocking UDP.

Why this slice follows typed socket errors:

- M57 proved invalid UTF-8 only with a test-only extern island; a first-party byte datagram facade
  removes that workaround for app code
- Haxe `Int` maps to Rust `i32`, so the public API uses `rust.Vec<Int>` and validates `0...255`
  before the helper creates a Rust `Vec<u8>`
- localhost UDP byte payloads are deterministic in CI and do not require `haxe.io.Bytes`, `hxrt`,
  DNS, arbitrary hosts, TLS, async runtimes, or service dependencies

The API family is on `rust.net.UdpSocket`:

- `sendBytesToLocalhost(...)` sends one byte datagram to `127.0.0.1:<port>` and returns
  `Result<Int, String>`
- `recvBytes(...)` receives one datagram into an explicitly sized buffer and returns
  `Result<Vec<Int>, String>`
- `sendBytesToLocalhostDetailed(...)` and `recvBytesDetailed(...)` return `SocketError` so invalid
  byte values, invalid receive sizes, and IO failures remain typed
- received bytes are returned as `Vec<Int>` values in `0...255`

This is still not portable `haxe.io.Bytes`, portable `sys.net.Socket`, arbitrary host/address
networking, TLS, async networking, DNS, live stream adapters, or a complete socket error hierarchy.

## M59 TCP Byte Stream Slice

M59 adds byte streams to the existing localhost TCP facade. It does not broaden the networking
surface beyond localhost blocking TCP.

Why this slice follows UDP byte datagrams:

- M58 proved the `rust.Vec<Int>` byte-boundary pattern and invalid-byte diagnostics without pulling
  in `haxe.io.Bytes` or `hxrt`
- TCP stream ownership is already proven by M55; the missing piece was an owned byte payload path
  that pairs `write_all(&bytes)` with read-to-EOF behavior
- localhost TCP byte payloads are deterministic in CI and do not require portable socket wrappers,
  runtime byte buffers, DNS, arbitrary hosts, TLS, async runtimes, or service dependencies

The API family is on `rust.net.TcpStream`:

- `writeBytesAndShutdownWrite(...)` writes one byte payload and shuts down only the write half,
  returning `Result<Bool, String>`
- `readBytes()` reads until EOF and returns `Result<Vec<Int>, String>`
- `writeBytesAndShutdownWriteDetailed(...)` and `readBytesDetailed()` return `SocketError` so
  invalid byte values and IO failures remain typed
- received bytes are returned as `Vec<Int>` values in `0...255`

This is still not portable `haxe.io.Bytes`, portable `sys.net.Socket`, arbitrary host/address
networking, TLS, async networking, DNS, live stream adapters, reusable stream adapters, or a
complete socket error hierarchy.

## M60 Typed Socket Address Slice

M60 adds `rust.net.SocketAddr` to the existing localhost TCP/UDP facade. It does not broaden the
networking contract beyond loopback.

Why this slice follows TCP byte streams:

- M55-M59 proved direct TCP/UDP handle ownership, typed errors, and typed byte payloads without
  `hxrt`, but call sites still needed port-oriented helpers when moving from an OS-assigned bind to
  a later connect/send
- a typed address value lets `localAddr()` flow into `connectDetailed(...)`, `bindDetailed(...)`, and
  `sendBytesToDetailed(...)` without string parsing, raw Rust snippets, or arbitrary host support
- loopback-only addresses keep the fixture deterministic in CI and avoid DNS, external networking,
  `ToSocketAddrs` polymorphism, or a broader portable socket promise

The API family is:

- `SocketAddr.localhost(...)` and `SocketAddr.localhostDetailed(...)` construct a loopback address
  from a validated port
- `SocketAddr.port()` exposes the assigned port for diagnostics and handoff
- `TcpListener.localAddr()` / `localAddrDetailed()` and `UdpSocket.localAddr()` /
  `localAddrDetailed()` return typed addresses
- `NativeTcp.bind(...)` / `bindDetailed(...)` and `NativeTcp.connect(...)` /
  `connectDetailed(...)` accept typed addresses
- `NativeUdp.bind(...)` / `bindDetailed(...)` and `UdpSocket.sendUtf8To(...)` /
  `sendBytesTo(...)` plus their `Detailed` variants accept typed addresses

The helper backing `SocketAddr` is classified as `lowering-candidate` under the native facade policy:
it is allowed for M60 because the current compiler cannot declare the wrapper field and crate-private
`std::net::SocketAddr` conversions cleanly from Haxe externs, while `localhost(...)` and `port()` are
simple enough to revisit with compiler-generated native wrappers or direct lowering later.

This is still not portable `sys.net.Socket`, arbitrary host/address networking, DNS, external
network access, TLS, async networking, live stream adapters, or a complete socket abstraction.

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
| `test/positive/metal_no_hxrt_command_error` | Proves opt-in typed `CommandError` categories for owned-command IO and UTF-8 failures without `hxrt`. |
| `test/positive/metal_no_hxrt_command_child` | Proves narrow `CommandChild` live lifecycle operations without `hxrt`. |
| `test/negative/metal_process_raw_escape` | Rejects app-side raw `std::process::Command` as a substitute for the facade under strict policy. |
| `scripts/ci/check-metal-policy.sh` native-process output-shape cases | Checks for avoidable `hxrt`, `Dynamic`, raw, portable process paths, direct `std::process::Command` helper use, quiet status execution, owned stdout capture, owned `std::process::Output` conversion, direct `current_dir(cwd)` wiring, direct `command.env(...)` / `env_remove(...)` / `env_clear()` wiring, composed cwd+env helper wiring, direct `Stdio::piped` / `write_all` / `wait_with_output` stdin wiring, composed stdin+cwd+env helper wiring, `CommandSpec` owned config storage plus `command_from_spec` builder wiring, `CommandError` typed category/output-decode wiring, and `CommandChild` direct `std::process::Child` lifecycle wiring. |
| `test/positive/metal_no_hxrt_native_tcp` | Proves a typed blocking localhost TCP round trip through `rust.net.NativeTcp`, `TcpListener`, and `TcpStream` without `hxrt`. |
| `scripts/ci/check-metal-policy.sh` native-TCP output-shape case | Checks for avoidable `hxrt`, `Dynamic`, raw, portable socket paths, direct `std::net` wrapper structs, localhost bind/connect wiring, `accept`, `write_all`, `Shutdown::Write`, and `read_to_string`. |
| `test/positive/metal_no_hxrt_native_udp` | Proves a typed blocking localhost UDP datagram round trip through `rust.net.NativeUdp` and `UdpSocket` without `hxrt`. |
| `scripts/ci/check-metal-policy.sh` native-UDP output-shape case | Checks for avoidable `hxrt`, `Dynamic`, raw, portable socket paths, direct `std::net::UdpSocket` wrapper structs, localhost bind/send wiring, `recv_from`, and UTF-8 decode. |
| `test/positive/metal_no_hxrt_socket_error` | Proves opt-in typed `SocketError` categories for TCP/UDP invalid input and UDP UTF-8 decode failures without `hxrt`. |
| `scripts/ci/check-metal-policy.sh` socket-error output-shape case | Checks for avoidable `hxrt`, `Dynamic`, raw, portable socket paths, shared `SocketError` helper categories, detailed TCP/UDP methods, and invalid-input/IO/UTF-8 mappings. |
| `test/positive/metal_no_hxrt_udp_bytes` | Proves typed UDP byte datagram send/receive plus invalid byte classification without `hxrt` or `haxe.io.Bytes`. |
| `scripts/ci/check-metal-policy.sh` UDP byte output-shape case | Checks for avoidable `hxrt`, `Dynamic`, raw, portable socket/byte-buffer paths, direct `std::net::UdpSocket` send/receive wiring, `Vec<i32>`/`Vec<u8>` conversion, and invalid byte mapping to `SocketError`. |
| `test/positive/metal_no_hxrt_tcp_bytes` | Proves typed TCP byte-stream send/read plus invalid byte classification without `hxrt` or `haxe.io.Bytes`. |
| `scripts/ci/check-metal-policy.sh` TCP byte output-shape case | Checks for avoidable `hxrt`, `Dynamic`, raw, portable socket/byte-buffer paths, direct `std::net::TcpStream` `write_all`/`read_to_end` wiring, `Vec<i32>`/`Vec<u8>` conversion, write-half shutdown, and invalid byte mapping to `SocketError`. |
| `test/positive/metal_no_hxrt_socket_addr` | Proves typed loopback `SocketAddr` values for TCP bind/connect and UDP bind/send without `hxrt`. |
| `scripts/ci/check-metal-policy.sh` socket-address output-shape case | Checks for avoidable `hxrt`, `Dynamic`, raw, portable socket paths, generated typed call sites, direct `std::net::SocketAddr` storage, crate-private conversions, and direct TCP/UDP helper use of `addr.as_std()`. |

Future expansion can add snapshots once these APIs grow beyond the current no-hxrt compile/run
contracts, but the evidence shape should stay contract-first.

## Non-Goals

This roadmap is not:

- a rewrite of portable `sys.io.*`
- a promise that all file/process/socket/TLS/DB APIs can omit `hxrt`
- a blanket cross-platform systems parity claim
- a DB/TLS/network service matrix
- an async systems runtime redesign
- a broad live process/pipe abstraction for metal beyond the narrow `CommandChild` lifecycle proof
- a broad socket/TLS/async networking abstraction beyond the narrow blocking localhost TCP and UDP
  proofs

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
| `haxe.rust-oo3.85` | M53 typed command-error owned-command facade. |
| `haxe.rust-oo3.85.1` | CommandError contract fixture. |
| `haxe.rust-oo3.85.2` | `CommandError` / detailed command and output helper implementation. |
| `haxe.rust-oo3.85.3` | CommandError no-hxrt output-shape gate. |
| `haxe.rust-oo3.85.4` | CommandError docs and evidence refresh. |
| `haxe.rust-oo3.86` | M54 narrow live command-child lifecycle facade. |
| `haxe.rust-oo3.86.1` | CommandChild contract fixture. |
| `haxe.rust-oo3.86.2` | `CommandChild` / `spawnChildFromSpec` lifecycle implementation. |
| `haxe.rust-oo3.86.3` | CommandChild no-hxrt output-shape gate. |
| `haxe.rust-oo3.86.4` | CommandChild docs and evidence refresh. |
| `haxe.rust-oo3.87` | M55 blocking localhost TCP facade. |
| `haxe.rust-oo3.87.1` | Native TCP contract fixture. |
| `haxe.rust-oo3.87.2` | `rust.net.NativeTcp`, `TcpListener`, and `TcpStream` implementation. |
| `haxe.rust-oo3.87.3` | Native TCP no-hxrt output-shape gate. |
| `haxe.rust-oo3.87.4` | Native TCP docs and evidence refresh. |
| `haxe.rust-oo3.88` | M56 blocking localhost UDP datagram facade. |
| `haxe.rust-oo3.88.1` | Native UDP contract fixture. |
| `haxe.rust-oo3.88.2` | `rust.net.NativeUdp` and `UdpSocket` implementation. |
| `haxe.rust-oo3.88.3` | Native UDP no-hxrt output-shape gate. |
| `haxe.rust-oo3.88.4` | Native UDP docs and evidence refresh. |
| `haxe.rust-oo3.89` | M57 typed socket-error TCP/UDP facade. |
| `haxe.rust-oo3.89.1` | SocketError contract fixture. |
| `haxe.rust-oo3.89.2` | `rust.net.SocketError` and Detailed TCP/UDP implementation. |
| `haxe.rust-oo3.89.3` | SocketError no-hxrt output-shape gate. |
| `haxe.rust-oo3.89.4` | SocketError docs and evidence refresh. |
| `haxe.rust-oo3.90` | M58 UDP byte datagram facade. |
| `haxe.rust-oo3.90.1` | UDP byte datagram contract fixture. |
| `haxe.rust-oo3.90.2` | `UdpSocket` byte send/receive implementation. |
| `haxe.rust-oo3.90.3` | UDP byte datagram no-hxrt output-shape gate. |
| `haxe.rust-oo3.90.4` | UDP byte datagram docs and evidence refresh. |
| `haxe.rust-oo3.91` | M59 TCP byte stream facade. |
| `haxe.rust-oo3.91.1` | TCP byte stream contract fixture. |
| `haxe.rust-oo3.91.2` | `TcpStream` byte write/read implementation. |
| `haxe.rust-oo3.91.3` | TCP byte stream no-hxrt output-shape gate. |
| `haxe.rust-oo3.91.4` | TCP byte stream docs and evidence refresh. |
| `haxe.rust-oo3.92` | M60 typed socket address facade plus examples audit. |
| `haxe.rust-oo3.92.1` | SocketAddr contract fixture. |
| `haxe.rust-oo3.92.2` | `rust.net.SocketAddr` plus typed TCP/UDP address implementation. |
| `haxe.rust-oo3.92.3` | SocketAddr no-hxrt output-shape gate. |
| `haxe.rust-oo3.92.4` | Examples audit and `examples/metal_native_net`. |
| `haxe.rust-oo3.92.5` | Native facade policy, docs, and evidence refresh. |
| `haxe.rust-oo3.93` | Native facade helper manifest and growth guard. |
| `haxe.rust-oo3.94` | Follow-up compiler-generated native wrapper facility spike. |
| `haxe.rust-oo3.95` | Follow-up `SocketAddr` lowering-candidate graduation. |
| `haxe.rust-oo3.96` | Follow-up resource lifecycle native facade review. |

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
gates. M54 later adds the first narrow live child lifecycle handle after the owned-output contract is
proven.

Second-pass review for `haxe.rust-oo3.77`: after the first owned-command proof, the smallest useful
process expansion is a typed `CommandOutput` value, not broad live handles. It preserves
deterministic CI, keeps portable `sys.io.Process` on the runtime path, and proves that
status/stdout/stderr inspection can stay on direct `std::process::Output` with no `hxrt` dependency.

Second-pass review for `haxe.rust-oo3.78`: explicit cwd is the next smallest process configuration
surface because it is deterministic in CI and still owned-output-only. Stdin and broad live handles
need separate API design because they introduce input ownership or lifecycle semantics.

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
`apply_env(...)` helpers instead of introducing a broader command configuration object. Stdin, broad
live handles, async process, and kill/close lifecycle semantics remained separate design slices at
M49. M52 later adds the typed owned config record after the individual builder dimensions are proven,
and M54 adds the narrow child lifecycle proof.

Review note for `haxe.rust-oo3.82`: one-shot stdin input stays in the owned-output command subset
because the helper owns the child process and pipe lifecycle internally, writes one `String` into
`Stdio::piped()` stdin, closes that pipe before waiting, and returns only status or
`CommandOutput`. This is not a live `stdin` stream API. Reusable stdin pipes, stdin combined with
cwd/env builder dimensions, async process, and broad child lifecycle semantics remained separate
design slices at M50. M51 handles stdin+cwd+env composition, M52 handles the typed owned config
record, and M54 adds the narrow child lifecycle proof.

Review note for `haxe.rust-oo3.83`: stdin+cwd+env combinations remain a composition of already
proven owned-command builder dimensions. The helper builds a direct `std::process::Command` with
`current_dir(...)` and ordered `CommandEnv` mutations, then hands that configured command to the
same one-shot stdin writer used by M50. This still returns only status or owned `CommandOutput`;
reusable/live stdin pipes, async process, broad live handles, and kill/close lifecycle semantics
remained separate design slices at M51. M52 follows by replacing further combination growth with a
typed owned config record, and M54 later adds a narrow child lifecycle handle.

Review note for `haxe.rust-oo3.84`: `CommandSpec` is the right next step after proving the separate
owned-command builder dimensions. It owns cloned program/args plus optional cwd, `CommandEnv`, and
stdin data, then builds a fresh `std::process::Command` for each status/output run. This keeps the
API typed and no-hxrt while avoiding more method-combination growth. It is still not a broad live
process handle, reusable pipe, async API, shell wrapper, or typed process-error taxonomy. M53 follows
with a narrow typed-error taxonomy for owned-command IO/stdin/UTF-8 failures only, and M54 follows
with the first narrow live child lifecycle handle.

Review note for `haxe.rust-oo3.85`: `CommandError` is the right next step after `CommandSpec`
because it improves recovery policy without introducing live process ownership. It is opt-in through
`Detailed` methods so existing `Result<..., String>` callers stay source-compatible. The first
taxonomy is deliberately small: IO covers spawn/wait/output errors, stdin covers helper-owned pipe
setup/write failures, and UTF-8 covers captured output decoding. M54 follows with the narrow live
child lifecycle proof; reusable pipes, live output streams, async process, and shell behavior remain
separate design work.

Review note for `haxe.rust-oo3.86`: `CommandChild` is the smallest justified live process handle
after the owned-command and typed-error slices. It owns `std::process::Child`, spawns from a
`CommandSpec` with piped stdin and null stdout/stderr, allows exactly one write-and-close stdin
operation, and exposes `wait()` plus `killAndWait()` so children are reaped. It deliberately rejects
`CommandSpec.withStdin(...)` at the live-spawn boundary because one-shot stdin belongs to the owned
status/output helpers. This is still not portable `sys.io.Process`: reusable stdin pipes, live
stdout/stderr streams, detached handles, shell fallback, and async process APIs remain future work.

Review note for `haxe.rust-oo3.87`: after file and process no-hxrt patterns are proven, a blocking
localhost TCP loopback facade is the narrowest socket slice with useful production shape and
deterministic CI evidence. It binds `127.0.0.1:0`, reports the assigned port, connects through
`std::net::TcpStream`, accepts one `std::net::TcpStream`, and exchanges UTF-8 payloads with explicit
write-half shutdown. This is still not portable `sys.net.Socket`: arbitrary hosts, DNS, UDP, TLS,
async networking, byte payloads, live stream adapters, and deeper socket error categories remained
separate design work at M55. M59 later adds the first localhost TCP byte-stream slice.

Review note for `haxe.rust-oo3.88`: after the TCP localhost proof, UDP localhost datagrams are the
next narrow socket slice with deterministic CI value. The facade binds two direct
`std::net::UdpSocket` wrappers to `127.0.0.1:0`, reports assigned ports, sends one UTF-8 datagram to
a localhost port, and receives one UTF-8 datagram through an explicit buffer-size contract. This is
still not portable `sys.net.Socket`: arbitrary hosts, DNS, TLS, async networking, byte datagrams,
live stream adapters, and deeper socket error categories remain separate design work at M56. M58
later adds the first localhost UDP byte-datagram slice.

Review note for `haxe.rust-oo3.89`: after both TCP and UDP localhost shapes are proven, typed socket
errors are the smallest useful recovery-policy slice. Keep existing `Result<..., String>` methods
source-compatible and add opt-in `Detailed` variants returning `SocketError`. The first taxonomy is
invalid-input, IO, and UTF-8 only; arbitrary hosts, DNS, TLS, async, live streams, and deeper
platform-specific socket categories remain future work. TCP byte streams were intentionally left
out of M57/M58 and handled later by M59.

Review note for `haxe.rust-oo3.90`: after typed socket errors, UDP byte datagrams are the smallest
slice that removes a real test-only extern workaround without broadening the network contract. Keep
the Haxe surface as `rust.Vec<Int>` because Haxe has no native `u8`; validate `0...255` at the
helper boundary and keep the direct Rust buffer as `Vec<u8>`. This is still not portable
`haxe.io.Bytes`, arbitrary host/address networking, TLS, async, live stream adapters, or a general
socket byte-stream abstraction.

Review note for `haxe.rust-oo3.91`: after both typed socket errors and UDP byte datagrams are
proven, TCP byte streams are the next smallest byte-payload surface. Keep the Haxe boundary as
`rust.Vec<Int>` for consistency with UDP bytes, validate `0...255` before touching the Rust `Vec<u8>`,
and continue using explicit write-half shutdown plus read-to-EOF. This is still not portable
`haxe.io.Bytes`, arbitrary host/address networking, TLS, async, live stream adapters, or a general
socket abstraction.

Oracle review note for `haxe.rust-oo3.92`: GPT-5.5 Pro returned `APPROVE_WITH_CHANGES`. The path
forward is to land `SocketAddr` as a narrow typed native facade, not to block M60 on compiler-generated
wrapper lowering. `rust_no_hxrt` means no Haxe semantic runtime dependency; it does not forbid small,
typed Rust-native facade modules. The closure requirements are stricter policy and evidence: classify
`SocketAddr` as `lowering-candidate`, keep it loopback-only, document why lowering is insufficient
today, inspect generated call sites, prove no `hxrt` dependency, run rustfmt/cargo/clippy evidence
where feasible, and track broader native-wrapper codegen plus helper-growth controls as follow-up
Beads.
