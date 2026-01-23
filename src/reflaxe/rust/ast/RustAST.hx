package reflaxe.rust.ast;

/**
 * Minimal Rust AST for the POC compiler.
 *
 * Keep this deliberately small and extend as codegen needs grow.
 */

// Main module type (required for Haxe module/type resolution).
class RustAST {}

typedef RustFile = {
	var items: Array<RustItem>;
}

enum RustItem {
	RFn(f: RustFunction);
	RStruct(s: RustStruct);
	RImpl(i: RustImpl);
	RRaw(s: String);
}

typedef RustStruct = {
	var name: String;
	var isPub: Bool;
	var fields: Array<RustStructField>;
}

typedef RustStructField = {
	var name: String;
	var ty: RustType;
	var isPub: Bool;
}

typedef RustImpl = {
	var forType: String;
	var functions: Array<RustFunction>;
}

typedef RustFunction = {
	var name: String;
	var isPub: Bool;
	var args: Array<RustFnArg>;
	var ret: RustType;
	var body: RustBlock;
}

typedef RustFnArg = {
	var name: String;
	var ty: RustType;
}

enum RustType {
	RUnit;
	RBool;
	RI32;
	RF64;
	RString;
	RPath(path: String);
}

typedef RustBlock = {
	var stmts: Array<RustStmt>;
	var tail: Null<RustExpr>;
}

enum RustStmt {
	RLet(name: String, mutable: Bool, ty: Null<RustType>, expr: Null<RustExpr>);
	RSemi(e: RustExpr);
	RReturn(e: Null<RustExpr>);
}

enum RustExpr {
	ERaw(s: String);
	ELitInt(v: Int);
	ELitFloat(v: Float);
	ELitBool(v: Bool);
	ELitString(v: String);
	EPath(path: String);
	ECall(func: RustExpr, args: Array<RustExpr>);
	EMacroCall(name: String, args: Array<RustExpr>);
	EBinary(op: String, left: RustExpr, right: RustExpr);
	EUnary(op: String, expr: RustExpr);
	EBlock(b: RustBlock);
	EIf(cond: RustExpr, thenExpr: RustExpr, elseExpr: Null<RustExpr>);
	EAssign(lhs: RustExpr, rhs: RustExpr);
	EField(recv: RustExpr, field: String);
}
