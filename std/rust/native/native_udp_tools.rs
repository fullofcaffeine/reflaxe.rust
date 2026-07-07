/// `native_udp_tools`
///
/// Typed helper module backing `rust.net.NativeUdp` and `UdpSocket`.
///
/// This module intentionally uses direct `std::net` APIs and owned `Result<_, String>` values so
/// the metal no-hxrt fixture can prove Rust-native blocking UDP datagram behavior without depending
/// on portable `sys.net` runtime handles, Haxe stream wrappers, async runtimes, DNS, or TLS setup.
use std::net::UdpSocket as StdUdpSocket;

#[derive(Debug)]
pub struct NativeUdp;

#[derive(Debug)]
pub struct UdpSocket {
    socket: StdUdpSocket,
}

fn port_to_u16(port: i32) -> Result<u16, String> {
    u16::try_from(port).map_err(|_| format!("UDP port out of range: {}", port))
}

fn positive_len_to_usize(value: i32, label: &str) -> Result<usize, String> {
    if value <= 0 {
        return Err(format!("{} must be positive: {}", label, value));
    }
    usize::try_from(value).map_err(|_| format!("{} out of range: {}", label, value))
}

#[allow(non_snake_case)]
impl NativeUdp {
    pub fn bindLocalhost(port: i32) -> Result<UdpSocket, String> {
        let port = port_to_u16(port)?;
        StdUdpSocket::bind(("127.0.0.1", port))
            .map(|socket| UdpSocket { socket })
            .map_err(|err| err.to_string())
    }
}

#[allow(non_snake_case)]
impl UdpSocket {
    pub fn localPort(&self) -> Result<i32, String> {
        self.socket
            .local_addr()
            .map(|addr| i32::from(addr.port()))
            .map_err(|err| err.to_string())
    }

    pub fn sendUtf8ToLocalhost(&self, payload: String, port: i32) -> Result<i32, String> {
        let port = port_to_u16(port)?;
        self.socket
            .send_to(payload.as_bytes(), ("127.0.0.1", port))
            .and_then(|sent| {
                i32::try_from(sent).map_err(|_| {
                    std::io::Error::new(std::io::ErrorKind::Other, "UDP byte count overflow")
                })
            })
            .map_err(|err| err.to_string())
    }

    pub fn recvUtf8(&self, max_bytes: i32) -> Result<String, String> {
        let max_bytes = positive_len_to_usize(max_bytes, "UDP receive buffer size")?;
        let mut buffer = vec![0_u8; max_bytes];
        let (read, _addr) = self
            .socket
            .recv_from(&mut buffer)
            .map_err(|err| err.to_string())?;
        buffer.truncate(read);
        String::from_utf8(buffer).map_err(|err| err.to_string())
    }
}
