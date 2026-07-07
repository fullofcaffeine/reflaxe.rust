package rust.net;

import rust.Result;

/**
	`rust.net.TcpStream`

	Why
	- A TCP stream is a native owner with read/write state; portable Haxe `Input` / `Output` wrappers
	  would import runtime semantics that the metal facade is intentionally avoiding.
	- The first socket slice needs only a deterministic UTF-8 round trip, not a reusable streaming
	  abstraction.

	What
	- A typed owner for the narrow M55 blocking TCP stream facade.
	- `writeUtf8AndShutdownWrite(...)` writes one UTF-8 payload and shuts down only the write half,
	  allowing the peer to read to EOF while the caller may still read a response.
	- `readToString()` reads UTF-8 text until EOF.

	How
	- The extern maps to `crate::native_tcp_tools::TcpStream`, a wrapper around
	  `std::net::TcpStream`.
	- Mutating methods are marked `@:rustMutating` so generated Rust owns the handle as `mut` only
	  where stream state actually changes.
	- This is not a line-oriented API, byte-buffer API, async stream, TLS stream, or portable socket
	  replacement.
**/
@:native("crate::native_tcp_tools::TcpStream")
@:rustExtraSrc("rust/native/native_tcp_tools.rs")
extern class TcpStream {
	@:rustMutating
	public function writeUtf8AndShutdownWrite(payload:String):Result<Bool, String>;

	@:rustMutating
	public function readToString():Result<String, String>;
}
