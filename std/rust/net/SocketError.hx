package rust.net;

/**
	`rust.net.SocketError`

	Why
	- The first Rust-native TCP/UDP facades returned `Result<..., String>` to keep the surface small
	  and source-compatible.
	- Callers that need recovery policy should not parse message text to distinguish invalid facade
	  inputs, Rust IO failures, and UTF-8 decode failures.
	- Metal/no-hxrt networking should stay on typed Rust-shaped values instead of exceptions,
	  `Dynamic`, portable `sys.net` handles, or app-side raw `std::net` snippets.

	What
	- Typed error record used by opt-in `Detailed` socket helpers.
	- `isInvalidInput()` covers facade contract failures such as out-of-range ports or non-positive
	  receive buffer sizes.
	- `isIo()` covers Rust `std::io::Error` paths from bind/connect/accept/read/write/send/receive.
	- `isUtf8()` covers byte-to-String decode failures from UTF-8 receive helpers.
	- `message()` returns human-readable detail for diagnostics; callers should branch on typed
	  predicates first and use the message only for reporting.

	How
	- The extern maps to `crate::native_socket_error_tools::SocketError`.
	- TCP and UDP helper modules map their native failures into this shared helper type.
	- In `metal + rust_no_hxrt`, this must remain a narrow Rust helper with no `hxrt`, `Dynamic`,
	  Haxe exception, or raw-snippet dependency.
**/
@:native("crate::native_socket_error_tools::SocketError")
@:rustExtraSrc("rust/native/native_socket_error_tools.rs")
extern class SocketError {
	public function message():String;
	public function isInvalidInput():Bool;
	public function isIo():Bool;
	public function isUtf8():Bool;
}
