package sys.ssl;

import hxrt.net.NativeSocket;
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
	- TLS is enabled in the runtime by upgrading the underlying `hxrt::net::SocketHandle` in-place
	  through the typed `hxrt.net.NativeSocket` boundary.
	- Server-side SNI selection is modeled as a list of Haxe matcher/cert/key triples which the
	  runtime resolves against the incoming client SNI hostname during handshake.
**/
class Socket extends sys.net.Socket {
	public static var DEFAULT_VERIFY_CERT:Null<Bool>;
	public static var DEFAULT_CA:Null<sys.ssl.Certificate>;

	public var verifyCert:Null<Bool> = null;

	private var ca:Null<sys.ssl.Certificate> = null;
	private var hostname:Null<String> = null;
	private var serverCert:Null<sys.ssl.Certificate> = null;
	private var serverKey:Null<sys.ssl.Key> = null;
	private var sniMatchers:Array<Null<(String) -> Bool>> = [];
	private var sniCerts:Array<Null<sys.ssl.Certificate>> = [];
	private var sniKeys:Array<Null<sys.ssl.Key>> = [];

	public function new():Void {
		super();
	}

	/**
		Upgrade the connected socket to TLS.

		Why
		- `sys.ssl.Socket` keeps the upstream Haxe surface, but the real TLS session is owned by the
		  Rust runtime.

		What
		- Client mode uses `hostname`, `verifyCert`, and optional CA roots.
		- Server mode uses `setCertificate(...)` as the default cert and optional
		  `addSNICertificate(...)` overrides.

		How
		- This method stays purely typed Haxe code and delegates to `hxrt.net.NativeSocket`.
	**/
	public function handshake():Void {
		var verify:Bool = (verifyCert != false);
		if (serverCert != null && serverKey != null) {
			if (sniMatchers.length > 0) {
				NativeSocket.tlsHandshakeServerSni(handle, serverCert.handle, serverKey.handle, sniMatchers,
					[for (cert in sniCerts) cert == null ? null : cert.handle], [for (key in sniKeys) key == null ? null : key.handle]);
			} else {
				NativeSocket.tlsHandshakeServer(handle, serverCert.handle, serverKey.handle);
			}
			return;
		}

		NativeSocket.tlsHandshakeClient(handle, hostname, verify, ca == null ? null : ca.handle);
	}

	public function setCA(cert:sys.ssl.Certificate):Void {
		this.ca = cert;
	}

	public function setHostname(name:String):Void {
		this.hostname = name;
	}

	public function setCertificate(cert:Certificate, key:Key):Void {
		this.serverCert = cert;
		this.serverKey = key;
	}

	/**
		Register an additional server certificate that may be selected via client SNI.

		Why
		- Upstream Haxe exposes SNI selection as a callback rather than a simple hostname table.
		- The Rust runtime needs the matcher plus cert/key so it can choose a certificate when the
		  TLS client hello arrives.

		What
		- Stores a matcher/cert/key triple for use by the next server-side `handshake()`.
		- `setCertificate(...)` remains the default/fallback certificate.

		How
		- Null entries are preserved at the Haxe surface so API-surface smoke tests and parity calls
		  do not throw eagerly.
		- The typed runtime boundary filters invalid entries before building the rustls resolver.
	**/
	public function addSNICertificate(cbServernameMatch:String->Bool, cert:Certificate, key:Key):Void {
		sniMatchers.push(cbServernameMatch);
		sniCerts.push(cert);
		sniKeys.push(key);
	}

	public function peerCertificate():sys.ssl.Certificate {
		return sys.ssl.Certificate.fromHandle(NativeSocket.tlsPeerCertificate(handle));
	}

	override public function accept():Socket {
		var h = untyped __rust__("{0}.borrow_mut().accept()", handle);
		var s:Socket = new Socket();
		untyped s.handle = h;
		untyped s.input = new sys.net._SocketIO.SocketInput(h);
		untyped s.output = new sys.net._SocketIO.SocketOutput(h);
		return s;
	}

	public override function connect(host:Host, port:Int):Void {
		super.connect(host, port);
	}
}
