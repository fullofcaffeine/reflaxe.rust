use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::Arc;

use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use rustls::{ServerConfig, ServerConnection};

#[test]
fn tls_client_handshake_and_io() {
    // Spin up a one-shot TLS echo server with a self-signed cert.
    let rcgen::CertifiedKey { cert, key_pair } =
        rcgen::generate_simple_self_signed(vec!["localhost".to_string()]).unwrap();
    let cert_der: Vec<u8> = cert.der().as_ref().to_vec();
    let key_der: Vec<u8> = key_pair.serialize_der();

    let config: Arc<ServerConfig> = Arc::new(
        ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(
                vec![CertificateDer::from(cert_der)],
                PrivateKeyDer::from(PrivatePkcs8KeyDer::from(key_der)),
            )
            .unwrap(),
    );

    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();

    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let conn = ServerConnection::new(config).unwrap();
        let mut tls = rustls::StreamOwned::new(conn, stream);

        let mut buf = [0u8; 4];
        tls.read_exact(&mut buf).unwrap();
        assert_eq!(&buf, b"ping");

        tls.write_all(b"pong").unwrap();
        tls.flush().unwrap();
    });

    // Client side: use the hxrt socket handle and upgrade to TLS in-place.
    let handle = hxrt::net::socket_new_tcp();
    handle
        .borrow_mut()
        .connect(hxrt::net::host_resolve("127.0.0.1"), addr.port() as i32);

    handle.borrow_mut().tls_handshake_client(
        Some("localhost".to_string()),
        Some(false), // self-signed: disable verification for this test
        None,
    );

    assert_eq!(handle.borrow_mut().write_stream(b"ping"), 4);

    let mut out = [0u8; 4];
    let n = handle.borrow_mut().read_stream(&mut out);
    assert_eq!(n, 4);
    assert_eq!(&out, b"pong");

    server.join().unwrap();
}
