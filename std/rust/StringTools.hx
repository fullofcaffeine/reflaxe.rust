package rust;

/**
 * rust.StringTools
 *
 * Minimal string helpers for the `rusty` profile.
 *
 * IMPORTANT: Keep these non-inline so `__rust__` stays in framework code.
 */
class StringTools {
	public static function contains(haystack: Ref<String>, needle: Str): Bool {
		return untyped __rust__("{0}.contains({1})", haystack, needle);
	}
}

