package reflaxe.rust.analyze;

/**
	Package-wide application boundary for compiler and framework implementation helpers.

	Why
	- Haxe package names do not make a declaration private across modules.
	- The installed compiler must expose implementation types to its own macros and std overrides,
	  but application imports of those types would accidentally turn implementation details into API.
	- One canonical namespace policy keeps the compiler diagnostic and the generated public-surface
	  graph aligned as new helpers are added.

	What
	- `applicationInternalRoots` lists namespace roots that application source may not reference.
	- `applicationPublicExceptions` lists exact, deliberately public type/module paths inside an
	  otherwise internal root; every exception must receive an explicit non-internal compatibility
	  classification, and qualified member access below that path inherits the exception.
	- `isInternalPath(...)` recognizes both a root and every declaration below it.
	- Public Haxe/std and `rust.*` facades remain outside this policy even when their implementation
	  signatures resolve transitively to one of these helpers.

	How
	- `RustCompiler` scans only user-authored source spelling and reports the first matching path.
	- The compatibility-manifest guard reads this same declaration and proves that every type assigned
	  to the `internal-helper` contract is sealed by one of these roots, and vice versa.
	- Add a root here only when the entire namespace is framework-owned. Mixed public/internal
	  namespaces must use Haxe `private` declarations or move helpers under a dedicated internal root.
**/
class InternalHelperBoundary {
	public static final applicationInternalRoots:Array<String> = [
		"haxe.BoundaryTypes",
		"hxrt",
		"reflaxe.rust",
		"rust._internal"
	];

	public static final applicationPublicExceptions:Array<String> = [
		"reflaxe.rust.macros.RustInjection"
	];

	/**
		Reports whether a Haxe module/type path belongs to an application-internal namespace.

		Why
		- Exact-root checks alone would let fully qualified child declarations bypass the guard.

		What
		- Accepts the namespace root itself or a dot-delimited descendant.

		How
		- Requires a `.` boundary so lookalike public names such as `hxrt_tools` remain unaffected.
	**/
	public static function isInternalPath(modulePath:String):Bool {
		if (modulePath == null || modulePath.length == 0)
			return false;
		for (publicPath in applicationPublicExceptions) {
			if (modulePath == publicPath || StringTools.startsWith(modulePath, publicPath + "."))
				return false;
		}
		for (root in applicationInternalRoots) {
			if (modulePath == root || StringTools.startsWith(modulePath, root + "."))
				return true;
		}
		return false;
	}

	/**
		Finds direct application spellings of internal helper paths.

		Why
		- Followed Haxe types erase public typedef boundaries. A typed-usage-only guard would therefore
		  reject legitimate facade types whose private representation is an `hxrt` handle.
		- A raw substring scan would report examples in comments or ordinary string/regex literals.

		What
		- Returns canonical namespace/type paths beginning at an internal root.
		- Preserves imports, aliases, package declarations, type annotations, and value expressions.

		How
		- Replaces comment and literal contents with spaces while retaining code/newline layout.
		- Tokenizes canonical dotted paths while allowing insignificant whitespace/comments around dots.
		- Deduplicates and sorts deterministically for one stable diagnostic per path.
	**/
	public static function collectDirectReferences(source:String):Array<String> {
		var out:Array<String> = [];
		if (source == null || source.length == 0)
			return out;
		var code = maskCommentsAndLiterals(source);
		for (modulePath in collectQualifiedPaths(code)) {
			if (isInternalPath(modulePath) && !out.contains(modulePath))
				out.push(modulePath);
		}
		out.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		return out;
	}

	/**
		Extracts canonical dotted Haxe paths from masked application source.

		Why
		- Haxe permits whitespace or comments around `.` in a qualified path, so a raw contiguous
		  substring match is insufficient for enforcing the namespace boundary.
		- A lone local variable named `hxrt` is not a framework import and must remain legal.

		What
		- Returns paths containing at least two identifier segments.
		- Normalizes insignificant whitespace around dots while preserving identifier spelling.

		How
		- Tokenizes ASCII identifiers used by the canonical internal roots, then accepts another segment
		  only when an actual dot token separates it. Masked comments already appear as whitespace.
	**/
	static function collectQualifiedPaths(source:String):Array<String> {
		var out:Array<String> = [];
		var index = 0;
		while (index < source.length) {
			if (!isIdentifierStart(source.charAt(index))) {
				index++;
				continue;
			}

			var segmentEnd = index + 1;
			while (segmentEnd < source.length && isIdentifierChar(source.charAt(segmentEnd)))
				segmentEnd++;
			var segments = [source.substring(index, segmentEnd)];
			var cursor = segmentEnd;
			while (true) {
				var dotIndex = skipWhitespace(source, cursor);
				if (dotIndex >= source.length || source.charAt(dotIndex) != ".")
					break;
				var nextStart = skipWhitespace(source, dotIndex + 1);
				if (nextStart >= source.length || !isIdentifierStart(source.charAt(nextStart)))
					break;
				var nextEnd = nextStart + 1;
				while (nextEnd < source.length && isIdentifierChar(source.charAt(nextEnd)))
					nextEnd++;
				segments.push(source.substring(nextStart, nextEnd));
				cursor = nextEnd;
			}

			if (segments.length > 1)
				out.push(segments.join("."));
			index = cursor;
		}
		return out;
	}

	static function skipWhitespace(source:String, start:Int):Int {
		var index = start;
		while (index < source.length) {
			var character = source.charAt(index);
			if (character != " " && character != "\t" && character != "\r" && character != "\n")
				break;
			index++;
		}
		return index;
	}

	static function isIdentifierStart(character:String):Bool {
		if (character == null || character.length == 0)
			return false;
		var code = character.charCodeAt(0);
		return (code >= "a".code && code <= "z".code)
			|| (code >= "A".code && code <= "Z".code)
			|| character == "_";
	}

	static function isIdentifierChar(character:String):Bool {
		if (isIdentifierStart(character))
			return true;
		if (character == null || character.length == 0)
			return false;
		var code = character.charCodeAt(0);
		return code >= "0".code && code <= "9".code;
	}

	/**
		Masks non-code text before internal-helper path matching.

		Why
		- User comments and literal payloads may legitimately discuss compiler/runtime module paths.
		- Those words are not Haxe references and must not create a compatibility-boundary error.

		What
		- Handles line comments, block comments, single/double quoted strings, escapes, and Haxe regex
		  literals introduced by `~/`.
		- Preserves `${...}` interpolation expressions because Haxe types and executes those expressions;
		  only their surrounding literal payload is masked.

		How
		- Preserves newlines and replaces other masked bytes with spaces. Haxe remains the authority for
		  actual syntax and typing; this scanner owns only direct source-spelling policy.
	**/
	static function maskCommentsAndLiterals(source:String):String {
		var out = new StringBuf();
		var index = 0;
		var state = 0; // 0 code, 1 line comment, 2 block comment, 3 single quote, 4 double quote, 5 regex.
		var escaped = false;
		var interpolationDepths:Array<Int> = [];
		var interpolationStringStates:Array<Int> = [];
		while (index < source.length) {
			var current = source.charAt(index);
			var next = index + 1 < source.length ? source.charAt(index + 1) : "";
			if (state == 0) {
				if (interpolationDepths.length > 0 && current == "{") {
					var depthIndex = interpolationDepths.length - 1;
					interpolationDepths[depthIndex] = interpolationDepths[depthIndex] + 1;
					out.add(" ");
					index++;
					continue;
				}
				if (interpolationDepths.length > 0 && current == "}") {
					var depthIndex = interpolationDepths.length - 1;
					var nextDepth = interpolationDepths[depthIndex] - 1;
					out.add(" ");
					index++;
					if (nextDepth == 0) {
						interpolationDepths.pop();
						state = interpolationStringStates.pop();
						escaped = false;
					} else {
						interpolationDepths[depthIndex] = nextDepth;
					}
					continue;
				}
				if (current == "/" && next == "/") {
					out.add("  ");
					index += 2;
					state = 1;
					continue;
				}
				if (current == "/" && next == "*") {
					out.add("  ");
					index += 2;
					state = 2;
					continue;
				}
				if (current == "~" && next == "/") {
					out.add("  ");
					index += 2;
					state = 5;
					escaped = false;
					continue;
				}
				if (current == "'") {
					out.add(" ");
					index++;
					state = 3;
					escaped = false;
					continue;
				}
				if (current == "\"") {
					out.add(" ");
					index++;
					state = 4;
					escaped = false;
					continue;
				}
				out.add(current);
				index++;
				continue;
			}

			if (state == 1) {
				if (current == "\n") {
					out.add("\n");
					state = 0;
				} else {
					out.add(" ");
				}
				index++;
				continue;
			}

			if (state == 2) {
				if (current == "*" && next == "/") {
					out.add("  ");
					index += 2;
					state = 0;
				} else {
					out.add(current == "\n" ? "\n" : " ");
					index++;
				}
				continue;
			}

			if ((state == 3 || state == 4) && !escaped && current == "$" && next == "{") {
				out.add("  ");
				index += 2;
				interpolationDepths.push(1);
				interpolationStringStates.push(state);
				state = 0;
				continue;
			}

			out.add(current == "\n" ? "\n" : " ");
			if (escaped) {
				escaped = false;
			} else if (current == "\\") {
				escaped = true;
			} else if ((state == 3 && current == "'") || (state == 4 && current == "\"") || (state == 5 && current == "/")) {
				state = 0;
			}
			index++;
		}
		return out.toString();
	}
}
