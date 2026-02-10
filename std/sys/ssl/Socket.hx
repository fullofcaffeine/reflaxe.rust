package sys.ssl;

import sys.net.Host;

/**
	`sys.ssl.Socket` (Rust target override)

	Why
	- `sys.ssl.Socket` is the stdlib's TLS-capable socket type.
	- `sys.Http` uses it (directly or indirectly) to implement HTTPS.

	What
	- A TCP socket that can be upgraded to TLS via `handshake()`.
	- Configuration hooks for certificate verification, trust roots (CA), and SNI hostname.

	How
	- Inherits all plain TCP behavior from `sys.net.Socket` (connect/bind/listen/accept/read/write).
	- TLS is enabled in the runtime by upgrading the underlying `hxrt::net::SocketHandle` in-place:
	  `SocketHandle::tls_handshake_client(hostname, verifyCert, ca)`.
	- Current limitations (v1 era):
	  - Client certificates (`setCertificate`) and SNI certificate selection (`addSNICertificate`)
	    are accepted for API parity but not yet used by the runtime.
**/
class Socket extends sys.net.Socket {
	public static var DEFAULT_VERIFY_CERT: Null<Bool>;
	public static var DEFAULT_CA: Null<sys.ssl.Certificate>;

	public var verifyCert: Null<Bool> = null;

	private var ca: Null<sys.ssl.Certificate> = null;
	private var hostname: Null<String> = null;
	private var serverCert: Null<sys.ssl.Certificate> = null;
	private var serverKey: Null<sys.ssl.Key> = null;

	public function new(): Void {
		super();
	}

	public function handshake(): Void {
		var verify: Bool = (verifyCert != false);
		if (serverCert != null && serverKey != null) {
			untyped __rust__(
				"{
					let cert_handle = {1}.borrow().handle.clone();
					let key_handle = {2}.borrow().handle.clone();
					{0}.borrow_mut().tls_handshake_server(cert_handle, key_handle);
				}",
				handle,
				serverCert,
				serverKey
			);
			return;
		}

		untyped __rust__(
			"{
				let ca_handle = match {3}.as_arc_opt() {
					None => None,
					Some(c) => Some(c.borrow().handle.clone()),
				};
				{0}.borrow_mut().tls_handshake_client({1}, Some({2} as bool), ca_handle);
			}",
			handle,
			hostname,
			verify,
			ca
		);
	}

	public function setCA(cert: sys.ssl.Certificate): Void {
		this.ca = cert;
	}

	public function setHostname(name: String): Void {
		this.hostname = name;
	}

	public function setCertificate(cert: Certificate, key: Key): Void {
		this.serverCert = cert;
		this.serverKey = key;
	}

	public function addSNICertificate(_cbServernameMatch: String -> Bool, _cert: Certificate, _key: Key): Void {
		throw "sys.ssl.Socket.addSNICertificate is not implemented yet on reflaxe.rust";
	}

	public function peerCertificate(): sys.ssl.Certificate {
		var h = untyped __rust__("{0}.borrow().tls_peer_certificate()", handle);
		return sys.ssl.Certificate.fromHandle(h);
	}

	override public function accept(): Socket {
		var h = untyped __rust__("{0}.borrow_mut().accept()", handle);
		var s: Socket = new Socket();
		untyped s.handle = h;
		untyped s.input = new sys.net._SocketIO.SocketInput(h);
		untyped s.output = new sys.net._SocketIO.SocketOutput(h);
		return s;
	}

	public override function connect(host: Host, port: Int): Void {
		super.connect(host, port);
	}
}
