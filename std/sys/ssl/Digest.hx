package sys.ssl;

import hxrt.ssl.KeyHandle;
import rust.HxRef;

/**
	`sys.ssl.Digest` (Rust target override)

	Why
	- The upstream stdlib exposes digest and signature helpers under `sys.ssl.Digest`.
	- These are commonly used for hashing, and occasionally for signing/verifying payloads.

	What
	- `make(data, alg)` returns the hash digest as `haxe.io.Bytes`.
	- `sign` is implemented for RSA keys using PKCS#1 v1.5 with SHA256/SHA384/SHA512 digests.
	- `verify` supports SHA1 (legacy) and SHA256/SHA384/SHA512 (RSA PKCS#1 v1.5).

	How
	- Delegates to `hxrt::ssl::{digest_make,digest_sign,digest_verify}`.
	- Note: algorithms like MD5/RIPEMD160 are supported for `make`, but not for RSA sign/verify
	  in the current runtime (throws for `sign`, returns `false` for `verify`).
	- Note: for security, SHA1/SHA224 signing are intentionally not exposed.
**/
class Digest {
	public static function make(data: haxe.io.Bytes, alg: DigestAlgorithm): haxe.io.Bytes {
		return untyped __rust__("hxrt::ssl::digest_make({0}.borrow().as_slice(), {1}.as_str())", data, alg);
	}

	public static function sign(data: haxe.io.Bytes, privKey: Key, alg: DigestAlgorithm): haxe.io.Bytes {
		return untyped __rust__(
			"hxrt::ssl::digest_sign({0}.borrow().as_slice(), &{1}, {2}.as_str())",
			data,
			untyped privKey.handle,
			alg
		);
	}

	public static function verify(data: haxe.io.Bytes, signature: haxe.io.Bytes, pubKey: Key, alg: DigestAlgorithm): Bool {
		return untyped __rust__(
			"hxrt::ssl::digest_verify({0}.borrow().as_slice(), {1}.borrow().as_slice(), &{2}, {3}.as_str())",
			data,
			signature,
			untyped pubKey.handle,
			alg
		);
	}
}
