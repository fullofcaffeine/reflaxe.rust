package sys.ssl;

import hxrt.ssl.KeyHandle;
import rust.HxRef;

/**
	`sys.ssl.Key` (Rust target override)

	Why
	- The upstream stdlib declares `sys.ssl.Key` as `extern`, but `sys.ssl.Digest` and
	  `sys.ssl.Socket` need a concrete key representation on sys targets.

	What
	- A wrapper around a runtime key handle (`hxrt::ssl::Key`).
	- Supports loading RSA keys from PEM/DER for digest signing and (future) client-auth TLS.

	How
	- Keys live in the Rust runtime and are referenced from Haxe as `HxRef<KeyHandle>`.
	- The optional `pass` argument is accepted for API parity, but is currently ignored.

	Design note
	- `handle` is `public` (but hidden from docs/completions) so sibling std classes like
	  `sys.ssl.Digest` can access it without relying on backend-specific "friend" access rules.
**/
class Key {
	@:noCompletion
	@:dox(hide)
	public var handle(default, null):HxRef<KeyHandle>;

	private function new(handle:HxRef<KeyHandle>) {
		this.handle = handle;
	}

	public static function loadFile(file:String, ?isPublic:Bool, ?_pass:String):Key {
		var pub:Bool = isPublic == true;
		var h:HxRef<KeyHandle> = untyped __rust__("hxrt::ssl::key_load_file({0}.as_str(), {1} as bool)", file, pub);
		return new Key(h);
	}

	public static function readPEM(data:String, isPublic:Bool, ?_pass:String):Key {
		var h:HxRef<KeyHandle> = untyped __rust__("hxrt::ssl::key_read_pem({0}.as_str(), {1} as bool)", data, isPublic);
		return new Key(h);
	}

	public static function readDER(data:haxe.io.Bytes, isPublic:Bool):Key {
		var h:HxRef<KeyHandle> = untyped __rust__("hxrt::ssl::key_read_der({0}.borrow().as_slice(), {1} as bool)", data, isPublic);
		return new Key(h);
	}
}
