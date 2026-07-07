package rust.net;

import rust.Result;
import rust.Vec;

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
	- `localAddr()` reports the concrete M60 `SocketAddr`, allowing callers to pass the address
	  directly into `sendUtf8To(...)` or `sendBytesTo(...)`.
	- `sendUtf8ToLocalhost(...)` sends one UTF-8 datagram to `127.0.0.1:<port>`.
	- `recvUtf8(...)` receives one datagram into an explicitly sized buffer and decodes it as UTF-8.
	- `sendBytesToLocalhost(...)` and `recvBytes(...)` expose raw datagram payloads as
	  `rust.Vec<Int>` byte values. The helper validates each send byte is in `0...255` before it
	  touches the Rust `u8` buffer.
	- The `Detailed` variants keep the String-error methods source-compatible while returning
	  `SocketError` for invalid input, IO, and UTF-8 decode categories. Byte APIs use
	  `SocketError::invalid_input` for out-of-range byte values.

	How
	- The extern maps to `crate::native_udp_tools::UdpSocket`, a wrapper around
	  `std::net::UdpSocket`.
	- Methods return `rust.Result` instead of throwing Haxe exceptions.
	- The current surface deliberately exposes only the minimal blocking datagram operations needed
	  for the localhost no-hxrt proof.
	- This is not portable `haxe.io.Bytes`; portable byte buffers still belong to the runtime-backed
	  Haxe stdlib contract. This facade is a Rust-native datagram contract for metal code.
**/
@:native("crate::native_udp_tools::UdpSocket")
@:rustExtraSrc("rust/native/native_udp_tools.rs")
extern class UdpSocket {
	public function localAddr():Result<SocketAddr, String>;
	public function localAddrDetailed():Result<SocketAddr, SocketError>;
	public function localPort():Result<Int, String>;
	public function localPortDetailed():Result<Int, SocketError>;
	public function sendUtf8To(payload:String, addr:SocketAddr):Result<Int, String>;
	public function sendUtf8ToDetailed(payload:String, addr:SocketAddr):Result<Int, SocketError>;
	public function sendUtf8ToLocalhost(payload:String, port:Int):Result<Int, String>;
	public function sendUtf8ToLocalhostDetailed(payload:String, port:Int):Result<Int, SocketError>;
	public function recvUtf8(maxBytes:Int):Result<String, String>;
	public function recvUtf8Detailed(maxBytes:Int):Result<String, SocketError>;
	public function sendBytesTo(payload:Vec<Int>, addr:SocketAddr):Result<Int, String>;
	public function sendBytesToDetailed(payload:Vec<Int>, addr:SocketAddr):Result<Int, SocketError>;
	public function sendBytesToLocalhost(payload:Vec<Int>, port:Int):Result<Int, String>;
	public function sendBytesToLocalhostDetailed(payload:Vec<Int>, port:Int):Result<Int, SocketError>;
	public function recvBytes(maxBytes:Int):Result<Vec<Int>, String>;
	public function recvBytesDetailed(maxBytes:Int):Result<Vec<Int>, SocketError>;
}
