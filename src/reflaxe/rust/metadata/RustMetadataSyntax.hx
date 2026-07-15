package reflaxe.rust.metadata;

import reflaxe.rust.ast.RustAST.RustConstArgument;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameter;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustIdentifier;
import reflaxe.rust.ast.RustAST.RustLifetime;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathRoot;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustTraitBoundModifier;
import reflaxe.rust.ast.RustAST.RustTraitObject;
import reflaxe.rust.ast.RustAST.RustType;

/**
	Parses the deliberately string-shaped `@:rustGeneric` and `@:rustReturn` metadata boundary.

	Why
	- Those stable metadata APIs necessarily arrive as target-syntax strings, but keeping the strings
	  inside declaration/type IR would make every later compiler pass parse printer output.
	- Compiler-owned paths must still be built from typed segments directly; this adapter exists only
	  for explicit metadata authority.

	What
	- Converts the admitted Rust type, path, trait-bound, lifetime, const-argument, and generic
	  declaration grammar into the same structural IR used by ordinary lowering.
	- Rejects unsupported syntax at this one boundary instead of falling back to an opaque type node.

	How
	- Call `parseGenericParameters` for one metadata string (which may contain comma-separated
	  declarations), `parseGenericParameterFragments` for metadata arrays, and `parseType` for
	  `@:rustReturn`.
	- Never feed compiler-rendered Rust back into this parser. Compiler lowering already owns typed
	  Haxe information and must construct nodes directly.
**/
class RustMetadataSyntax {
	/**
		Parses one metadata-owned Rust type into `RustType`.

		Why / What / How
		- `@:rustReturn` is intentionally a textual target boundary, but downstream lowering must remain
		  typed. This method consumes the complete string, rejects trailing or unsupported syntax, and
		  returns only structural nodes; compiler-rendered types must never be passed here.
	**/
	public static function parseType(code:String):RustType {
		var parser = new RustMetadataSyntaxParser(code);
		var result = parser.parseType();
		parser.requireEnd();
		return result;
	}

	/**
		Parses one metadata-owned nominal or qualified Rust path.

		Why / What / How
		- Extern metadata may name absolute, crate, self, super, type-`Self`, or qualified paths. Parse
		  that authority exactly once, then attach Haxe-derived generic arguments structurally rather
		  than concatenating target syntax in compiler lowering.
	**/
	public static function parsePath(code:String):RustPath {
		var parser = new RustMetadataSyntaxParser(code);
		var result = parser.parsePath();
		parser.requireEnd();
		return result;
	}

	/**
		Parses a comma-separated `@:rustGeneric` declaration list.

		Why / What / How
		- Lifetimes, type bounds, defaults, and const parameters affect Rust ownership and validity.
		  This method preserves each role in `RustGenericParameters`, whose constructor validates Rust
		  ordering and duplicate-name rules before a declaration reaches the printer.
	**/
	public static function parseGenericParameters(code:String):RustGenericParameters {
		var parser = new RustMetadataSyntaxParser(code);
		var result = parser.parseGenericParameters();
		parser.requireEnd();
		return result;
	}

	/**
		Combines the array form of `@:rustGeneric` without weakening its grammar.

		Why / What / How
		- Haxe metadata permits one declaration string or an array of declaration fragments. Joining the
		  fragments at this boundary routes both forms through the same parser and validation contract.
	**/
	public static function parseGenericParameterFragments(fragments:Array<String>):RustGenericParameters {
		if (fragments == null)
			throw "Rust metadata generic fragments cannot be null";
		return parseGenericParameters(fragments.join(", "));
	}
}

/**
	Cursor parser for the closed Rust metadata grammar admitted by `RustMetadataSyntax`.

	Why
	- A general Rust parser would add a large dependency and admit syntax the structural IR cannot
	  traverse. Scattered string splitting would mishandle nested generics, tuples, arrays, function
	  traits, qualified paths, and lifetimes.

	What
	- Implements only the closed forms represented by `RustType`, `RustPath`, generic declarations,
	  trait bounds, lifetimes, and const arguments. Unsupported tokens fail with a stable source offset.

	How
	- Recursive descent owns delimiter nesting; structural AST factories remain the final validators.
	- The class is private so application/compiler callers can enter only through the complete-input
	  methods above and cannot observe or resume a partially consumed parse.
**/
private class RustMetadataSyntaxParser {
	final source:String;
	var index:Int = 0;

	public function new(source:String) {
		if (source == null)
			throw "Rust metadata syntax cannot be null";
		this.source = source;
	}

	public function requireEnd():Void {
		skipWhitespace();
		if (index != source.length)
			fail('Unexpected `${source.charAt(index)}`');
	}

	public function parseGenericParameters():RustGenericParameters {
		skipWhitespace();
		if (index == source.length)
			return RustGenericParameters.empty();
		var parameters:Array<RustGenericParameter> = [];
		while (true) {
			parameters.push(parseGenericParameter());
			skipWhitespace();
			if (!consume(","))
				break;
			skipWhitespace();
			if (index == source.length)
				fail("Trailing comma is not admitted in Rust metadata generic declarations");
		}
		return RustGenericParameters.of(parameters);
	}

	function parseGenericParameter():RustGenericParameter {
		skipWhitespace();
		if (peek("'")) {
			var lifetime = parseLifetime();
			if (!lifetime.isNamed() || lifetime.name == null)
				fail("Rust lifetime parameter declarations require a named lifetime");
			var bounds:Array<RustLifetime> = [];
			skipWhitespace();
			if (consume(":")) {
				do {
					bounds.push(parseLifetime());
					skipWhitespace();
				} while (consume("+"));
			}
			return GenericLifetimeParam(lifetime.name, bounds);
		}

		if (consumeKeyword("const")) {
			var constName = parseIdentifier();
			require(":");
			var constType = parseType();
			var defaultValue:Null<RustConstArgument> = null;
			skipWhitespace();
			if (consume("="))
				defaultValue = parseConstArgument();
			return GenericConstParam(constName, constType, defaultValue);
		}

		var name = parseIdentifier();
		var bounds:Array<RustGenericBound> = [];
		skipWhitespace();
		if (consume(":")) {
			do {
				bounds.push(parseGenericBound());
				skipWhitespace();
			} while (consume("+"));
		}
		var defaultType:Null<RustType> = null;
		skipWhitespace();
		if (consume("="))
			defaultType = parseType();
		return GenericTypeParam(name, bounds, defaultType);
	}

	function parseGenericBound():RustGenericBound {
		skipWhitespace();
		if (peek("'"))
			return GenericLifetimeBound(parseLifetime());
		var modifier = consume("?") ? TraitBoundOptional : TraitBoundRequired;
		return GenericTraitBound(parsePath(), modifier);
	}

	public function parseType():RustType {
		skipWhitespace();
		if (consume("&")) {
			skipWhitespace();
			var lifetime:Null<RustLifetime> = peek("'") ? parseLifetime() : null;
			var mutable = consumeKeyword("mut");
			return RBorrow(parseType(), mutable, lifetime);
		}

		if (consume("(")) {
			skipWhitespace();
			if (consume(")"))
				return RUnit;
			var elements:Array<RustType> = [parseType()];
			skipWhitespace();
			if (!consume(",")) {
				require(")");
				return elements[0];
			}
			skipWhitespace();
			while (!consume(")")) {
				elements.push(parseType());
				skipWhitespace();
				if (!consume(",")) {
					require(")");
					break;
				}
				skipWhitespace();
			}
			return RTuple(elements);
		}

		if (consume("[")) {
			var element = parseType();
			skipWhitespace();
			if (consume(";")) {
				var length = parseConstArgument();
				require("]");
				return RArray(element, length);
			}
			require("]");
			return RSlice(element);
		}

		if (consumeKeyword("dyn")) {
			var bounds:Array<RustGenericBound> = [parseGenericBound()];
			skipWhitespace();
			while (consume("+")) {
				bounds.push(parseGenericBound());
				skipWhitespace();
			}
			return RTraitObject(RustTraitObject.of(bounds));
		}

		if (peek("<"))
			return RNamed(parseQualifiedPath());
		return RNamed(parsePath());
	}

	function parseQualifiedPath():RustPath {
		require("<");
		var selfType = parseType();
		var traitPath:Null<RustPath> = null;
		if (consumeKeyword("as"))
			traitPath = parsePath();
		require(">");
		require("::");
		return RustPath.qualified(selfType, traitPath, parsePathSegments());
	}

	public function parsePath():RustPath {
		skipWhitespace();
		if (consume("::"))
			return RustPath.absolute(parsePathSegments());

		var saved = index;
		var first = parseIdentifierToken();
		if (first.name == "crate" && !first.isRaw && consume("::"))
			return RustPath.cratePath(parsePathSegments());
		if (first.name == "self" && !first.isRaw && consume("::"))
			return RustPath.selfModule(parsePathSegments());
		if (first.name == "Self" && !first.isRaw) {
			if (consume("::"))
				return RustPath.typeSelf(parsePathSegments());
			return RustPath.typeSelf([]);
		}
		if (first.name == "super" && !first.isRaw && consume("::")) {
			var depth = 1;
			while (true) {
				var before = index;
				var token = tryParseIdentifierToken();
				if (token != null && token.name == "super" && !token.isRaw && consume("::")) {
					depth++;
					continue;
				}
				index = before;
				break;
			}
			return RustPath.superPath(depth, parsePathSegments());
		}

		index = saved;
		return RustPath.relative(parsePathSegments());
	}

	function parsePathSegments():Array<RustPathSegment> {
		var segments:Array<RustPathSegment> = [parsePathSegment()];
		while (true) {
			skipWhitespace();
			if (!consume("::"))
				break;
			segments.push(parsePathSegment());
		}
		return segments;
	}

	function parsePathSegment():RustPathSegment {
		var identifier = parseIdentifier();
		skipWhitespace();
		if (consume("<")) {
			var arguments:Array<RustGenericArgument> = [];
			do {
				arguments.push(parseGenericArgument());
				skipWhitespace();
			} while (consume(","));
			require(">");
			return RustPathSegment.angleIdentifier(identifier, arguments);
		}
		if (consume("(")) {
			var inputs:Array<RustType> = [];
			skipWhitespace();
			if (!consume(")")) {
				do {
					inputs.push(parseType());
					skipWhitespace();
				} while (consume(","));
				require(")");
			}
			var output:Null<RustType> = null;
			skipWhitespace();
			if (consume("->"))
				output = parseType();
			return RustPathSegment.parenthesized(identifier.name, inputs, output);
		}
		return RustPathSegment.plainIdentifier(identifier);
	}

	function parseGenericArgument():RustGenericArgument {
		skipWhitespace();
		if (peek("'"))
			return GenericLifetime(parseLifetime());
		if (isDigit(peekChar()) || matchesKeyword("true") || matchesKeyword("false"))
			return GenericConst(parseConstArgument());
		return GenericType(parseType());
	}

	function parseConstArgument():RustConstArgument {
		skipWhitespace();
		if (consumeKeyword("true"))
			return RustConstArgument.boolean(true);
		if (consumeKeyword("false"))
			return RustConstArgument.boolean(false);
		if (isDigit(peekChar())) {
			var start = index;
			while (isDigit(peekChar()))
				index++;
			return RustConstArgument.decimalInteger(source.substring(start, index));
		}
		return RustConstArgument.path(parsePath());
	}

	function parseLifetime():RustLifetime {
		require("'");
		if (consume("_"))
			return RustLifetime.inferred();
		var token = parseIdentifierToken();
		if (!token.isRaw && token.name == "static")
			return RustLifetime.staticLifetime();
		if (token.isRaw)
			fail("Rust lifetime names cannot be raw identifiers");
		return RustLifetime.named(token.name);
	}

	function parseIdentifier():RustIdentifier {
		var token = parseIdentifierToken();
		return token.isRaw ? RustIdentifier.raw(token.name) : RustIdentifier.named(token.name);
	}

	function tryParseIdentifierToken():Null<{name:String, isRaw:Bool}> {
		skipWhitespace();
		if (!isIdentifierStartAt(index) && !peek("r#"))
			return null;
		return parseIdentifierToken();
	}

	function parseIdentifierToken():{name:String, isRaw:Bool} {
		skipWhitespace();
		var isRaw = consume("r#");
		if (!isIdentifierStartAt(index))
			fail("Expected a Rust identifier");
		var start = index++;
		while (isIdentifierContinueAt(index))
			index++;
		return {name: source.substring(start, index), isRaw: isRaw};
	}

	function require(token:String):Void {
		skipWhitespace();
		if (!consume(token))
			fail('Expected `$token`');
	}

	function consumeKeyword(keyword:String):Bool {
		skipWhitespace();
		if (!matchesKeyword(keyword))
			return false;
		index += keyword.length;
		skipWhitespace();
		return true;
	}

	function matchesKeyword(keyword:String):Bool {
		if (!peek(keyword))
			return false;
		return !isIdentifierContinueAt(index + keyword.length);
	}

	function consume(token:String):Bool {
		skipWhitespace();
		if (!peek(token))
			return false;
		index += token.length;
		skipWhitespace();
		return true;
	}

	function peek(token:String):Bool {
		return source.substr(index, token.length) == token;
	}

	function peekChar():String {
		return index < source.length ? source.charAt(index) : "";
	}

	function skipWhitespace():Void {
		while (index < source.length) {
			var code = source.charCodeAt(index);
			if (code != 32 && code != 9 && code != 10 && code != 13)
				break;
			index++;
		}
	}

	function isIdentifierStartAt(position:Int):Bool {
		if (position < 0 || position >= source.length)
			return false;
		var code = source.charCodeAt(position);
		return code == 95 || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
	}

	function isIdentifierContinueAt(position:Int):Bool {
		if (position < 0 || position >= source.length)
			return false;
		var code = source.charCodeAt(position);
		return isIdentifierStartAt(position) || (code >= 48 && code <= 57);
	}

	function isDigit(char:String):Bool {
		return char.length == 1 && char >= "0" && char <= "9";
	}

	function fail(message:String):Void {
		throw '$message at offset $index in Rust metadata syntax `$source`';
	}
}
