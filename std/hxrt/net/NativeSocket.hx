package hxrt.net;

import hxrt.ssl.CertificateHandle;
import hxrt.ssl.KeyHandle;
import rust.HxRef;
import rust.Ref;

/**
	Typed native boundary for `sys.net.Socket` operations.

	Why
	- `sys.net.Socket` is a core stdlib API, but the actual socket implementation lives in Rust
	  runtime code (`hxrt::net`).
	- Keeping this bridge typed avoids raw `__rust__` snippets in first-party std overrides and
	  improves metal fallback diagnostics.

	What
	- Exposes TCP socket lifecycle and polling helpers used by `std/rust/_std/sys/net/Socket.hx`.
	- Returns plain typed values (`Int`, `Bool`, `Array<Array<Int>>`) so callers immediately return
	  to normal typed Haxe code.

	How
	- Binds to crate module `socket_native` provided via `@:rustExtraSrc`.
	- Each method maps to a small Rust wrapper function that calls `hxrt::net::SocketHandle` methods.
**/
@:native("crate::socket_native")
@:rustExtraSrc("sys/net/native/socket_native.rs")
extern class NativeSocket {
	@:native("new_tcp")
	public static function newTcp():HxRef<SocketHandle>;

	@:native("new_udp")
	public static function newUdp():HxRef<SocketHandle>;

	@:native("host_resolve")
	public static function hostResolve(name:Ref<String>):Int;

	@:native("host_to_string")
	public static function hostToString(ip:Int):String;

	@:native("host_reverse")
	public static function hostReverse(ip:Int):String;

	@:native("host_local")
	public static function hostLocal():String;

	@:native("close")
	public static function closeHandle(handle:Ref<HxRef<SocketHandle>>):Void;

	public static function connect(handle:Ref<HxRef<SocketHandle>>, host:Int, port:Int):Void;
	public static function listen(handle:Ref<HxRef<SocketHandle>>, connections:Int):Void;
	public static function shutdown(handle:Ref<HxRef<SocketHandle>>, read:Bool, write:Bool):Void;
	public static function bind(handle:Ref<HxRef<SocketHandle>>, host:Int, port:Int):Void;
	public static function accept(handle:Ref<HxRef<SocketHandle>>):HxRef<SocketHandle>;

	@:native("peer_ip")
	public static function peerIp(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("peer_port")
	public static function peerPort(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("host_ip")
	public static function hostIp(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("host_port")
	public static function hostPort(handle:Ref<HxRef<SocketHandle>>):Int;

	@:native("set_timeout")
	public static function setTimeout(handle:Ref<HxRef<SocketHandle>>, timeout:Float):Void;

	@:native("wait_for_read")
	public static function waitForRead(handle:Ref<HxRef<SocketHandle>>):Void;

	@:native("set_blocking")
	public static function setBlocking(handle:Ref<HxRef<SocketHandle>>, blocking:Bool):Void;

	@:native("set_fast_send")
	public static function setFastSend(handle:Ref<HxRef<SocketHandle>>, fastSend:Bool):Void;

	/**
		Upgrade a connected TCP socket to a TLS client session.

		Why
		- `sys.ssl.Socket.handshake()` should stay in typed Haxe code instead of embedding raw Rust.

		What
		- Delegates to `hxrt::net::SocketHandle::tls_handshake_client`.

		How
		- `hostname` becomes the SNI / verification hostname when non-null.
		- `ca` is an optional custom trust store chain.
	**/
	@:native("tls_handshake_client")
	public static function tlsHandshakeClient(handle:Ref<HxRef<SocketHandle>>, hostname:Null<String>, verifyCert:Bool, ca:Null<HxRef<CertificateHandle>>):Void;

	/**
		Upgrade a connected TCP socket to a TLS server session using a single certificate.
	**/
	@:native("tls_handshake_server")
	public static function tlsHandshakeServer(handle:Ref<HxRef<SocketHandle>>, cert:Ref<HxRef<CertificateHandle>>, key:Ref<HxRef<KeyHandle>>):Void;

	/**
		Upgrade a connected TCP socket to a TLS server session with optional SNI-driven certificate
		selection.

		Why
		- `sys.ssl.Socket.addSNICertificate` accepts Haxe matchers (`String->Bool`), but the actual
		  TLS cert selection happens inside the Rust runtime during the server handshake.

		What
		- Passes the default server certificate plus zero-or-more matcher/cert/key triples to the
		  runtime, which resolves the final certificate against the incoming client SNI.

		How
		- `matchers`, `certs`, and `keys` are parallel arrays.
		- Null entries are ignored by the runtime so API-surface smoke tests can exercise the method
		  without forcing a live TLS handshake.
	**/
	@:native("tls_handshake_server_sni")
	public static function tlsHandshakeServerSni(handle:Ref<HxRef<SocketHandle>>, defaultCert:Ref<HxRef<CertificateHandle>>, defaultKey:Ref<HxRef<KeyHandle>>,
		matchers:Array<Null<(String) -> Bool>>, certs:Array<Null<HxRef<CertificateHandle>>>, keys:Array<Null<HxRef<KeyHandle>>>):Void;

	/**
		Read the peer certificate chain from the current TLS session.
	**/
	@:native("tls_peer_certificate")
	public static function tlsPeerCertificate(handle:Ref<HxRef<SocketHandle>>):HxRef<CertificateHandle>;

	@:native("write_bytes")
	public static function writeBytes(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int):Int;

	@:native("read_bytes")
	public static function readBytes(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int):Int;

	@:native("udp_set_broadcast")
	public static function udpSetBroadcast(handle:Ref<HxRef<SocketHandle>>, enabled:Bool):Void;

	@:native("udp_send_to")
	public static function udpSendTo(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int, host:Int, port:Int):Int;

	@:native("udp_read_from")
	public static function udpReadFrom(handle:Ref<HxRef<SocketHandle>>, bytes:Ref<haxe.io.Bytes>, pos:Int, len:Int):Array<Int>;

	@:native("select_groups")
	public static function selectGroups(read:Ref<Array<HxRef<SocketHandle>>>, write:Ref<Array<HxRef<SocketHandle>>>, others:Ref<Array<HxRef<SocketHandle>>>,
		timeout:Null<Float>):Array<Array<Int>>;
}
