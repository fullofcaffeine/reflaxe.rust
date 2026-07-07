# Metal Native Net

Rust-native networking example for the `metal + rust_no_hxrt` contract.

## What This Shows

- typed `rust.net.SocketAddr` loopback addresses
- blocking TCP UTF-8 exchange through `NativeTcp`, `TcpListener`, and `TcpStream`
- blocking UDP byte datagrams through `NativeUdp` and `UdpSocket`
- typed `Detailed` error-returning methods instead of Haxe exceptions
- no app-side raw Rust and no `hxrt` dependency

## Run

```bash
cd examples/metal_native_net
npx haxe compile.hxml
(cd out && cargo run -q)
```

The run is intentionally quiet. Any failed contract check exits non-zero.

## Why No Portable Variant

This example demonstrates Rust-native `rust.net.*` facades. Portable socket behavior remains covered
by `examples/sys_net_loopback`, which uses `sys.net.*` and the portable runtime-backed contract.
