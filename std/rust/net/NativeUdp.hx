package rust.net;

import rust.Result;

/**
	`rust.net.NativeUdp`

	Why
	- Portable `sys.net.UdpSocket`-style behavior belongs on the runtime-backed `sys.*` path when
	  Haxe compatibility, platform abstraction, and portable error behavior matter.
	- Metal code sometimes needs the narrower Rust contract: explicit blocking UDP over localhost,
	  direct `std::net::UdpSocket` ownership, and no portable socket/runtime behavior.
	- A typed facade keeps app code away from raw `std::net` snippets while giving no-hxrt policy
	  checks one stable helper shape to inspect.

	What
	- First M56 Rust-native UDP entry point.
	- `bindLocalhost(port)` binds `127.0.0.1:<port>` and returns a typed `UdpSocket`; passing `0`
	  asks the OS for an ephemeral port.
	- `bindLocalhostDetailed(...)` keeps the same bind behavior but returns `SocketError` so callers
	  can distinguish invalid port values from Rust IO failures without parsing message text.
	- This is intentionally not portable `sys.net` parity, not TCP, not TLS, not async networking,
	  and not a general host/address API yet.

	How
	- `@:native("crate::native_udp_tools::NativeUdp")` binds to a small Rust helper module.
	- `@:rustExtraSrc("rust/native/native_udp_tools.rs")` copies that helper into generated crates.
	- The helper owns `std::net::UdpSocket` wrapper structs and returns `rust.Result<..., String>`
	  so callers stay in explicit Rust-style error handling.
	- In `metal + rust_no_hxrt`, this surface must remain free of `hxrt`, `Dynamic`, Haxe `Array`,
	  and app-side raw Rust snippets; the metal policy fixture checks the generated shape.
**/
@:native("crate::native_udp_tools::NativeUdp")
@:rustExtraSrc("rust/native/native_udp_tools.rs")
extern class NativeUdp {
	public static function bindLocalhost(port:Int):Result<UdpSocket, String>;
	public static function bindLocalhostDetailed(port:Int):Result<UdpSocket, SocketError>;
}
