use hxrt::array::Array;
use hxrt::cell::HxRef;
use hxrt::net::SocketHandle;

pub fn new_tcp() -> HxRef<SocketHandle> {
    hxrt::net::socket_new_tcp()
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

pub fn select_groups(
    read: &Array<HxRef<SocketHandle>>,
    write: &Array<HxRef<SocketHandle>>,
    others: &Array<HxRef<SocketHandle>>,
    timeout: Option<f64>,
) -> Array<Array<i32>> {
    let (ri, wi, oi) = hxrt::net::socket_select(read.to_vec(), write.to_vec(), others.to_vec(), timeout);
    Array::<Array<i32>>::from_vec(vec![
        Array::<i32>::from_vec(ri),
        Array::<i32>::from_vec(wi),
        Array::<i32>::from_vec(oi),
    ])
}
