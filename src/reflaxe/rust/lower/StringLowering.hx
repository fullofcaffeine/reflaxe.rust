package reflaxe.rust.lower;

import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustExpr.*;

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
	public static inline function rustStringTypePath(nullableStrings:Bool):String {
		return nullableStrings ? "hxrt::string::HxString" : "String";
	}

	public static inline function stringLiteralExpr(nullableStrings:Bool, value:String):RustExpr {
		return nullableStrings ? ECall(EPath("hxrt::string::HxString::from"), [ELitString(value)]) : ECall(EPath("String::from"), [ELitString(value)]);
	}

	public static inline function stringNullExpr(nullableStrings:Bool):RustExpr {
		return nullableStrings ? ECall(EPath("hxrt::string::HxString::null"), []) : ECall(EPath("String::new"), []);
	}

	public static inline function wrapRustStringExpr(nullableStrings:Bool, value:RustExpr):RustExpr {
		return nullableStrings ? ECall(EPath("hxrt::string::HxString::from"), [value]) : value;
	}

	public static inline function stringNullDefaultValue(nullableStrings:Bool):String {
		return nullableStrings ? "hxrt::string::HxString::null()" : "String::new()";
	}
}
