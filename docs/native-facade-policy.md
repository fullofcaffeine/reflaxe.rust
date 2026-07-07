# Native Facade Helper Policy

`std/rust/native/*.rs` modules are typed Rust-native facade backing code. They are not `hxrt`, and
they must not grow into a second runtime.

## Why

The compiler has two product promises that can pull in opposite directions:

- generated Rust should stay close to hand-written Rust when Haxe semantics permit it
- users should call typed Haxe APIs, not raw Rust snippets, `Dynamic` handles, or app-local generated
  Rust patches

Some Rust APIs need a small amount of Rust code because the current Haxe surface cannot declare the
real Rust shape cleanly. Examples include private fields, RAII handles, partial moves, `Drop`-sensitive
behavior, trait impl bodies, lifetimes, HRTB, const generics, macro-heavy setup, or contained unsafe
internals.

The policy is not "no handwritten Rust." The policy is "no hidden runtime drift." A helper that owns
one Rust resource behind a typed `rust.*` facade is acceptable. A helper that starts collecting broad
services, type-erased handles, generic platform abstraction, or Haxe semantic compatibility belongs
in `hxrt`, compiler lowering, or a rejected design.

## What

Every helper must be classified:

| Classification | Meaning |
| --- | --- |
| `permanent-native-facade` | Backing code for a real Rust resource/lifecycle/native wrapper that is expected to remain behind a typed facade unless a generic native-wrapper generator later replaces it. |
| `lowering-candidate` | Simple pure constructor/accessor/conversion or small wrapper that may graduate into compiler lowering once the representation is stable. |
| `experimental-scaffold` | Temporary helper accepted only with a Bead, explicit removal/graduation criteria, and review before it becomes product surface. |

Prefer compiler lowering when the operation is a pure, closed transformation from typed AST,
metadata, literals, or existing Rust primitives.

Use a native facade helper only when the operation owns or safely wraps a real Rust type/resource and
Haxe or the current compiler cannot express the required Rust shape without raw snippets, dynamic
handles, layout assumptions, or noisy generated code.

Reject helper growth when it introduces:

- `hxrt` dependency or Haxe semantic runtime behavior
- `Dynamic`, `Any`, type-erased registries, broad handles, or reflection-like dispatch
- portable `sys.*` compatibility semantics under `rust.*`
- generic platform abstraction that hides target behavior
- allocation-heavy adapters where direct Rust values are available
- catch-all `*_tools.rs` growth that collects unrelated operations

## How

For every new or expanded helper, update the closest docs and evidence:

- Haxe owner extern/facade
- helper classification
- why compiler lowering is insufficient today
- allowed imports/dependencies
- forbidden growth
- generated call-site evidence
- no-hxrt evidence
- rustfmt/cargo evidence, and clippy where feasible
- policy or fixture coverage that proves the intended output shape

Forbidden-token checks must avoid false failures on explanatory comments. Prefer checking Cargo
dependencies, generated call expressions, helper imports, and emitted Rust code with comments
stripped or otherwise scoped to semantically relevant locations.

## Current Inventory

| Helper | Haxe owner | Classification | Why not compiler lowering today | Forbidden growth |
| --- | --- | --- | --- | --- |
| `native_socket_addr_tools.rs` | `rust.net.SocketAddr` | `lowering-candidate` | The current compiler cannot declare the wrapper field and crate-private conversions used by TCP/UDP helpers without a helper or a new native-wrapper generator. `localhost(...)` and `port()` are simple enough to revisit. | DNS, parsing, arbitrary host strings, generic address registries, portable `sys.net` semantics. |
| `native_tcp_tools.rs` | `rust.net.NativeTcp`, `TcpListener`, `TcpStream` | `permanent-native-facade` | Owns direct `std::net::TcpListener` / `TcpStream` handles and blocking read/write/shutdown lifecycle. | TLS, async runtime, portable socket compatibility, broad stream adapters. |
| `native_udp_tools.rs` | `rust.net.NativeUdp`, `UdpSocket` | `permanent-native-facade` | Owns direct `std::net::UdpSocket` handles and datagram send/receive behavior. | DNS, async runtime, portable socket compatibility, generic datagram registry. |
| `native_socket_error_tools.rs` | `rust.net.SocketError` | `permanent-native-facade` | Provides typed error categories shared by TCP/UDP facade helpers without exceptions or `Dynamic`. | Broad error hierarchy, portable exception behavior, type-erased payloads. |
| `native_process_tools.rs` | `rust.process.*` | `permanent-native-facade` | Owns process lifecycle, child wait/kill behavior, stdout/stderr ownership, and `stdin.take()` pipe-close semantics. | Shell/runtime process abstraction, portable `sys.io.Process` semantics, reusable stream runtime. |
| `native_file_tools.rs` | `rust.fs.NativeFiles` | `permanent-native-facade` | Owns direct file/path operations where the metal facade intentionally avoids portable `sys.io` stream semantics. | Portable file handles, Haxe `Input`/`Output` compatibility, platform abstraction beyond the facade contract. |
| `vec_tools.rs`, `hash_map_tools*.rs`, `slice_tools.rs`, `mut_slice_tools.rs`, `array_borrow_tools.rs`, `iter_tools.rs` | `rust.*` collections and borrow helpers | mixed: mostly `lowering-candidate` plus borrow-facade helpers | Some helper methods expose borrow-shaped or native collection operations before the compiler has a generic wrapper/lowering facility for every pattern. | Broad collection runtime, clone-heavy adapters normalized as API, unrelated helper accumulation. |
| `path_buf_tools*.rs`, `os_string_tools*.rs`, `duration_tools.rs`, `instant_tools.rs`, `rust_string_tools*.rs`, `clone_tools.rs`, `map_storage_tools*.rs` | `rust.*` value/tool facades and selected std internals | mixed; audit required before broad expansion | These helpers predate the taxonomy. Treat expansion as requiring fresh classification and output-shape evidence. | Catch-all tools growth, generic conversion/runtime layers, portable semantic emulation under `rust.*`. |

The inventory is intentionally a starting classification. New work should refine entries when it
touches a helper, rather than expanding unclassified behavior.

## Follow-Up Beads

| Bead | Scope |
| --- | --- |
| `haxe.rust-oo3.93` | Turn this inventory into a machine-checkable helper manifest and CI growth guard. |
| `haxe.rust-oo3.94` | Spike compiler-generated native wrapper support for simple typed Rust value wrappers. |
| `haxe.rust-oo3.95` | Revisit `rust.net.SocketAddr` as a lowering candidate once wrapper/lowering rules are stable. |
| `haxe.rust-oo3.96` | Audit resource/lifecycle helpers such as process, file, TCP, and UDP facades under this taxonomy. |
