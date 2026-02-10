use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;

use rustls::pki_types::{CertificateDer, ServerName};
use rustls::{ClientConfig, ClientConnection, RootCertStore};

#[test]
fn tls_server_handshake_and_io() {
    // Generate a one-shot self-signed certificate and feed it into the hxrt TLS server.
    let rcgen::CertifiedKey { cert, key_pair } =
        rcgen::generate_simple_self_signed(vec!["localhost".to_string()]).unwrap();
    let cert_der: Vec<u8> = cert.der().as_ref().to_vec();
    let key_der: Vec<u8> = key_pair.serialize_der(); // PKCS#8 private key DER

    let server_cert = hxrt::ssl::cert_from_chain_der(vec![cert_der.clone()]);
    let server_key = hxrt::ssl::key_read_der(&key_der, false);

    // Bind a TCP listener via hxrt and accept a single connection.
    let listener = hxrt::net::socket_new_tcp();
    listener
        .borrow_mut()
        .bind(hxrt::net::host_resolve("127.0.0.1"), 0);
    listener.borrow_mut().listen(1);
    let (_, port) = listener.borrow().host();

    let server = std::thread::spawn(move || {
        let conn = listener.borrow_mut().accept();
        conn.borrow_mut()
            .tls_handshake_server(server_cert.clone(), server_key.clone());

        let mut buf = [0u8; 4];
        let n = conn.borrow_mut().read_stream(&mut buf);
        assert_eq!(n, 4);
        assert_eq!(&buf, b"ping");

        assert_eq!(conn.borrow_mut().write_stream(b"pong"), 4);
    });

    // Client side: use rustls with the self-signed cert as a trust root.
    let mut roots = RootCertStore::empty();
    roots.add(CertificateDer::from(cert_der)).unwrap();

    let config: Arc<ClientConfig> = Arc::new(
        ClientConfig::builder()
            .with_root_certificates(roots)
            .with_no_client_auth(),
    );
    let name = ServerName::try_from("localhost").unwrap();
    let conn = ClientConnection::new(config, name).unwrap();

    let stream = TcpStream::connect(("127.0.0.1", port as u16)).unwrap();
    let mut tls = rustls::StreamOwned::new(conn, stream);

    tls.write_all(b"ping").unwrap();
    tls.flush().unwrap();

    let mut out = [0u8; 4];
    tls.read_exact(&mut out).unwrap();
    assert_eq!(&out, b"pong");

    server.join().unwrap();
}
