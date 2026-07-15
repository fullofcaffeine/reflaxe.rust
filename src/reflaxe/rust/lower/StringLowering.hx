package reflaxe.rust.lower;

import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustExpr.*;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;

/**
		StringLowering

	Why
	- String representation policy (`String` vs `hxrt::string::HxString`) is a core lowering
	  decision reused across many expression paths.
	- Centralizing these builders in `lower/` prevents policy drift and keeps expression lowering
	  callsites concise.

	What
		- Typed helpers for string-type paths and literal/default constructors.

		How
		- Callers pass `nullableStrings` once and receive the correct Rust AST node/path for the active
		  profile/define policy.
		- In non-null string mode, these helpers never synthesize a fake `"null"` sentinel string.
		  Null-as-string contract handling is enforced in `RustCompiler` at typed boundary sites.
**/
class StringLowering {
	/**
		Builds a compiler-owned relative path from already separated identifiers.

		Why
		- String lowering knows the semantic module/member boundaries and must not collapse them into
		  delimiter-bearing text before the printer.

		What
		- Produces one validated `RustPathSegment` per supplied identifier.

		How
		- Callers pass only fixed compiler-owned names; metadata-owned target syntax is parsed elsewhere.
	**/
	static function path(names:Array<String>):RustPath {
		return RustPath.relative([for (name in names) RustPathSegment.plain(name)]);
	}

	public static inline function stringLiteralExpr(nullableStrings:Bool, value:String):RustExpr {
		return nullableStrings ? ECall(EPath(path(["hxrt", "string", "HxString", "from"])), [ELitString(value)]) : ECall(EPath(path(["String", "from"])),
			[ELitString(value)]);
	}

	public static inline function stringNullExpr(nullableStrings:Bool):RustExpr {
		return nullableStrings ? ECall(EPath(path(["hxrt", "string", "HxString", "null"])), []) : ECall(EPath(path(["String", "new"])), []);
	}

	public static inline function wrapRustStringExpr(nullableStrings:Bool, value:RustExpr):RustExpr {
		return nullableStrings ? ECall(EPath(path(["hxrt", "string", "HxString", "from"])), [value]) : value;
	}
}
