package rust.net;

import rust.Result;

/**
	`rust.net.UdpSocket`

	Why
	- UDP sockets are native RAII handles: dropping the value closes the socket.
	- Portable Haxe socket semantics should not be implied for metal code that only wants a direct
	  blocking `std::net::UdpSocket` shape.

	What
	- A typed owner for the narrow M56 blocking UDP localhost facade.
	- `localPort()` reports the concrete port assigned by the OS, which makes `port = 0` fixtures
	  deterministic without hardcoding a port.
	- `sendUtf8ToLocalhost(...)` sends one UTF-8 datagram to `127.0.0.1:<port>`.
	- `recvUtf8(...)` receives one datagram into an explicitly sized buffer and decodes it as UTF-8.

	How
	- The extern maps to `crate::native_udp_tools::UdpSocket`, a wrapper around
	  `std::net::UdpSocket`.
	- Methods return `rust.Result` instead of throwing Haxe exceptions.
	- The current surface deliberately exposes only the minimal blocking datagram operations needed
	  for the localhost no-hxrt proof.
**/
@:native("crate::native_udp_tools::UdpSocket")
@:rustExtraSrc("rust/native/native_udp_tools.rs")
extern class UdpSocket {
	public function localPort():Result<Int, String>;
	public function sendUtf8ToLocalhost(payload:String, port:Int):Result<Int, String>;
	public function recvUtf8(maxBytes:Int):Result<String, String>;
}
