package sys.ssl;

import hxrt.ssl.CertificateHandle;
import rust.HxRef;

/**
	`sys.ssl.Certificate` (Rust target override)

	Why
	- `sys.ssl.Certificate` is the stdlib's representation for certificate chains used by TLS.
	- HTTPS support (`sys.Http` with `https://`) requires a way to load trust roots and inspect
	  peer certificates.

	What
	- A wrapper around a runtime certificate chain (`hxrt::ssl::Certificate`).
	- Exposes common inspection helpers (`commonName`, validity dates, subject/issuer fields).

	How
	- Certificates are stored as DER blobs in the runtime (leaf-first chain).
	- Parsing is best-effort via `x509-parser`. If parsing fails, getters return `null`/empty values.
**/
class Certificate {
	@:noCompletion
	@:dox(hide)
	public var handle(default, null): HxRef<CertificateHandle>;

	private function new(handle: HxRef<CertificateHandle>) {
		this.handle = handle;
	}

	@:noCompletion
	@:dox(hide)
	public function __hxrtHandle(): HxRef<CertificateHandle> {
		return handle;
	}

	@:allow(sys.ssl.Socket)
	private static function fromHandle(handle: HxRef<CertificateHandle>): Certificate {
		return new Certificate(handle);
	}

	public static function loadFile(file: String): Certificate {
		var h: HxRef<CertificateHandle> = untyped __rust__("hxrt::ssl::cert_load_file({0}.as_str())", file);
		return new Certificate(h);
	}

	public static function loadPath(path: String): Certificate {
		var h: HxRef<CertificateHandle> = untyped __rust__("hxrt::ssl::cert_load_path({0}.as_str())", path);
		return new Certificate(h);
	}

	public static function fromString(str: String): Certificate {
		var h: HxRef<CertificateHandle> = untyped __rust__("hxrt::ssl::cert_from_string({0}.as_str())", str);
		return new Certificate(h);
	}

	public static function loadDefaults(): Certificate {
		var h: HxRef<CertificateHandle> = untyped __rust__("hxrt::ssl::cert_load_defaults()");
		return new Certificate(h);
	}

	public var commonName(get, null): Null<String>;
	public var altNames(get, null): Array<String>;
	public var notBefore(get, null): Date;
	public var notAfter(get, null): Date;

	public function subject(field: String): Null<String> {
		return untyped __rust__("{0}.borrow().subject_field({1}.as_str())", handle, field);
	}

	public function issuer(field: String): Null<String> {
		return untyped __rust__("{0}.borrow().issuer_field({1}.as_str())", handle, field);
	}

	public function next(): Null<Certificate> {
		return untyped __rust__(
			"{
				match hxrt::ssl::cert_next(&{0}) {
					None => crate::HxRef::<crate::sys_ssl_certificate::Certificate>::null(),
					Some(h) => crate::sys_ssl_certificate::Certificate::from_handle(h),
				}
			}",
			handle
		);
	}

	public function add(pem: String): Void {
		untyped __rust__("hxrt::ssl::cert_add_pem(&{0}, {1}.as_str())", handle, pem);
	}

	public function addDER(der: haxe.io.Bytes): Void {
		untyped __rust__("hxrt::ssl::cert_add_der(&{0}, {1}.borrow().as_slice())", handle, der);
	}

	private function get_commonName(): Null<String> {
		return untyped __rust__("{0}.borrow().common_name()", handle);
	}

	private function get_altNames(): Array<String> {
		return untyped __rust__("hxrt::array::Array::<String>::from_vec({0}.borrow().alt_names())", handle);
	}

	private function get_notBefore(): Date {
		var ms: Float = untyped __rust__("{0}.borrow().not_before_ms() as f64", handle);
		return Date.fromTime(ms);
	}

	private function get_notAfter(): Date {
		var ms: Float = untyped __rust__("{0}.borrow().not_after_ms() as f64", handle);
		return Date.fromTime(ms);
	}
}
