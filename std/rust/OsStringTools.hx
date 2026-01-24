package rust;

/**
 * OsStringTools
 *
 * Framework helpers for `rust.OsString`.
 */
class OsStringTools {
	public static function fromString(s: String): OsString {
		return untyped __rust__("std::ffi::OsString::from({0})", s);
	}

	public static function toStringLossy(s: Ref<OsString>): String {
		return untyped __rust__(
			"({0}).as_os_str().to_string_lossy().to_string()",
			s
		);
	}
}
