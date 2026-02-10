package hxrt.ssl;

/**
	Opaque runtime certificate handle (`hxrt::ssl::Certificate`).

	Why
	- `sys.ssl.Certificate` is implemented in Haxe in `std/sys/ssl/Certificate.hx`, but the
	  certificate chain data and parsing helpers live in the Rust runtime (`hxrt::ssl`).

	What
	- An extern marker type used in typed signatures as `HxRef<CertificateHandle>`.

	How
	- The Rust backend maps `@:native("hxrt::ssl::Certificate")` to the real runtime type.
	- All operations are performed via target code injection in `std/sys/ssl/Certificate.hx`.
**/
@:native("hxrt::ssl::Certificate")
extern class CertificateHandle {}

