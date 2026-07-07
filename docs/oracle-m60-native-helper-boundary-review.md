# Oracle Review Prompt: M60 Native Helper Boundary

Paste this into GPT-5.5 Pro.

## Context

You are reviewing `reflaxe.rust`, a Haxe 4.3.7 -> Rust compiler backend built through Reflaxe.

Strategic goal from `AGENTS.md`:

- Make `reflaxe.rust` the best way to write production Rust outside of writing raw Rust directly.
- Generated Rust quality is a first-class product requirement.
- `hxrt` should remain lightweight and used only where Haxe semantics require runtime support.
- Stdlib lowering should prefer direct, idiomatic, efficient Rust or the thinnest typed primitive.
- Do not normalize broad runtime layers, dynamic handles, or allocation-heavy adapters.
- If typeful Haxe produces poor/noisy/runtime-heavy Rust, treat it as a generic compiler/runtime gap.

Current active Bead:

- `haxe.rust-oo3.92` / M60 typed socket address facade + examples audit.
- It was escalated from `thinking:high` to `thinking:xhigh` because we are unsure whether the current
  `std/rust/native/*.rs` helper pattern is compatible with the compiler vision or risks becoming a
  second runtime beside `hxrt`.

Recent trajectory:

- M55 added blocking localhost TCP over direct `std::net`.
- M56 added blocking localhost UDP over direct `std::net`.
- M57 added typed `SocketError`.
- M58 added UDP byte datagrams as `rust.Vec<Int>` -> `Vec<u8>` validation without `haxe.io.Bytes`
  or `hxrt`.
- M59 added TCP byte streams under the same no-hxrt byte-validation contract.
- M60 started as a narrow typed address value so TCP/UDP helpers can accept/carry loopback addresses
  rather than only `localhost(port)` helper methods.

The user challenged whether adding `std/rust/native/native_socket_addr_tools.rs` is an anti-pattern:

> hxrt is supposed to be the runtime; if we are avoiding hxrt, should we avoid adding additional
> Rust runtime code? Can this be generated at compile time instead?

I agree this needs second-pass architecture review before M60 closes.

## Current Work-In-Progress Diff Shape

New fixture:

- `test/positive/metal_no_hxrt_socket_addr/compile.hxml`
- `test/positive/metal_no_hxrt_socket_addr/Main.hx`

The fixture proves:

- `SocketAddr.localhostDetailed(70000)` returns a typed invalid-input `SocketError`.
- `SocketAddr.localhostDetailed(0)` can bind TCP/UDP sockets to OS-assigned loopback ports.
- `TcpListener.localAddrDetailed()` returns a typed `SocketAddr`.
- `NativeTcp.connect(addr)` connects using that typed address.
- `UdpSocket.localAddrDetailed()` returns a typed `SocketAddr`.
- `UdpSocket.sendBytesToDetailed(payload, addr)` sends bytes using the typed address.
- The fixture compiles/runs with:
  - `-D reflaxe_rust_profile=metal`
  - `-D rust_no_hxrt`
  - no output, no `hxrt` dependency.

New Haxe extern:

- `std/rust/net/SocketAddr.hx`

Shape:

```haxe
@:native("crate::native_socket_addr_tools::SocketAddr")
@:rustExtraSrc("rust/native/native_socket_addr_tools.rs")
extern class SocketAddr {
  public static function localhost(port:Int):Result<SocketAddr, String>;
  public static function localhostDetailed(port:Int):Result<SocketAddr, SocketError>;
  public function port():Int;
}
```

New Rust helper:

- `std/rust/native/native_socket_addr_tools.rs`

Shape:

```rust
use std::net::{Ipv4Addr, SocketAddr as StdSocketAddr, SocketAddrV4};

use crate::native_socket_error_tools::SocketError;

#[derive(Clone, Copy, Debug)]
pub struct SocketAddr {
    addr: StdSocketAddr,
}

fn port_to_u16(port: i32) -> Result<u16, String> { ... }
fn port_to_u16_detailed(port: i32) -> Result<u16, SocketError> { ... }

impl SocketAddr {
    pub fn localhost(port: i32) -> Result<SocketAddr, String> {
        let port = port_to_u16(port)?;
        Ok(SocketAddr::from_std(SocketAddrV4::new(Ipv4Addr::LOCALHOST, port).into()))
    }

    pub fn localhostDetailed(port: i32) -> Result<SocketAddr, SocketError> {
        let port = port_to_u16_detailed(port)?;
        Ok(SocketAddr::from_std(SocketAddrV4::new(Ipv4Addr::LOCALHOST, port).into()))
    }

    pub fn port(&self) -> i32 {
        i32::from(self.addr.port())
    }

    pub(crate) fn from_std(addr: StdSocketAddr) -> SocketAddr { ... }
    pub(crate) fn as_std(&self) -> StdSocketAddr { ... }
}
```

Existing helpers updated:

- `std/rust/native/native_tcp_tools.rs`
  - imports `crate::native_socket_addr_tools::SocketAddr`
  - adds `NativeTcp.bind(addr)`, `bindDetailed(addr)`, `connect(addr)`, `connectDetailed(addr)`
  - adds `TcpListener.localAddr()` / `localAddrDetailed()`

- `std/rust/native/native_udp_tools.rs`
  - imports `crate::native_socket_addr_tools::SocketAddr`
  - adds `NativeUdp.bind(addr)` / `bindDetailed(addr)`
  - adds `UdpSocket.localAddr()` / `localAddrDetailed()`
  - adds `sendUtf8To(payload, addr)` / `sendUtf8ToDetailed(...)`
  - adds `sendBytesTo(payload, addr)` / `sendBytesToDetailed(...)`

Policy gate added:

- `scripts/ci/check-metal-policy.sh`
  - `run_socket_addr_output_shape_case`
  - rejects `hxrt`, `Dynamic`, `__rust__`, `ERaw`, `SocketHandle`, `socket_native`, `sys_net`,
    `haxe_io_bytes`
  - checks direct `std::net::{Ipv4Addr, SocketAddr, SocketAddrV4}` use
  - checks `StdTcpListener::bind(addr.as_std())`, `StdTcpStream::connect(addr.as_std())`,
    `StdUdpSocket::bind(addr.as_std())`, and `send_to(..., addr.as_std())`

Validation so far:

- Contract-first red bar: fixture initially failed with missing `rust.net.SocketAddr` and address
  methods.
- After implementation: `haxe compile.hxml && cd out && cargo build -q && cargo run -q` passed for
  `test/positive/metal_no_hxrt_socket_addr`.
- The full metal policy gate and full examples audit were not completed because the architectural
  question paused the work.

## Existing Pattern For Comparison

Several current Rust-native facades use `std/rust/native/*.rs`:

- `native_process_tools.rs` backs `rust.process.NativeCommands`, `CommandSpec`, `CommandError`,
  `CommandChild`.
- `native_tcp_tools.rs` backs `rust.net.NativeTcp`, `TcpListener`, `TcpStream`.
- `native_udp_tools.rs` backs `rust.net.NativeUdp`, `UdpSocket`.
- `native_socket_error_tools.rs` backs `rust.net.SocketError`.
- `vec_tools.rs`, `hash_map_tools.rs`, string/path/os helpers also exist.

Example where a helper seems clearly justified:

- `CommandChild.writeStdinAndClose(...)` owns `std::process::Child`, calls
  `self.child.stdin.take()`, writes to `ChildStdin`, and drops the pipe so the child sees EOF. This
  models Rust resource lifecycle/partial moves that Haxe cannot cleanly express without raw Rust or
  a dedicated compiler IR for native wrapper impls.

Example now under question:

- `SocketAddr.localhost(...)` may be simple enough for compiler-time lowering, or it may still be
  acceptable as a tiny typed extern island because Haxe cannot declare the Rust wrapper field and
  private conversions itself.

## Questions

Please answer with `APPROVE`, `APPROVE_WITH_CHANGES`, or `REJECT_AND_REDIRECT`.

1. Is the current `std/rust/native/*.rs` typed-helper pattern compatible with the compiler vision
   when `rust_no_hxrt` output remains free of `hxrt`, `Dynamic`, raw snippets, and portable handles?

2. Is `SocketAddr` specifically a justified tiny extern island, or should M60 be redirected toward
   compile-time lowering / compiler-generated wrapper code instead?

3. What rule should distinguish:
   - real extern islands / native facades,
   - compiler intrinsics or compile-time lowering,
   - unacceptable shadow-runtime/helper accretion?

4. Should `std/rust/native/*.rs` helpers be treated as temporary scaffolding by default, with a
   Beads follow-up to graduate stable/simple helpers into compiler lowering, or are some helpers
   acceptable permanent public native facade backing code?

5. For resource-lifecycle cases like `CommandChild`, is the handwritten helper still the right
   shape, or should the compiler grow a generic typed native-wrapper codegen facility?

6. What stricter directives should be added to `AGENTS.md` / `std/AGENTS.md` to prevent helper
   modules from becoming a second runtime?

7. What should happen to the current M60 WIP:
   - land with tighter docs/policy,
   - narrow it,
   - replace it with compile-time lowering,
   - split a new architecture Bead first,
   - or abandon M60 until the compiler has typed native-wrapper generation?

8. Are the output-shape gates described above sufficient evidence, or should the acceptance criteria
   require generated Rust inspection of `main.rs` call sites, rustfmt/cargo/clippy, no helper
   growth budget, or a helper-size/static-analysis guard?

## Desired Output

Please provide:

- verdict,
- top findings ordered by severity,
- answers to the questions,
- concrete changes before M60 closure,
- directives/policy text to add if needed,
- recommended follow-up Beads.
