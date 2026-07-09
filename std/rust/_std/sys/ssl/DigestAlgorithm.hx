package sys.ssl;

/**
	`sys.ssl.DigestAlgorithm` (Rust target override)

	Why
	- `sys.ssl.Digest` takes a `DigestAlgorithm` value to select a hash/signature algorithm.
	- Keeping this type identical to upstream Haxe makes `sys.ssl.*` callsites portable.

	What
	- A string-backed enum abstract whose values match the upstream names.

	How
	- The Rust runtime (`hxrt::ssl`) matches on these strings.
**/
enum abstract DigestAlgorithm(String) to String {
	var MD5 = "MD5";
	var SHA1 = "SHA1";
	var SHA224 = "SHA224";
	var SHA256 = "SHA256";
	var SHA384 = "SHA384";
	var SHA512 = "SHA512";
	var RIPEMD160 = "RIPEMD160";
}
