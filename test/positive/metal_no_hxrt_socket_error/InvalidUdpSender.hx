import rust.Result;

/**
	`InvalidUdpSender`

	Why
	- The public UDP facade intentionally sends UTF-8 strings in the current socket slice.
	- The typed `SocketError` contract still needs deterministic proof that `recvUtf8Detailed(...)`
	  maps invalid datagram bytes into the UTF-8 category.

	What
	- A tiny test-only extern island that sends one invalid UTF-8 datagram to localhost.
	- This keeps the product API clean until a real Rust-native byte-buffer datagram surface is
	  designed.

	How
	- The Haxe fixture calls a typed extern method, not app-side raw Rust.
	- The helper returns `Result<Int, String>` because this fixture only uses it to place bytes on
	  the wire; the product error category under test is produced by `UdpSocket.recvUtf8Detailed`.
**/
@:native("crate::invalid_udp_sender::InvalidUdpSender")
@:rustExtraSrc("native/invalid_udp_sender.rs")
extern class InvalidUdpSender {
	public static function sendInvalidUtf8ToLocalhost(port:Int):Result<Int, String>;
}
