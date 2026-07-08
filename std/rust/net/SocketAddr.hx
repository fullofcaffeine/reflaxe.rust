package rust.net;

import rust.Result;

/**
	`rust.net.SocketAddr`

	Why
	- The first Rust-native TCP/UDP facades intentionally accepted only localhost ports. That kept
	  M55-M59 deterministic, but it left app code without a typed value to carry an address between
	  bind/connect/send APIs.
	- Metal networking should expose Rust-shaped authority through typed Haxe values, not through
	  stringly host/port pairs, portable `sys.net` handles, `Dynamic`, or raw `std::net` snippets.
	- A first address value lets examples and policy gates prove direct `std::net::SocketAddr`
	  lowering while still avoiding DNS, TLS, async runtimes, or arbitrary external networking.

	What
	- A narrow loopback socket-address value for the M60 Rust-native networking slice.
	- `localhost(port)` builds `127.0.0.1:<port>` and returns a String-error `Result`.
	- `localhostDetailed(port)` keeps the same behavior but reports invalid port values as
	  `SocketError::invalid_input`.
	- `port()` exposes the concrete port from a constructed address, including OS-assigned ports
	  returned from `localAddr()`.

	How
	- The extern maps to `crate::native_socket_addr_tools::SocketAddr`, a small wrapper around
	  `std::net::SocketAddr`.
	- TCP/UDP helper modules accept this wrapper and convert it internally to `std::net` values.
	- `localhost(...)`, `localhostDetailed(...)`, and `port()` are compiler-lowered into direct
	  `std::net` operations. The helper no longer owns those pure constructor/accessor bodies.
	- The helper is retained only for representation privacy and crate-private conversion handoff:
	  current Haxe externs still cannot declare the Rust wrapper field or expose the narrow
	  `from_std` / `as_std` bridge needed by `TcpListener` / `UdpSocket` helpers without raw Rust or
	  generic native-wrapper generation.
	- This is a native facade island, not `hxrt`: it carries a direct Rust stdlib value and does not
	  provide Haxe semantic runtime behavior.
	- In `metal + rust_no_hxrt`, this must stay free of `hxrt`, `Dynamic`, portable socket handles,
	  DNS lookups, and app-side raw Rust.
**/
@:native("crate::native_socket_addr_tools::SocketAddr")
@:rustExtraSrc("rust/native/native_socket_addr_tools.rs")
extern class SocketAddr {
	public static function localhost(port:Int):Result<SocketAddr, String>;
	public static function localhostDetailed(port:Int):Result<SocketAddr, SocketError>;
	public function port():Int;
}
