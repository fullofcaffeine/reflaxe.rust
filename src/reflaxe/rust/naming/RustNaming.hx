package reflaxe.rust.naming;

/**
 * RustNaming
 *
 * Centralizes Rust identifier rules (snake_case + keyword escaping + basic collisions).
 *
 * Keep this deterministic: same input -> same output within a compilation.
 */
class RustNaming {
	// Rust keywords (2021 edition + reserved-for-future-use words).
	static final RUST_KEYWORDS:Map<String, Bool> = [
		"as" => true,
		"break" => true,
		"box" => true,
		"const" => true,
		"continue" => true,
		"crate" => true,
		"else" => true,
		"enum" => true,
		"extern" => true,
		"false" => true,
		"fn" => true,
		"for" => true,
		"if" => true,
		"impl" => true,
		"in" => true,
		"let" => true,
		"loop" => true,
		"match" => true,
		"mod" => true,
		"move" => true,
		"mut" => true,
		"pub" => true,
		"ref" => true,
		"return" => true,
		"self" => true,
		"Self" => true,
		"static" => true,
		"struct" => true,
		"super" => true,
		"trait" => true,
		"true" => true,
		"type" => true,
		"unsafe" => true,
		"use" => true,
		"where" => true,
		"while" => true,
		"async" => true,
		"await" => true,
		"dyn" => true,
		// Reserved keywords not currently used in stable syntax, but still reserved in Rust 2021.
		"abstract" => true,
		"become" => true,
		"do" => true,
		"final" => true,
		"macro" => true,
		"override" => true,
		"priv" => true,
		"try" => true,
		"typeof" => true,
		"unsized" => true,
		"virtual" => true,
		"yield" => true,
	];

	// These are legal Rust identifiers but are reserved by this backend's source-name allocator.
	static final CODEGEN_RESERVED_NAMES:Map<String, Bool> = [
		// Not keywords, but reserved in this codegen to avoid shadowing common Rust crates.
		"std" => true,
		"core" => true,
		"alloc" => true,
	];

	/**
		Reports whether a token is a real Rust 2021 keyword.

		Why
		- Structural Rust IR must reject a keyword as a normal identifier while still accepting legal
		  path segments such as `std`, `core`, and `alloc`.
		- The source-name allocator additionally reserves those crate names, so its older `isKeyword`
		  contract is intentionally broader than Rust's grammar.

		What
		- Returns true only for strict, edition, or reserved-for-future-use Rust 2021 keywords.

		How
		- `RustIdentifier` uses this grammar-level query.
		- Existing name allocation continues to use `isKeyword`, preserving its collision policy.
	**/
	public static function isRustKeyword(name:String):Bool {
		return RUST_KEYWORDS.exists(name);
	}

	public static function isKeyword(name:String):Bool {
		return RUST_KEYWORDS.exists(name) || CODEGEN_RESERVED_NAMES.exists(name);
	}

	public static function isValidIdent(name:String):Bool {
		return ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(name);
	}

	public static function escapeKeyword(name:String):String {
		return isKeyword(name) ? (name + "_") : name;
	}

	/**
	 * Best-effort identifier sanitization:
	 * - invalid chars -> `_`
	 * - leading digit -> `_` prefix
	 * - collapse consecutive `_`
	 */
	public static function sanitizeIdent(name:String):String {
		if (name == null || name.length == 0)
			return "_";

		var out = new StringBuf();
		var prevUnderscore = false;
		for (i in 0...name.length) {
			var ch = name.charAt(i);
			var ok = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch == "_";
			var c = ok ? ch : "_";
			if (c == "_") {
				if (prevUnderscore)
					continue;
				prevUnderscore = true;
				out.add("_");
			} else {
				prevUnderscore = false;
				out.add(c);
			}
		}

		var s = out.toString();
		if (s.length == 0)
			s = "_";
		var first = s.charAt(0);
		if (first >= "0" && first <= "9")
			s = "_" + s;
		return s;
	}

	/**
	 * Converts `CamelCase` / `mixedCase` / `URLValue` to `snake_case`.
	 * Keeps existing underscores intact.
	 */
	public static function toSnakeCase(name:String):String {
		if (name == null || name.length == 0)
			return "";

		var out = new StringBuf();
		for (i in 0...name.length) {
			var ch = name.charAt(i);
			var lower = ch.toLowerCase();
			var isUpper = (ch != lower) && (ch >= "A" && ch <= "Z");

			if (isUpper && i > 0) {
				var prev = name.charAt(i - 1);
				var prevIsLowerOrDigit = ((prev >= "a" && prev <= "z") || (prev >= "0" && prev <= "9"));
				var nextIsLower = false;
				if (i + 1 < name.length) {
					var next = name.charAt(i + 1);
					nextIsLower = (next >= "a" && next <= "z");
				}
				// "fooBar" -> foo_bar, "URLValue" -> url_value
				if (prevIsLowerOrDigit || nextIsLower)
					out.add("_");
			}

			out.add(lower);
		}

		return out.toString();
	}

	public static function snakeIdent(name:String):String {
		return escapeKeyword(sanitizeIdent(toSnakeCase(name)));
	}

	/**
	 * Converts an arbitrary identifier into a Rust type identifier (UpperCamelCase).
	 *
	 * Why
	 * - Rust lints warn on non-CamelCase type names (`non_camel_case_types`).
	 * - Haxe can generate synthetic type names containing underscores (e.g. `Foo_Impl_` for
	 *   abstract implementation classes). Those should still become idiomatic Rust types.
	 *
	 * What
	 * - Sanitizes invalid characters and leading digits.
	 * - Splits on `_` and concatenates segments using UpperCamelCase.
	 * - Escapes Rust keywords (best-effort; primarily relevant for `Self`).
	 *
	 * How
	 * - We do not try to "re-case" already-camel segments (e.g. `URLValue` stays `URLValue`).
	 * - Empty segments are ignored, so `Foo__Bar_` becomes `FooBar`.
	 */
	public static function typeIdent(name:String):String {
		var sanitized = sanitizeIdent(name);
		var parts = sanitized.split("_");
		var out = new StringBuf();

		for (p in parts) {
			if (p == null || p.length == 0)
				continue;
			out.add(p.charAt(0).toUpperCase());
			if (p.length > 1)
				out.add(p.substr(1));
		}

		var s = out.toString();
		if (s.length == 0)
			s = "_";
		return escapeKeyword(s);
	}

	public static function stableUnique(base:String, used:Map<String, Bool>):String {
		var name = base;
		if (!used.exists(name)) {
			used.set(name, true);
			return name;
		}
		var i = 2;
		var sep = StringTools.endsWith(name, "_") ? "" : "_";
		while (true) {
			var candidate = name + sep + i;
			if (!used.exists(candidate)) {
				used.set(candidate, true);
				return candidate;
			}
			i++;
		}
	}
}
