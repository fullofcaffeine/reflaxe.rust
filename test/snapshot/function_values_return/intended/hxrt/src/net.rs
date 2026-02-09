use crate::cell::{HxCell, HxRc, HxRef};
use crate::{dynamic, exception, io};
use mio::{Events, Interest, Poll, Token};
use socket2::{Domain, Protocol, Socket, Type};
use std::io::{Read, Write};
use std::net::{
    IpAddr, Ipv4Addr, SocketAddr, SocketAddrV4, TcpListener, TcpStream, ToSocketAddrs, UdpSocket,
};
use std::time::Duration;

/// `hxrt::net`
///
/// Runtime support for a subset of `sys.net.*` on the Rust target.
///
/// Why
/// - `sys.net.Host` and `sys.net.Socket` are core sys APIs for network-capable Haxe targets.
/// - The Haxe stdlib expects `sys.net.Socket.select` and `waitForRead` to exist for basic polling.
///
/// What
/// - Hostname resolution (`resolve`, `toString`, reverse lookup, local hostname).
/// - TCP socket operations: bind/listen/accept/connect, stream read/write, timeouts, non-blocking,
///   and best-effort `select`.
/// - UDP socket operations: bind/connect, send/recv, broadcast.
///
/// How
/// - We represent sockets as a single handle type (`SocketHandle`) that can be TCP or UDP.
/// - IO errors map into typed `haxe.io.Error` values (runtime `hxrt::io::Error`):
///   - `WouldBlock` -> `Error::Blocked`
///   - `TimedOut` -> `Error::Custom("Timeout")`
///   - Other failures -> `Error::Custom("<os error>")`
/// - `select` uses `mio` so it works on Unix and Windows.

#[derive(Debug, Default)]
pub struct SocketHandle {
    kind: SocketKind,
    timeout: Option<Duration>,
    blocking: bool,
}

#[derive(Debug)]
enum SocketKind {
    Tcp(TcpState),
    Udp(UdpState),
}

impl Default for SocketKind {
    fn default() -> Self {
        SocketKind::Tcp(TcpState::default())
    }
}

#[derive(Debug, Default)]
struct TcpState {
    // For Haxe's `bind()` then `listen(backlog)` sequence, we need a socket we can `listen()` on.
    // std::net::TcpListener doesn't expose backlog configuration, so we use socket2.
    listener_socket: Option<Socket>,
    listener: Option<TcpListener>,

    stream: Option<TcpStream>,
    read: Option<TcpStream>,
    write: Option<TcpStream>,
    fast_send: bool,
}

#[derive(Debug, Default)]
struct UdpState {
    socket: Option<UdpSocket>,
    broadcast: bool,
}

fn apply_tcp_opts(s: &TcpStream, blocking: bool, timeout: Option<Duration>, fast_send: bool) {
    let _ = s.set_nonblocking(!blocking);
    let _ = s.set_nodelay(fast_send);
    let _ = s.set_read_timeout(timeout);
    let _ = s.set_write_timeout(timeout);
}

fn apply_udp_opts(s: &UdpSocket, blocking: bool, timeout: Option<Duration>, broadcast: bool) {
    let _ = s.set_nonblocking(!blocking);
    let _ = s.set_read_timeout(timeout);
    let _ = s.set_write_timeout(timeout);
    let _ = s.set_broadcast(broadcast);
}

fn throw_io_err(err: std::io::Error) -> ! {
    use std::io::ErrorKind;
    match err.kind() {
        ErrorKind::WouldBlock => exception::throw(dynamic::from(io::Error::Blocked)),
        ErrorKind::TimedOut => exception::throw(dynamic::from(io::Error::Custom(dynamic::from(
            String::from("Timeout"),
        )))),
        _ => exception::throw(dynamic::from(io::Error::Custom(dynamic::from(format!(
            "{}",
            err
        ))))),
    }
}

fn throw_msg(msg: &str) -> ! {
    exception::throw(dynamic::from(String::from(msg)))
}

fn ipv4_to_int(ip: Ipv4Addr) -> i32 {
    let [a, b, c, d] = ip.octets();
    // Store in network order (big-endian) like C `inet_addr`.
    ((a as i32) << 24) | ((b as i32) << 16) | ((c as i32) << 8) | (d as i32)
}

fn int_to_ipv4(ip: i32) -> Ipv4Addr {
    let a = ((ip >> 24) & 0xff) as u8;
    let b = ((ip >> 16) & 0xff) as u8;
    let c = ((ip >> 8) & 0xff) as u8;
    let d = (ip & 0xff) as u8;
    Ipv4Addr::new(a, b, c, d)
}

pub fn host_resolve(name: &str) -> i32 {
    if let Ok(ip) = name.parse::<Ipv4Addr>() {
        return ipv4_to_int(ip);
    }

    // Best-effort DNS: prefer IPv4 like Haxe's `Host.ip:Int` model.
    let addrs = match (name, 0).to_socket_addrs() {
        Ok(a) => a,
        Err(e) => throw_io_err(e),
    };
    for addr in addrs {
        match addr.ip() {
            IpAddr::V4(v4) => return ipv4_to_int(v4),
            IpAddr::V6(_) => {}
        }
    }

    throw_msg("Host resolution failed (no IPv4 address found)")
}

pub fn host_to_string(ip: i32) -> String {
    int_to_ipv4(ip).to_string()
}

pub fn host_reverse(ip: i32) -> String {
    let addr = IpAddr::V4(int_to_ipv4(ip));
    match dns_lookup::lookup_addr(&addr) {
        Ok(name) => name,
        Err(_) => host_to_string(ip),
    }
}

pub fn host_local() -> String {
    match hostname::get() {
        Ok(name) => name.to_string_lossy().to_string(),
        Err(_) => String::from("localhost"),
    }
}

pub fn socket_new_tcp() -> HxRef<SocketHandle> {
    HxRc::new(HxCell::new(SocketHandle {
        kind: SocketKind::Tcp(TcpState::default()),
        timeout: None,
        blocking: true,
    }))
}

pub fn socket_new_udp() -> HxRef<SocketHandle> {
    HxRc::new(HxCell::new(SocketHandle {
        kind: SocketKind::Udp(UdpState::default()),
        timeout: None,
        blocking: true,
    }))
}

impl SocketHandle {
    fn tcp_mut(&mut self) -> &mut TcpState {
        match &mut self.kind {
            SocketKind::Tcp(s) => s,
            SocketKind::Udp(_) => throw_msg("Socket is not TCP"),
        }
    }

    fn udp_mut(&mut self) -> &mut UdpState {
        match &mut self.kind {
            SocketKind::Udp(s) => s,
            SocketKind::Tcp(_) => throw_msg("Socket is not UDP"),
        }
    }

    pub fn close(&mut self) {
        self.kind = SocketKind::Tcp(TcpState::default());
        self.timeout = None;
        self.blocking = true;
    }

    pub fn set_timeout(&mut self, seconds: f64) {
        if seconds < 0.0 {
            self.timeout = None;
        } else {
            let ms = (seconds * 1000.0).max(0.0) as u64;
            self.timeout = Some(Duration::from_millis(ms));
        }

        match &mut self.kind {
            SocketKind::Tcp(t) => {
                if let Some(r) = t.read.as_ref() {
                    let _ = r.set_read_timeout(self.timeout);
                }
                if let Some(w) = t.write.as_ref() {
                    let _ = w.set_write_timeout(self.timeout);
                }
            }
            SocketKind::Udp(u) => {
                if let Some(s) = u.socket.as_ref() {
                    let _ = s.set_read_timeout(self.timeout);
                    let _ = s.set_write_timeout(self.timeout);
                }
            }
        }
    }

    pub fn set_blocking(&mut self, blocking: bool) {
        self.blocking = blocking;
        match &mut self.kind {
            SocketKind::Tcp(t) => {
                if let Some(l) = t.listener.as_ref() {
                    let _ = l.set_nonblocking(!blocking);
                }
                if let Some(s) = t.stream.as_ref() {
                    let _ = s.set_nonblocking(!blocking);
                }
                if let Some(r) = t.read.as_ref() {
                    let _ = r.set_nonblocking(!blocking);
                }
                if let Some(w) = t.write.as_ref() {
                    let _ = w.set_nonblocking(!blocking);
                }
            }
            SocketKind::Udp(u) => {
                if let Some(s) = u.socket.as_ref() {
                    let _ = s.set_nonblocking(!blocking);
                }
            }
        }
    }

    pub fn set_fast_send(&mut self, fast: bool) {
        let t = self.tcp_mut();
        t.fast_send = fast;
        if let Some(s) = t.stream.as_ref() {
            let _ = s.set_nodelay(fast);
        }
    }

    pub fn connect(&mut self, ip: i32, port: i32) {
        let blocking = self.blocking;
        let timeout = self.timeout;
        match &mut self.kind {
            SocketKind::Tcp(t) => {
                let fast_send = t.fast_send;
                let addr = SocketAddr::V4(SocketAddrV4::new(int_to_ipv4(ip), port as u16));
                let stream = match TcpStream::connect(addr) {
                    Ok(s) => s,
                    Err(e) => throw_io_err(e),
                };

                apply_tcp_opts(&stream, blocking, timeout, fast_send);
                let read = match stream.try_clone() {
                    Ok(s) => s,
                    Err(e) => throw_io_err(e),
                };
                let write = match stream.try_clone() {
                    Ok(s) => s,
                    Err(e) => throw_io_err(e),
                };
                apply_tcp_opts(&read, blocking, timeout, fast_send);
                apply_tcp_opts(&write, blocking, timeout, fast_send);

                t.stream = Some(stream);
                t.read = Some(read);
                t.write = Some(write);
            }
            SocketKind::Udp(u) => {
                if u.socket.is_none() {
                    let sock = match UdpSocket::bind("0.0.0.0:0") {
                        Ok(s) => s,
                        Err(e) => throw_io_err(e),
                    };
                    apply_udp_opts(&sock, blocking, timeout, u.broadcast);
                    u.socket = Some(sock);
                }
                let addr = SocketAddr::V4(SocketAddrV4::new(int_to_ipv4(ip), port as u16));
                if let Some(sock) = u.socket.as_ref() {
                    if let Err(e) = sock.connect(addr) {
                        throw_io_err(e)
                    }
                }
            }
        }
    }

    pub fn bind(&mut self, ip: i32, port: i32) {
        let blocking = self.blocking;
        let timeout = self.timeout;
        match &mut self.kind {
            SocketKind::Tcp(t) => {
                let addr = SocketAddr::V4(SocketAddrV4::new(int_to_ipv4(ip), port as u16));
                let domain = Domain::IPV4;
                let socket = match Socket::new(domain, Type::STREAM, Some(Protocol::TCP)) {
                    Ok(s) => s,
                    Err(e) => throw_io_err(e),
                };

                let _ = socket.set_reuse_address(true);
                if let Err(e) = socket.bind(&addr.into()) {
                    throw_io_err(e)
                }
                t.listener_socket = Some(socket);
            }
            SocketKind::Udp(u) => {
                let addr = SocketAddr::V4(SocketAddrV4::new(int_to_ipv4(ip), port as u16));
                let sock = match UdpSocket::bind(addr) {
                    Ok(s) => s,
                    Err(e) => throw_io_err(e),
                };
                apply_udp_opts(&sock, blocking, timeout, u.broadcast);
                u.socket = Some(sock);
            }
        }
    }

    pub fn listen(&mut self, backlog: i32) {
        let blocking = self.blocking;
        let t = self.tcp_mut();
        if t.listener.is_some() {
            return;
        }
        let sock = match t.listener_socket.take() {
            Some(s) => s,
            None => throw_msg("Socket is not bound"),
        };
        let backlog = backlog.max(0);
        if let Err(e) = sock.listen(backlog) {
            throw_io_err(e)
        }
        let listener: TcpListener = sock.into();
        let _ = listener.set_nonblocking(!blocking);
        t.listener = Some(listener);
    }

    pub fn accept(&mut self) -> HxRef<SocketHandle> {
        let blocking = self.blocking;
        let timeout = self.timeout;
        let t = self.tcp_mut();
        let fast_send = t.fast_send;
        let listener = match t.listener.as_ref() {
            Some(l) => l,
            None => throw_msg("Socket is not listening"),
        };
        let (stream, _) = match listener.accept() {
            Ok(v) => v,
            Err(e) => throw_io_err(e),
        };

        let mut out = SocketHandle {
            kind: SocketKind::Tcp(TcpState::default()),
            timeout,
            blocking,
        };
        if let SocketKind::Tcp(ts) = &mut out.kind {
            ts.fast_send = fast_send;
        }
        apply_tcp_opts(&stream, blocking, timeout, fast_send);
        let read = match stream.try_clone() {
            Ok(s) => s,
            Err(e) => throw_io_err(e),
        };
        let write = match stream.try_clone() {
            Ok(s) => s,
            Err(e) => throw_io_err(e),
        };
        apply_tcp_opts(&read, blocking, timeout, fast_send);
        apply_tcp_opts(&write, blocking, timeout, fast_send);
        if let SocketKind::Tcp(ts) = &mut out.kind {
            ts.stream = Some(stream);
            ts.read = Some(read);
            ts.write = Some(write);
        }

        HxRc::new(HxCell::new(out))
    }

    pub fn shutdown(&mut self, read: bool, write: bool) {
        let t = self.tcp_mut();
        let stream = match t.stream.as_ref() {
            Some(s) => s,
            None => throw_msg("Socket is not connected"),
        };
        use std::net::Shutdown;
        let how = match (read, write) {
            (true, true) => Shutdown::Both,
            (true, false) => Shutdown::Read,
            (false, true) => Shutdown::Write,
            (false, false) => return,
        };
        if let Err(e) = stream.shutdown(how) {
            throw_io_err(e)
        }
    }

    pub fn peer(&self) -> (i32, i32) {
        match &self.kind {
            SocketKind::Tcp(t) => {
                let stream = match t.stream.as_ref() {
                    Some(s) => s,
                    None => throw_msg("Socket is not connected"),
                };
                let addr = match stream.peer_addr() {
                    Ok(a) => a,
                    Err(e) => throw_io_err(e),
                };
                match addr {
                    SocketAddr::V4(v4) => (ipv4_to_int(*v4.ip()), v4.port() as i32),
                    SocketAddr::V6(_) => (0, 0),
                }
            }
            SocketKind::Udp(u) => {
                let sock = match u.socket.as_ref() {
                    Some(s) => s,
                    None => throw_msg("UDP socket is not open"),
                };
                let addr = match sock.peer_addr() {
                    Ok(a) => a,
                    Err(e) => throw_io_err(e),
                };
                match addr {
                    SocketAddr::V4(v4) => (ipv4_to_int(*v4.ip()), v4.port() as i32),
                    SocketAddr::V6(_) => (0, 0),
                }
            }
        }
    }

    pub fn host(&self) -> (i32, i32) {
        match &self.kind {
            SocketKind::Tcp(t) => {
                let addr = if let Some(stream) = t.stream.as_ref() {
                    match stream.local_addr() {
                        Ok(a) => a,
                        Err(e) => throw_io_err(e),
                    }
                } else if let Some(listener) = t.listener.as_ref() {
                    match listener.local_addr() {
                        Ok(a) => a,
                        Err(e) => throw_io_err(e),
                    }
                } else if let Some(sock) = t.listener_socket.as_ref() {
                    let a = match sock.local_addr() {
                        Ok(a) => a,
                        Err(e) => throw_io_err(e),
                    };
                    match a.as_socket() {
                        Some(a) => a,
                        None => throw_msg("Socket has no local address"),
                    }
                } else {
                    throw_msg("Socket is not bound")
                };
                match addr {
                    SocketAddr::V4(v4) => (ipv4_to_int(*v4.ip()), v4.port() as i32),
                    SocketAddr::V6(_) => (0, 0),
                }
            }
            SocketKind::Udp(u) => {
                let sock = match u.socket.as_ref() {
                    Some(s) => s,
                    None => throw_msg("UDP socket is not open"),
                };
                let addr = match sock.local_addr() {
                    Ok(a) => a,
                    Err(e) => throw_io_err(e),
                };
                match addr {
                    SocketAddr::V4(v4) => (ipv4_to_int(*v4.ip()), v4.port() as i32),
                    SocketAddr::V6(_) => (0, 0),
                }
            }
        }
    }

    pub fn read_stream(&mut self, buf: &mut [u8]) -> i32 {
        let t = self.tcp_mut();
        let r = match t.read.as_mut() {
            Some(s) => s,
            None => throw_msg("Socket is not connected"),
        };
        match r.read(buf) {
            Ok(0) => -1,
            Ok(n) => n as i32,
            Err(e) => throw_io_err(e),
        }
    }

    pub fn write_stream(&mut self, buf: &[u8]) -> i32 {
        let t = self.tcp_mut();
        let w = match t.write.as_mut() {
            Some(s) => s,
            None => throw_msg("Socket is not connected"),
        };
        match w.write(buf) {
            Ok(n) => n as i32,
            Err(e) => throw_io_err(e),
        }
    }

    pub fn udp_set_broadcast(&mut self, enable: bool) {
        let blocking = self.blocking;
        let timeout = self.timeout;
        let u = self.udp_mut();
        u.broadcast = enable;
        if let Some(s) = u.socket.as_ref() {
            apply_udp_opts(s, blocking, timeout, enable);
        }
    }

    pub fn udp_send_to(&mut self, buf: &[u8], ip: i32, port: i32) -> i32 {
        let u = self.udp_mut();
        let sock = match u.socket.as_ref() {
            Some(s) => s,
            None => throw_msg("UDP socket is not open"),
        };
        let addr = SocketAddr::V4(SocketAddrV4::new(int_to_ipv4(ip), port as u16));
        match sock.send_to(buf, addr) {
            Ok(n) => n as i32,
            Err(e) => throw_io_err(e),
        }
    }

    pub fn udp_read_from(&mut self, buf: &mut [u8]) -> (i32, i32, i32) {
        let u = self.udp_mut();
        let sock = match u.socket.as_ref() {
            Some(s) => s,
            None => throw_msg("UDP socket is not open"),
        };
        match sock.recv_from(buf) {
            Ok((0, _)) => (-1, 0, 0),
            Ok((n, addr)) => match addr {
                SocketAddr::V4(v4) => (n as i32, ipv4_to_int(*v4.ip()), v4.port() as i32),
                SocketAddr::V6(_) => (n as i32, 0, 0),
            },
            Err(e) => throw_io_err(e),
        }
    }
}

enum AnySource {
    TcpStream(mio::net::TcpStream),
    TcpListener(mio::net::TcpListener),
    Udp(mio::net::UdpSocket),
}

impl AnySource {
    fn register(
        &mut self,
        poll: &mut Poll,
        token: Token,
        interest: Interest,
    ) -> std::io::Result<()> {
        match self {
            AnySource::TcpStream(s) => poll.registry().register(s, token, interest),
            AnySource::TcpListener(s) => poll.registry().register(s, token, interest),
            AnySource::Udp(s) => poll.registry().register(s, token, interest),
        }
    }
}

fn socket_source_clone(h: &HxRef<SocketHandle>) -> Option<AnySource> {
    let hb = h.borrow();
    match &hb.kind {
        SocketKind::Tcp(t) => {
            if let Some(s) = t.stream.as_ref() {
                let c = s.try_clone().ok()?;
                c.set_nonblocking(true).ok()?;
                Some(AnySource::TcpStream(mio::net::TcpStream::from_std(c)))
            } else if let Some(l) = t.listener.as_ref() {
                let c = l.try_clone().ok()?;
                c.set_nonblocking(true).ok()?;
                Some(AnySource::TcpListener(mio::net::TcpListener::from_std(c)))
            } else {
                None
            }
        }
        SocketKind::Udp(u) => {
            let s = u.socket.as_ref()?;
            let c = s.try_clone().ok()?;
            c.set_nonblocking(true).ok()?;
            Some(AnySource::Udp(mio::net::UdpSocket::from_std(c)))
        }
    }
}

pub fn socket_select(
    read: Vec<HxRef<SocketHandle>>,
    write: Vec<HxRef<SocketHandle>>,
    others: Vec<HxRef<SocketHandle>>,
    timeout_seconds: Option<f64>,
) -> (Vec<i32>, Vec<i32>, Vec<i32>) {
    let mut poll = match Poll::new() {
        Ok(p) => p,
        Err(e) => throw_io_err(e),
    };
    let mut events = Events::with_capacity(read.len() + write.len() + others.len() + 8);

    #[derive(Clone, Copy)]
    enum Group {
        Read,
        Write,
        Other,
    }

    let mut token_map: Vec<(Group, usize)> = vec![];
    let mut sources: Vec<AnySource> = vec![];

    let mut register_group =
        |group: Group, interest: Interest, sockets: &Vec<HxRef<SocketHandle>>| {
            for (idx, s) in sockets.iter().enumerate() {
                let Some(mut src) = socket_source_clone(s) else {
                    continue;
                };
                let token = Token(token_map.len());
                if let Err(e) = src.register(&mut poll, token, interest) {
                    throw_io_err(e)
                }
                token_map.push((group, idx));
                sources.push(src);
            }
        };

    register_group(Group::Read, Interest::READABLE, &read);
    register_group(Group::Write, Interest::WRITABLE, &write);
    register_group(
        Group::Other,
        Interest::READABLE | Interest::WRITABLE,
        &others,
    );

    let timeout = timeout_seconds.and_then(|t| {
        if t < 0.0 {
            None
        } else {
            Some(Duration::from_millis((t * 1000.0).max(0.0) as u64))
        }
    });

    if let Err(e) = poll.poll(&mut events, timeout) {
        throw_io_err(e)
    }

    let mut r_ready = vec![false; read.len()];
    let mut w_ready = vec![false; write.len()];
    let mut o_ready = vec![false; others.len()];

    for ev in events.iter() {
        let i = ev.token().0;
        if i >= token_map.len() {
            continue;
        }
        let (group, idx) = token_map[i];
        match group {
            Group::Read => {
                if idx < r_ready.len() {
                    r_ready[idx] = true
                }
            }
            Group::Write => {
                if idx < w_ready.len() {
                    w_ready[idx] = true
                }
            }
            Group::Other => {
                if idx < o_ready.len() {
                    o_ready[idx] = true
                }
            }
        }
    }

    let mut r_idx: Vec<i32> = vec![];
    for (i, ok) in r_ready.iter().enumerate() {
        if *ok {
            r_idx.push(i as i32);
        }
    }
    let mut w_idx: Vec<i32> = vec![];
    for (i, ok) in w_ready.iter().enumerate() {
        if *ok {
            w_idx.push(i as i32);
        }
    }
    let mut o_idx: Vec<i32> = vec![];
    for (i, ok) in o_ready.iter().enumerate() {
        if *ok {
            o_idx.push(i as i32);
        }
    }

    (r_idx, w_idx, o_idx)
}
