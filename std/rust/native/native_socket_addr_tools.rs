/// `native_socket_addr_tools`
///
/// Typed helper module backing `rust.net.SocketAddr`.
///
/// The first address slice intentionally models typed `std::net::SocketAddr` values that are
/// constructed by compiler lowering or returned from TCP/UDP resource helpers. That keeps the metal
/// no-hxrt fixtures deterministic while giving TCP/UDP facades a reusable typed address value
/// instead of more localhost-port-only entry points.
///
/// Classification: permanent-native-facade.
///
/// Why this helper exists today:
/// - Haxe externs can name the public typed surface, but they cannot declare this private wrapper
///   field plus crate-private conversions into the TCP/UDP helper modules.
/// - `SocketAddr.localhost*` and `SocketAddr.port()` are compiler-lowered; this helper is retained
///   only for representation privacy and resource-helper handoff.
/// - Keeping those conversions here avoids app-side raw Rust and avoids assuming Rust's address
///   layout from Haxe.
///
/// What this helper must not become:
/// - DNS or arbitrary host parsing.
/// - Portable `sys.net` compatibility.
/// - A generic address registry, runtime handle, or platform abstraction layer.
use std::net::SocketAddr as StdSocketAddr;

#[derive(Clone, Copy, Debug)]
pub struct SocketAddr {
    addr: StdSocketAddr,
}

impl SocketAddr {
    pub(crate) fn from_std(addr: StdSocketAddr) -> SocketAddr {
        SocketAddr { addr }
    }

    pub(crate) fn as_std(&self) -> StdSocketAddr {
        self.addr
    }
}
