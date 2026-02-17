package sys.net;

/**
	`sys.net` boundary value aliases (Rust target override)

	Why
	- Upstream `sys.net.Socket` exposes `custom:Dynamic` so app code can attach
	  arbitrary values and recover them after `Socket.select`.
	- We preserve that API while keeping backend implementation code explicit
	  about untyped boundaries.

	What
	- `SocketCustomValue`: value stored in `Socket.custom`.

	How
	- This alias maps to `Dynamic` to match upstream behavior.
	- Treat values as boundary payloads and validate/cast immediately where
	  concrete typing is required.
**/
typedef SocketCustomValue = Dynamic;
