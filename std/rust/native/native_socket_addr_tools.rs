/// `native_socket_addr_tools`
///
/// Typed helper module backing `rust.net.SocketAddr`.
///
/// The first address slice intentionally models loopback `std::net::SocketAddr` values only. That
/// keeps the metal no-hxrt fixtures deterministic while giving TCP/UDP facades a reusable typed
/// address value instead of more localhost-port-only entry points.
///
/// Classification: lowering-candidate.
///
/// Why this helper exists today:
/// - Haxe externs can name the public typed surface, but they cannot declare this private wrapper
///   field plus crate-private conversions into the TCP/UDP helper modules.
/// - Keeping those conversions here avoids app-side raw Rust and avoids assuming Rust's address
///   layout from Haxe.
///
/// What this helper must not become:
/// - DNS or arbitrary host parsing.
/// - Portable `sys.net` compatibility.
/// - A generic address registry, runtime handle, or platform abstraction layer.
use std::net::{Ipv4Addr, SocketAddr as StdSocketAddr, SocketAddrV4};

use crate::native_socket_error_tools::SocketError;

#[derive(Clone, Copy, Debug)]
pub struct SocketAddr {
    addr: StdSocketAddr,
}

fn port_to_u16(port: i32) -> Result<u16, String> {
    u16::try_from(port).map_err(|_| format!("socket port out of range: {}", port))
}

fn port_to_u16_detailed(port: i32) -> Result<u16, SocketError> {
    u16::try_from(port)
        .map_err(|_| SocketError::invalid_input(format!("socket port out of range: {}", port)))
}

#[allow(non_snake_case)]
impl SocketAddr {
    pub fn localhost(port: i32) -> Result<SocketAddr, String> {
        let port = port_to_u16(port)?;
        Ok(SocketAddr::from_std(
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, port).into(),
        ))
    }

    pub fn localhostDetailed(port: i32) -> Result<SocketAddr, SocketError> {
        let port = port_to_u16_detailed(port)?;
        Ok(SocketAddr::from_std(
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, port).into(),
        ))
    }

    pub fn port(&self) -> i32 {
        i32::from(self.addr.port())
    }

    pub(crate) fn from_std(addr: StdSocketAddr) -> SocketAddr {
        SocketAddr { addr }
    }

    pub(crate) fn as_std(&self) -> StdSocketAddr {
        self.addr
    }
}
