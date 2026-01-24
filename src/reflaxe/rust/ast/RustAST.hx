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
	REnum(e: RustEnum);
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

typedef RustEnum = {
	var name: String;
	var isPub: Bool;
	var derives: Array<String>;
	var variants: Array<RustEnumVariant>;
}

typedef RustEnumVariant = {
	var name: String;
	var args: Array<RustType>;
}

typedef RustImpl = {
	var forType: String;
	var functions: Array<RustFunction>;
}

typedef RustFunction = {
	var name: String;
	var isPub: Bool;
	@:optional var generics: Array<String>;
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
	RRef(inner: RustType, mutable: Bool);
	RPath(path: String);
}

typedef RustBlock = {
	var stmts: Array<RustStmt>;
	var tail: Null<RustExpr>;
}

typedef RustMatchArm = {
	var pat: RustPattern;
	var expr: RustExpr;
}

enum RustPattern {
	PWildcard;
	PBind(name: String);
	PPath(path: String);
	PLitInt(v: Int);
	PLitBool(v: Bool);
	PLitString(v: String);
	PTupleStruct(path: String, fields: Array<RustPattern>);
	POr(patterns: Array<RustPattern>);
}

enum RustStmt {
	RLet(name: String, mutable: Bool, ty: Null<RustType>, expr: Null<RustExpr>);
	RSemi(e: RustExpr);
	RReturn(e: Null<RustExpr>);
	RWhile(cond: RustExpr, body: RustBlock);
	RLoop(body: RustBlock);
	RFor(name: String, iter: RustExpr, body: RustBlock);
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
	EClosure(args: Array<String>, body: RustBlock);
	EBinary(op: String, left: RustExpr, right: RustExpr);
	EUnary(op: String, expr: RustExpr);
	ERange(start: RustExpr, end: RustExpr);
	ECast(expr: RustExpr, ty: String);
	EIndex(recv: RustExpr, index: RustExpr);
	EBlock(b: RustBlock);
	EIf(cond: RustExpr, thenExpr: RustExpr, elseExpr: Null<RustExpr>);
	EMatch(scrutinee: RustExpr, arms: Array<RustMatchArm>);
	EAssign(lhs: RustExpr, rhs: RustExpr);
	EField(recv: RustExpr, field: String);
}
