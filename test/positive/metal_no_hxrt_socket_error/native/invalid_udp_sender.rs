use std::net::UdpSocket;

pub struct InvalidUdpSender;

fn port_to_u16(port: i32) -> Result<u16, String> {
    u16::try_from(port).map_err(|_| format!("UDP port out of range: {}", port))
}

#[allow(non_snake_case)]
impl InvalidUdpSender {
    pub fn sendInvalidUtf8ToLocalhost(port: i32) -> Result<i32, String> {
        let port = port_to_u16(port)?;
        let socket = UdpSocket::bind(("127.0.0.1", 0)).map_err(|err| err.to_string())?;
        socket
            .send_to(&[0xff, 0xfe], ("127.0.0.1", port))
            .and_then(|sent| {
                i32::try_from(sent).map_err(|_| {
                    std::io::Error::new(std::io::ErrorKind::Other, "UDP byte count overflow")
                })
            })
            .map_err(|err| err.to_string())
    }
}
