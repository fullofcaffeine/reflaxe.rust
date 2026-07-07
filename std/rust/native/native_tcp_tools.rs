/// `native_tcp_tools`
///
/// Typed helper module backing `rust.net.NativeTcp`, `TcpListener`, and `TcpStream`.
///
/// This module intentionally uses direct `std::net` APIs and owned `Result<_, String>` values so
/// the metal no-hxrt fixture can prove Rust-native blocking TCP behavior without depending on
/// portable `sys.net` runtime handles, Haxe stream wrappers, async runtimes, or TLS setup.
use std::io::{Read, Write};
use std::net::{Shutdown, TcpListener as StdTcpListener, TcpStream as StdTcpStream};

#[derive(Debug)]
pub struct NativeTcp;

#[derive(Debug)]
pub struct TcpListener {
    listener: StdTcpListener,
}

#[derive(Debug)]
pub struct TcpStream {
    stream: StdTcpStream,
}

fn port_to_u16(port: i32) -> Result<u16, String> {
    u16::try_from(port).map_err(|_| format!("TCP port out of range: {}", port))
}

#[allow(non_snake_case)]
impl NativeTcp {
    pub fn bindLocalhost(port: i32) -> Result<TcpListener, String> {
        let port = port_to_u16(port)?;
        StdTcpListener::bind(("127.0.0.1", port))
            .map(|listener| TcpListener { listener })
            .map_err(|err| err.to_string())
    }

    pub fn connectLocalhost(port: i32) -> Result<TcpStream, String> {
        let port = port_to_u16(port)?;
        StdTcpStream::connect(("127.0.0.1", port))
            .map(|stream| TcpStream { stream })
            .map_err(|err| err.to_string())
    }
}

#[allow(non_snake_case)]
impl TcpListener {
    pub fn localPort(&self) -> Result<i32, String> {
        self.listener
            .local_addr()
            .map(|addr| i32::from(addr.port()))
            .map_err(|err| err.to_string())
    }

    pub fn accept(&self) -> Result<TcpStream, String> {
        self.listener
            .accept()
            .map(|(stream, _addr)| TcpStream { stream })
            .map_err(|err| err.to_string())
    }
}

#[allow(non_snake_case)]
impl TcpStream {
    pub fn writeUtf8AndShutdownWrite(&mut self, payload: String) -> Result<bool, String> {
        self.stream
            .write_all(payload.as_bytes())
            .and_then(|_| self.stream.shutdown(Shutdown::Write))
            .map(|_| true)
            .map_err(|err| err.to_string())
    }

    pub fn readToString(&mut self) -> Result<String, String> {
        let mut output = String::new();
        self.stream
            .read_to_string(&mut output)
            .map(|_| output)
            .map_err(|err| err.to_string())
    }
}
