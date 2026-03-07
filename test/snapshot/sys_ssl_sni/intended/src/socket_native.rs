use hxrt::array::Array;
use hxrt::bytes::{self, Bytes};
use hxrt::cell::{HxDynRef, HxRc, HxRef};
use hxrt::net::SocketHandle;
use hxrt::ssl::{Certificate, Key};

pub fn new_tcp() -> HxRef<SocketHandle> {
    hxrt::net::socket_new_tcp()
}

pub fn new_udp() -> HxRef<SocketHandle> {
    hxrt::net::socket_new_udp()
}

pub fn host_resolve(name: &str) -> i32 {
    hxrt::net::host_resolve(name)
}

pub fn host_to_string(ip: i32) -> String {
    hxrt::net::host_to_string(ip)
}

pub fn host_reverse(ip: i32) -> String {
    hxrt::net::host_reverse(ip)
}

pub fn host_local() -> String {
    hxrt::net::host_local()
}

pub fn close(handle: &HxRef<SocketHandle>) {
    handle.borrow_mut().close();
}

pub fn connect(handle: &HxRef<SocketHandle>, host: i32, port: i32) {
    handle.borrow_mut().connect(host, port);
}

pub fn listen(handle: &HxRef<SocketHandle>, connections: i32) {
    handle.borrow_mut().listen(connections);
}

pub fn shutdown(handle: &HxRef<SocketHandle>, read: bool, write: bool) {
    handle.borrow_mut().shutdown(read, write);
}

pub fn bind(handle: &HxRef<SocketHandle>, host: i32, port: i32) {
    handle.borrow_mut().bind(host, port);
}

pub fn accept(handle: &HxRef<SocketHandle>) -> HxRef<SocketHandle> {
    handle.borrow_mut().accept()
}

pub fn peer_ip(handle: &HxRef<SocketHandle>) -> i32 {
    let (ip, _) = handle.borrow().peer();
    ip
}

pub fn peer_port(handle: &HxRef<SocketHandle>) -> i32 {
    let (_, port) = handle.borrow().peer();
    port
}

pub fn host_ip(handle: &HxRef<SocketHandle>) -> i32 {
    let (ip, _) = handle.borrow().host();
    ip
}

pub fn host_port(handle: &HxRef<SocketHandle>) -> i32 {
    let (_, port) = handle.borrow().host();
    port
}

pub fn set_timeout(handle: &HxRef<SocketHandle>, timeout: f64) {
    handle.borrow_mut().set_timeout(timeout);
}

pub fn wait_for_read(handle: &HxRef<SocketHandle>) {
    let _ = hxrt::net::socket_select(vec![handle.clone()], vec![], vec![], Some(-1.0));
}

pub fn set_blocking(handle: &HxRef<SocketHandle>, blocking: bool) {
    handle.borrow_mut().set_blocking(blocking);
}

pub fn set_fast_send(handle: &HxRef<SocketHandle>, fast_send: bool) {
    handle.borrow_mut().set_fast_send(fast_send);
}

pub fn tls_handshake_client<S>(
    handle: &HxRef<SocketHandle>,
    hostname: S,
    verify_cert: bool,
    ca: HxRef<Certificate>,
) where
    S: Into<hxrt::string::HxString>,
{
    let ca_opt = if ca.is_null() { None } else { Some(ca) };
    let hostname = hostname.into();
    let hostname_opt = hostname.as_deref().map(str::to_string);
    handle
        .borrow_mut()
        .tls_handshake_client(hostname_opt, Some(verify_cert), ca_opt);
}

pub fn tls_handshake_server(
    handle: &HxRef<SocketHandle>,
    cert: &HxRef<Certificate>,
    key: &HxRef<Key>,
) {
    handle
        .borrow_mut()
        .tls_handshake_server(cert.clone(), key.clone());
}

pub fn tls_handshake_server_sni<S>(
    handle: &HxRef<SocketHandle>,
    default_cert: &HxRef<Certificate>,
    default_key: &HxRef<Key>,
    matchers: Array<crate::HxDynRef<dyn Fn(S) -> bool + Send + Sync>>,
    certs: Array<HxRef<Certificate>>,
    keys: Array<HxRef<Key>>,
) where
    S: From<String> + Send + Sync + 'static,
{
    let matcher_vec = matchers.to_vec();
    let cert_vec = certs.to_vec();
    let key_vec = keys.to_vec();
    let mut entries: Vec<hxrt::net::TlsSniEntry> = Vec::new();
    let len = matcher_vec.len().min(cert_vec.len()).min(key_vec.len());

    for idx in 0..len {
        let matcher = matcher_vec[idx].clone();
        let cert = cert_vec[idx].clone();
        let key = key_vec[idx].clone();
        if matcher.is_null() || cert.is_null() || key.is_null() {
            continue;
        }

        let adapted_matcher: HxDynRef<dyn Fn(String) -> bool + Send + Sync> = {
            let matcher = matcher.clone();
            let rc: HxRc<dyn Fn(String) -> bool + Send + Sync> =
                HxRc::new(move |server_name: String| {
                    let name_for_haxe: S = S::from(server_name);
                    matcher(name_for_haxe)
                });
            HxDynRef::new(rc)
        };

        entries.push(hxrt::net::TlsSniEntry {
            matcher: adapted_matcher,
            cert,
            key,
        });
    }

    handle.borrow_mut().tls_handshake_server_sni(
        default_cert.clone(),
        default_key.clone(),
        entries,
    );
}

pub fn tls_peer_certificate(handle: &HxRef<SocketHandle>) -> HxRef<Certificate> {
    handle.borrow().tls_peer_certificate()
}

pub fn write_bytes(
    handle: &HxRef<SocketHandle>,
    bytes_ref: &HxRef<Bytes>,
    pos: i32,
    len: i32,
) -> i32 {
    let bytes_binding = bytes_ref.borrow();
    let data = bytes_binding.as_slice();
    let start = pos as usize;
    let end = (pos + len) as usize;
    handle.borrow_mut().write_stream(&data[start..end]) as i32
}

pub fn read_bytes(
    handle: &HxRef<SocketHandle>,
    bytes_ref: &HxRef<Bytes>,
    pos: i32,
    len: i32,
) -> i32 {
    let mut tmp = vec![0u8; len as usize];
    let n = handle.borrow_mut().read_stream(tmp.as_mut_slice());
    if n == -1 {
        return 0;
    }

    bytes::write_from_slice(bytes_ref, pos, &tmp[0..(n as usize)]);
    n
}

pub fn udp_set_broadcast(handle: &HxRef<SocketHandle>, enabled: bool) {
    handle.borrow_mut().udp_set_broadcast(enabled);
}

pub fn udp_send_to(
    handle: &HxRef<SocketHandle>,
    bytes_ref: &HxRef<Bytes>,
    pos: i32,
    len: i32,
    host: i32,
    port: i32,
) -> i32 {
    let bytes_binding = bytes_ref.borrow();
    let data = bytes_binding.as_slice();
    let start = pos as usize;
    let end = (pos + len) as usize;
    handle
        .borrow_mut()
        .udp_send_to(&data[start..end], host, port)
}

pub fn udp_read_from(
    handle: &HxRef<SocketHandle>,
    bytes_ref: &HxRef<Bytes>,
    pos: i32,
    len: i32,
) -> Array<i32> {
    let mut tmp = vec![0u8; len as usize];
    let (n, ip, port) = handle.borrow_mut().udp_read_from(tmp.as_mut_slice());
    if n == -1 {
        return Array::<i32>::from_vec(vec![0i32, 0i32, 0i32]);
    }

    bytes::write_from_slice(bytes_ref, pos, &tmp[0..(n as usize)]);
    Array::<i32>::from_vec(vec![n, ip, port])
}

pub fn select_groups(
    read: &Array<HxRef<SocketHandle>>,
    write: &Array<HxRef<SocketHandle>>,
    others: &Array<HxRef<SocketHandle>>,
    timeout: Option<f64>,
) -> Array<Array<i32>> {
    let (ri, wi, oi) =
        hxrt::net::socket_select(read.to_vec(), write.to_vec(), others.to_vec(), timeout);
    Array::<Array<i32>>::from_vec(vec![
        Array::<i32>::from_vec(ri),
        Array::<i32>::from_vec(wi),
        Array::<i32>::from_vec(oi),
    ])
}
