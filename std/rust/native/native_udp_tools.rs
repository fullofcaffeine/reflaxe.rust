/// `native_udp_tools`
///
/// Typed helper module backing `rust.net.NativeUdp` and `UdpSocket`.
///
/// This module intentionally uses direct `std::net` APIs and owned `Result<_, String>` values so
/// the metal no-hxrt fixtures can prove Rust-native blocking UDP datagram behavior without
/// depending on portable `sys.net` runtime handles, Haxe stream wrappers, `haxe.io.Bytes`, async
/// runtimes, DNS, or TLS setup. Byte datagram helpers validate Haxe `Int` values before converting
/// them into Rust `u8` buffers.
use std::net::UdpSocket as StdUdpSocket;

use crate::native_socket_addr_tools::SocketAddr;
use crate::native_socket_error_tools::SocketError;

#[derive(Debug)]
pub struct NativeUdp;

#[derive(Debug)]
pub struct UdpSocket {
    socket: StdUdpSocket,
}

fn port_to_u16(port: i32) -> Result<u16, String> {
    u16::try_from(port).map_err(|_| format!("UDP port out of range: {}", port))
}

fn port_to_u16_detailed(port: i32) -> Result<u16, SocketError> {
    u16::try_from(port)
        .map_err(|_| SocketError::invalid_input(format!("UDP port out of range: {}", port)))
}

fn positive_len_to_usize(value: i32, label: &str) -> Result<usize, String> {
    if value <= 0 {
        return Err(format!("{} must be positive: {}", label, value));
    }
    usize::try_from(value).map_err(|_| format!("{} out of range: {}", label, value))
}

fn positive_len_to_usize_detailed(value: i32, label: &str) -> Result<usize, SocketError> {
    if value <= 0 {
        return Err(SocketError::invalid_input(format!(
            "{} must be positive: {}",
            label, value
        )));
    }
    usize::try_from(value)
        .map_err(|_| SocketError::invalid_input(format!("{} out of range: {}", label, value)))
}

fn byte_count_to_i32(sent: usize) -> Result<i32, std::io::Error> {
    i32::try_from(sent).map_err(|_| std::io::Error::other("UDP byte count overflow"))
}

fn bytes_to_u8_vec(payload: Vec<i32>) -> Result<Vec<u8>, String> {
    payload
        .into_iter()
        .enumerate()
        .map(|(index, byte)| {
            u8::try_from(byte)
                .map_err(|_| format!("UDP byte at index {} out of range: {}", index, byte))
        })
        .collect()
}

fn bytes_to_u8_vec_detailed(payload: Vec<i32>) -> Result<Vec<u8>, SocketError> {
    bytes_to_u8_vec(payload).map_err(SocketError::invalid_input)
}

fn u8_vec_to_i32_vec(payload: Vec<u8>) -> Vec<i32> {
    payload.into_iter().map(i32::from).collect()
}

#[allow(non_snake_case)]
impl NativeUdp {
    pub fn bind(addr: SocketAddr) -> Result<UdpSocket, String> {
        StdUdpSocket::bind(addr.as_std())
            .map(|socket| UdpSocket { socket })
            .map_err(|err| err.to_string())
    }

    pub fn bindDetailed(addr: SocketAddr) -> Result<UdpSocket, SocketError> {
        StdUdpSocket::bind(addr.as_std())
            .map(|socket| UdpSocket { socket })
            .map_err(SocketError::io)
    }

    pub fn bindLocalhost(port: i32) -> Result<UdpSocket, String> {
        let port = port_to_u16(port)?;
        StdUdpSocket::bind(("127.0.0.1", port))
            .map(|socket| UdpSocket { socket })
            .map_err(|err| err.to_string())
    }

    pub fn bindLocalhostDetailed(port: i32) -> Result<UdpSocket, SocketError> {
        let port = port_to_u16_detailed(port)?;
        StdUdpSocket::bind(("127.0.0.1", port))
            .map(|socket| UdpSocket { socket })
            .map_err(SocketError::io)
    }
}

#[allow(non_snake_case)]
impl UdpSocket {
    pub fn localAddr(&self) -> Result<SocketAddr, String> {
        self.socket
            .local_addr()
            .map(SocketAddr::from_std)
            .map_err(|err| err.to_string())
    }

    pub fn localAddrDetailed(&self) -> Result<SocketAddr, SocketError> {
        self.socket
            .local_addr()
            .map(SocketAddr::from_std)
            .map_err(SocketError::io)
    }

    pub fn localPort(&self) -> Result<i32, String> {
        self.socket
            .local_addr()
            .map(|addr| i32::from(addr.port()))
            .map_err(|err| err.to_string())
    }

    pub fn localPortDetailed(&self) -> Result<i32, SocketError> {
        self.socket
            .local_addr()
            .map(|addr| i32::from(addr.port()))
            .map_err(SocketError::io)
    }

    pub fn sendUtf8To(&self, payload: String, addr: SocketAddr) -> Result<i32, String> {
        self.socket
            .send_to(payload.as_bytes(), addr.as_std())
            .and_then(byte_count_to_i32)
            .map_err(|err| err.to_string())
    }

    pub fn sendUtf8ToDetailed(
        &self,
        payload: String,
        addr: SocketAddr,
    ) -> Result<i32, SocketError> {
        self.socket
            .send_to(payload.as_bytes(), addr.as_std())
            .and_then(byte_count_to_i32)
            .map_err(SocketError::io)
    }

    pub fn sendUtf8ToLocalhost(&self, payload: String, port: i32) -> Result<i32, String> {
        let port = port_to_u16(port)?;
        self.socket
            .send_to(payload.as_bytes(), ("127.0.0.1", port))
            .and_then(byte_count_to_i32)
            .map_err(|err| err.to_string())
    }

    pub fn sendUtf8ToLocalhostDetailed(
        &self,
        payload: String,
        port: i32,
    ) -> Result<i32, SocketError> {
        let port = port_to_u16_detailed(port)?;
        self.socket
            .send_to(payload.as_bytes(), ("127.0.0.1", port))
            .and_then(byte_count_to_i32)
            .map_err(SocketError::io)
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

    pub fn recvUtf8Detailed(&self, max_bytes: i32) -> Result<String, SocketError> {
        let max_bytes = positive_len_to_usize_detailed(max_bytes, "UDP receive buffer size")?;
        let mut buffer = vec![0_u8; max_bytes];
        let (read, _addr) = self.socket.recv_from(&mut buffer).map_err(SocketError::io)?;
        buffer.truncate(read);
        String::from_utf8(buffer).map_err(SocketError::utf8)
    }

    pub fn sendBytesTo(&self, payload: Vec<i32>, addr: SocketAddr) -> Result<i32, String> {
        let bytes = bytes_to_u8_vec(payload)?;
        self.socket
            .send_to(&bytes, addr.as_std())
            .and_then(byte_count_to_i32)
            .map_err(|err| err.to_string())
    }

    pub fn sendBytesToDetailed(
        &self,
        payload: Vec<i32>,
        addr: SocketAddr,
    ) -> Result<i32, SocketError> {
        let bytes = bytes_to_u8_vec_detailed(payload)?;
        self.socket
            .send_to(&bytes, addr.as_std())
            .and_then(byte_count_to_i32)
            .map_err(SocketError::io)
    }

    pub fn sendBytesToLocalhost(&self, payload: Vec<i32>, port: i32) -> Result<i32, String> {
        let port = port_to_u16(port)?;
        let bytes = bytes_to_u8_vec(payload)?;
        self.socket
            .send_to(&bytes, ("127.0.0.1", port))
            .and_then(byte_count_to_i32)
            .map_err(|err| err.to_string())
    }

    pub fn sendBytesToLocalhostDetailed(
        &self,
        payload: Vec<i32>,
        port: i32,
    ) -> Result<i32, SocketError> {
        let port = port_to_u16_detailed(port)?;
        let bytes = bytes_to_u8_vec_detailed(payload)?;
        self.socket
            .send_to(&bytes, ("127.0.0.1", port))
            .and_then(byte_count_to_i32)
            .map_err(SocketError::io)
    }

    pub fn recvBytes(&self, max_bytes: i32) -> Result<Vec<i32>, String> {
        let max_bytes = positive_len_to_usize(max_bytes, "UDP receive buffer size")?;
        let mut buffer = vec![0_u8; max_bytes];
        let (read, _addr) = self
            .socket
            .recv_from(&mut buffer)
            .map_err(|err| err.to_string())?;
        buffer.truncate(read);
        Ok(u8_vec_to_i32_vec(buffer))
    }

    pub fn recvBytesDetailed(&self, max_bytes: i32) -> Result<Vec<i32>, SocketError> {
        let max_bytes = positive_len_to_usize_detailed(max_bytes, "UDP receive buffer size")?;
        let mut buffer = vec![0_u8; max_bytes];
        let (read, _addr) = self.socket.recv_from(&mut buffer).map_err(SocketError::io)?;
        buffer.truncate(read);
        Ok(u8_vec_to_i32_vec(buffer))
    }
}
