package rust.net;

import rust.Result;

/**
	`rust.net.NativeTcp`

	Why
	- Portable `sys.net.Socket` preserves Haxe's socket API and correctly goes through the
	  `hxrt.net` runtime layer for stream wrappers, exceptions, nullable strings, and platform
	  compatibility.
	- Metal code sometimes needs the narrower Rust contract: explicit blocking TCP over localhost,
	  direct `std::net` ownership, and no portable socket/runtime behavior.
	- A typed facade keeps app code away from raw `std::net` snippets while giving policy checks one
	  stable helper shape to inspect for no-hxrt output.

	What
	- First M55 Rust-native TCP entry point.
	- `bindLocalhost(port)` binds `127.0.0.1:<port>` and returns a typed `TcpListener`; passing `0`
	  asks the OS for an ephemeral port.
	- `connectLocalhost(port)` connects a typed `TcpStream` to `127.0.0.1:<port>`.
	- `bind(addr)` and `connect(addr)` accept the M60 typed `SocketAddr` value so loopback addresses
	  can be carried between APIs without stringly host/port plumbing.
	- The `Detailed` variants keep the same behavior but return `SocketError` so callers can branch
	  on invalid-input or IO categories without parsing error text.
	- This is intentionally not portable `sys.net` parity, not TLS, not UDP, not async networking,
	  not DNS, and not a general external host API yet.

	How
	- `@:native("crate::native_tcp_tools::NativeTcp")` binds to a small Rust helper module.
	- `@:rustExtraSrc("rust/native/native_tcp_tools.rs")` copies that helper into generated crates.
	- The helper owns `std::net::TcpListener` / `std::net::TcpStream` wrapper structs and returns
	  `rust.Result<..., String>` so callers stay in explicit Rust-style error handling.
	- In `metal + rust_no_hxrt`, this surface must remain free of `hxrt`, `Dynamic`, Haxe `Array`,
	  and app-side raw Rust snippets; the metal policy fixture checks the generated shape.
**/
@:native("crate::native_tcp_tools::NativeTcp")
@:rustExtraSrc("rust/native/native_tcp_tools.rs")
extern class NativeTcp {
	public static function bind(addr:SocketAddr):Result<TcpListener, String>;
	public static function bindDetailed(addr:SocketAddr):Result<TcpListener, SocketError>;
	public static function bindLocalhost(port:Int):Result<TcpListener, String>;
	public static function bindLocalhostDetailed(port:Int):Result<TcpListener, SocketError>;
	public static function connect(addr:SocketAddr):Result<TcpStream, String>;
	public static function connectDetailed(addr:SocketAddr):Result<TcpStream, SocketError>;
	public static function connectLocalhost(port:Int):Result<TcpStream, String>;
	public static function connectLocalhostDetailed(port:Int):Result<TcpStream, SocketError>;
}
