package reflaxe.rust.naming;

/**
 * RustNaming
 *
 * Centralizes Rust identifier rules (snake_case + keyword escaping + basic collisions).
 *
 * Keep this deterministic: same input -> same output within a compilation.
 */
class RustNaming {
	// Rust keywords (2021 edition + reserved).
	static final KEYWORDS: Map<String, Bool> = [
		"as" => true, "break" => true, "const" => true, "continue" => true, "crate" => true, "else" => true, "enum" => true, "extern" => true,
		"false" => true, "fn" => true, "for" => true, "if" => true, "impl" => true, "in" => true, "let" => true, "loop" => true, "match" => true,
		"mod" => true, "move" => true, "mut" => true, "pub" => true, "ref" => true, "return" => true, "self" => true, "Self" => true, "static" => true,
		"struct" => true, "super" => true, "trait" => true, "true" => true, "type" => true, "unsafe" => true, "use" => true, "where" => true, "while" => true,
		"async" => true, "await" => true, "dyn" => true,
		// Not keywords, but reserved in this codegen to avoid shadowing common Rust crates.
		"std" => true, "core" => true, "alloc" => true,
	];

	public static function isKeyword(name: String): Bool {
		return KEYWORDS.exists(name);
	}

	public static function isValidIdent(name: String): Bool {
		return ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(name);
	}

	public static function escapeKeyword(name: String): String {
		return isKeyword(name) ? (name + "_") : name;
	}

	/**
	 * Best-effort identifier sanitization:
	 * - invalid chars -> `_`
	 * - leading digit -> `_` prefix
	 * - collapse consecutive `_`
	 */
	public static function sanitizeIdent(name: String): String {
		if (name == null || name.length == 0) return "_";

		var out = new StringBuf();
		var prevUnderscore = false;
		for (i in 0...name.length) {
			var ch = name.charAt(i);
			var ok = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch == "_";
			var c = ok ? ch : "_";
			if (c == "_") {
				if (prevUnderscore) continue;
				prevUnderscore = true;
				out.add("_");
			} else {
				prevUnderscore = false;
				out.add(c);
			}
		}

		var s = out.toString();
		if (s.length == 0) s = "_";
		var first = s.charAt(0);
		if (first >= "0" && first <= "9") s = "_" + s;
		return s;
	}

	/**
	 * Converts `CamelCase` / `mixedCase` / `URLValue` to `snake_case`.
	 * Keeps existing underscores intact.
	 */
	public static function toSnakeCase(name: String): String {
		if (name == null || name.length == 0) return "";

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
				if (prevIsLowerOrDigit || nextIsLower) out.add("_");
			}

			out.add(lower);
		}

		return out.toString();
	}

	public static function snakeIdent(name: String): String {
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
	public static function typeIdent(name: String): String {
		var sanitized = sanitizeIdent(name);
		var parts = sanitized.split("_");
		var out = new StringBuf();

		for (p in parts) {
			if (p == null || p.length == 0) continue;
			out.add(p.charAt(0).toUpperCase());
			if (p.length > 1) out.add(p.substr(1));
		}

		var s = out.toString();
		if (s.length == 0) s = "_";
		return escapeKeyword(s);
	}

	public static function stableUnique(base: String, used: Map<String, Bool>): String {
		var name = base;
		if (!used.exists(name)) {
			used.set(name, true);
			return name;
		}
		var i = 2;
		while (true) {
			var candidate = name + "_" + i;
			if (!used.exists(candidate)) {
				used.set(candidate, true);
				return candidate;
			}
			i++;
		}
	}
}
