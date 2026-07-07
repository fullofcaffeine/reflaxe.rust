package rust.net;

import rust.Result;

/**
	`rust.net.TcpListener`

	Why
	- Rust-native TCP listeners are RAII handles: dropping the value closes the listener.
	- Haxe's portable socket listener semantics should not be implied for metal code that only wants
	  a direct blocking `std::net::TcpListener` shape.

	What
	- A typed owner for the narrow M55 blocking TCP listener facade.
	- `localPort()` reports the concrete port assigned by the OS, which makes `port = 0` fixtures
	  deterministic without hardcoding a port.
	- `accept()` waits for one incoming connection and returns a typed `TcpStream`.

	How
	- The extern maps to `crate::native_tcp_tools::TcpListener`, a wrapper around
	  `std::net::TcpListener`.
	- Methods return `rust.Result` instead of throwing Haxe exceptions.
	- The current surface deliberately exposes only the minimal blocking operations needed for the
	  localhost no-hxrt proof.
**/
@:native("crate::native_tcp_tools::TcpListener")
@:rustExtraSrc("rust/native/native_tcp_tools.rs")
extern class TcpListener {
	public function localPort():Result<Int, String>;
	public function accept():Result<TcpStream, String>;
}
