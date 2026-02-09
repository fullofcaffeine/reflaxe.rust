package hxrt.net;

/**
	Opaque runtime socket handle (`hxrt::net::SocketHandle`).

	Why
	- `sys.net.Socket` / `sys.net.UdpSocket` are implemented in Haxe in this repo's `std/` overrides,
	  but the actual OS resources (TCP/UDP sockets) live in the Rust runtime (`hxrt`).

	What
	- This type is an *extern marker* that lets the compiler refer to the runtime handle in typed
	  signatures (`HxRef<SocketHandle>`), without emitting any Haxe-level fields or methods.

	How
	- The Rust backend maps `@:native("hxrt::net::SocketHandle")` to the real Rust type.
	- All operations are performed via target code injection in `std/sys/net/Socket.hx` and
	  `std/sys/net/UdpSocket.hx`, which call methods on the borrowed handle.
**/
@:native("hxrt::net::SocketHandle")
extern class SocketHandle {}

