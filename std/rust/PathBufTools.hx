package rust;

/**
 * PathBufTools
 *
 * Framework helpers for `rust.PathBuf`.
 *
 * IMPORTANT: Keep these as regular (non-inline) functions so `__rust__` stays inside
 * framework code and does not get inlined into application code.
 */
class PathBufTools {
	public static function fromString(s: String): PathBuf {
		return untyped __rust__("std::path::PathBuf::from({0})", s);
	}

	public static function join(p: Ref<PathBuf>, child: String): PathBuf {
		return untyped __rust__("({0}).join({1}.as_str())", p, child);
	}

	public static function push(p: Ref<PathBuf>, child: String): PathBuf {
		return untyped __rust__(
			"{ let mut __p = ({0}).clone(); __p.push({1}.as_str()); __p }",
			p,
			child
		);
	}

	public static function toStringLossy(p: Ref<PathBuf>): String {
		return untyped __rust__(
			"({0}).as_path().to_string_lossy().to_string()",
			p
		);
	}

	public static function fileName(p: Ref<PathBuf>): Option<String> {
		return untyped __rust__(
			"({0}).file_name().map(|s| s.to_string_lossy().to_string())",
			p
		);
	}
}
