package hxrt.ssl;

/**
	Opaque runtime key handle (`hxrt::ssl::Key`).

	Why
	- `sys.ssl.Key` is implemented in Haxe in `std/sys/ssl/Key.hx`, but key parsing and cryptographic
	  operations live in the Rust runtime (`hxrt::ssl`).

	What
	- An extern marker type used in typed signatures as `HxRef<KeyHandle>`.

	How
	- The Rust backend maps `@:native("hxrt::ssl::Key")` to the real runtime type.
	- All operations are performed via target code injection in `std/sys/ssl/Key.hx` and
	  `std/sys/ssl/Digest.hx`.
**/
@:native("hxrt::ssl::Key")
extern class KeyHandle {}

