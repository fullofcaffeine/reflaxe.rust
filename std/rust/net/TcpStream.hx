package rust.net;

import rust.Result;
import rust.Vec;

/**
	`rust.net.TcpStream`

	Why
	- A TCP stream is a native owner with read/write state; portable Haxe `Input` / `Output` wrappers
	  would import runtime semantics that the metal facade is intentionally avoiding.
	- Metal code also needs a byte-stream path that does not route through `haxe.io.Bytes` or a
	  broad runtime adapter just to move owned TCP payloads.

	What
	- A typed owner for the narrow blocking TCP stream facade.
	- `writeUtf8AndShutdownWrite(...)` writes one UTF-8 payload and shuts down only the write half,
	  allowing the peer to read to EOF while the caller may still read a response.
	- `readToString()` reads UTF-8 text until EOF.
	- `writeBytesAndShutdownWrite(...)` writes a `rust.Vec<Int>` as bytes after validating every
	  value is in `0...255`; `readBytes()` reads until EOF and returns owned `rust.Vec<Int>` bytes.
	- The `Detailed` variants return `SocketError`, including a distinct UTF-8 decode category for
	  `readToStringDetailed()` and invalid-input category for out-of-range byte values.

	How
	- The extern maps to `crate::native_tcp_tools::TcpStream`, a wrapper around
	  `std::net::TcpStream`.
	- Mutating methods are marked `@:rustMutating` so generated Rust owns the handle as `mut` only
	  where stream state actually changes.
	- This is not a line-oriented API, async stream, TLS stream, or portable socket replacement.
	  Portable byte-buffer semantics remain a separate runtime-backed stdlib contract.
**/
@:native("crate::native_tcp_tools::TcpStream")
@:rustExtraSrc("rust/native/native_tcp_tools.rs")
extern class TcpStream {
	@:rustMutating
	public function writeUtf8AndShutdownWrite(payload:String):Result<Bool, String>;

	@:rustMutating
	public function writeUtf8AndShutdownWriteDetailed(payload:String):Result<Bool, SocketError>;

	@:rustMutating
	public function writeBytesAndShutdownWrite(payload:Vec<Int>):Result<Bool, String>;

	@:rustMutating
	public function writeBytesAndShutdownWriteDetailed(payload:Vec<Int>):Result<Bool, SocketError>;

	@:rustMutating
	public function readToString():Result<String, String>;

	@:rustMutating
	public function readToStringDetailed():Result<String, SocketError>;

	@:rustMutating
	public function readBytes():Result<Vec<Int>, String>;

	@:rustMutating
	public function readBytesDetailed():Result<Vec<Int>, SocketError>;
}
