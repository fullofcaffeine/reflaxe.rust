package reflaxe.rust.ast;

import haxe.macro.Expr.Position;

/**
 * Minimal Rust AST for the reflaxe.rust compiler.
 *
 * Keep this deliberately small and extend as codegen needs grow.
 */
// Main module type (required for Haxe module/type resolution).
class RustAST {}

/**
	Describes whether a Rust IR node came from Haxe source or was synthesized by the backend.

	Why
	- Diagnostics and policy passes must distinguish user authority from compiler implementation
	  details without guessing from printed Rust text.
	- A missing position is not equivalent to user source: generated scaffolding needs an explicit
	  origin so later source-map work can report it honestly.

	What
	- `OriginHaxeSource` retains the exact typed-AST position supplied by Haxe.
	- `OriginCompilerGenerated` marks syntax with no single honest Haxe source position.

	How
	- Raw-fragment factories require one of these origins today. Later typed IR nodes can reuse the
	  same origin without changing Rust output.
**/
enum RustOrigin {
	OriginHaxeSource(pos:Position);
	OriginCompilerGenerated;
}

/**
	Closed reasons for compiler-owned Rust text that has not yet migrated to structural IR.

	Why
	- `RRaw` and `ERaw` are analysis blind spots. Treating every compiler string as equivalent makes
	  it impossible to prioritize migration or tell source authority from backend debt.

	What
	- Each constructor identifies one current compiler lowering family. These reasons describe
	  migration debt; they do not authorize adding more raw lowering.

	How
	- `RustRawCode` maps every constructor to a stable identifier. Adding a constructor therefore
	  requires updating the exhaustive mapping and reviewing the new authority explicitly.
**/
enum RustCompilerRawReason {
	RawGeneratedFileMarker;
	RawStaticStorage;
	RawCrateHeader;
	RawNestedModuleDeclarations;
	RawInterfaceTraitDeclaration;
	RawBaseTraitImport;
	RawTypeIdConstant;
	RawDeriveAttribute;
	RawClassTraitDeclaration;
	RawClassTraitImplementation;
	RawBaseTraitImplementation;
	RawInterfaceTraitImplementation;
	RawGeneratedTestModule;
	RawDefaultValueFallback;
	RawUnsupportedFallback;
}

/**
	Closed reasons for Rust text deliberately supplied through Haxe metadata.

	Why
	- Metadata is user authority even when the compiler renders its surrounding syntax.
	- Keeping it separate prevents a future compiler migration from silently claiming ownership of
	  source-provided Rust bodies or target paths.

	What
	- Currently covers the raw `@:rustImpl` contract.

	How
	- The metadata factory always requires the metadata's Haxe position.
**/
enum RustMetadataRawReason {
	RawTraitImplementation;
}

/**
	Closed reasons for Rust expressions supplied verbatim by source code.

	Why
	- Explicit target-code injection is a real escape hatch and must never be confused with typed
	  compiler lowering merely because both eventually print Rust text.

	What
	- Currently covers the configured `__rust__` target-code injection boundary.

	How
	- The source factory requires an exact Haxe position and remains visible to metal restrictions.
	- This records emission ownership only; it never grants `@:rustAllowRaw` permission or weakens
	  strict/metal boundary enforcement.
**/
enum RustSourceRawReason {
	RawTargetCodeInjection;
}

/**
	Identifies who owns an intentionally raw Rust fragment.

	Why
	- Policy passes need a typed distinction between compiler migration debt, metadata authority, and
	  explicit source injection.

	What
	- Wraps one of three closed reason enums rather than accepting a free-form label.

	How
	- Instances can only be created through `RustRawCode` factories, which pair authority with a
	  source origin.
**/
enum RustRawAuthority {
	RawCompilerOwned(reason:RustCompilerRawReason);
	RawMetadataOwned(reason:RustMetadataRawReason);
	RawSourceOwned(reason:RustSourceRawReason);
}

/**
	A classified raw Rust fragment carried by `RRaw` or `ERaw`.

	Why
	- Plain strings erase both authority and Haxe provenance, so compiler passes cannot distinguish an
	  intentional escape hatch from syntax that should become typed IR.
	- Public construction would allow new raw text to bypass that classification.

	What
	- Stores the exact printable bytes plus a closed authority/reason and explicit origin.
	- Exposes stable identifiers for reports and policy diagnostics.

	How
	- The constructor is private. Callers select `compilerGenerated`, `compilerAt`, `metadataAt`, or
	  `sourceAt`; `withCode` is the only transformation helper and preserves metadata byte-for-byte.
	- The printer reads only `code`, so classification cannot alter generated Rust.
**/
class RustRawCode {
	public final code:String;
	public final authority:RustRawAuthority;
	public final origin:RustOrigin;

	private function new(code:String, authority:RustRawAuthority, origin:RustOrigin) {
		this.code = code;
		this.authority = authority;
		this.origin = origin;
	}

	public static function compilerGenerated(code:String, reason:RustCompilerRawReason):RustRawCode {
		return new RustRawCode(code, RawCompilerOwned(reason), OriginCompilerGenerated);
	}

	public static function compilerAt(code:String, reason:RustCompilerRawReason, pos:Position):RustRawCode {
		return new RustRawCode(code, RawCompilerOwned(reason), OriginHaxeSource(pos));
	}

	public static function metadataAt(code:String, reason:RustMetadataRawReason, pos:Position):RustRawCode {
		return new RustRawCode(code, RawMetadataOwned(reason), OriginHaxeSource(pos));
	}

	public static function sourceAt(code:String, reason:RustSourceRawReason, pos:Position):RustRawCode {
		return new RustRawCode(code, RawSourceOwned(reason), OriginHaxeSource(pos));
	}

	public function withCode(nextCode:String):RustRawCode {
		return new RustRawCode(nextCode, authority, origin);
	}

	public function authorityId():String {
		return switch (authority) {
			case RawCompilerOwned(_): "compiler-owned";
			case RawMetadataOwned(_): "metadata-owned";
			case RawSourceOwned(_): "source-owned";
		};
	}

	public function reasonId():String {
		return switch (authority) {
			case RawCompilerOwned(reason): switch (reason) {
					case RawGeneratedFileMarker: "generated-file-marker";
					case RawStaticStorage: "static-storage";
					case RawCrateHeader: "crate-header";
					case RawNestedModuleDeclarations: "nested-module-declarations";
					case RawInterfaceTraitDeclaration: "interface-trait-declaration";
					case RawBaseTraitImport: "base-trait-import";
					case RawTypeIdConstant: "type-id-constant";
					case RawDeriveAttribute: "derive-attribute";
					case RawClassTraitDeclaration: "class-trait-declaration";
					case RawClassTraitImplementation: "class-trait-implementation";
					case RawBaseTraitImplementation: "base-trait-implementation";
					case RawInterfaceTraitImplementation: "interface-trait-implementation";
					case RawGeneratedTestModule: "generated-test-module";
					case RawDefaultValueFallback: "default-value-fallback";
					case RawUnsupportedFallback: "unsupported-fallback";
				}
			case RawMetadataOwned(reason): switch (reason) {
					case RawTraitImplementation: "trait-implementation";
				}
			case RawSourceOwned(reason): switch (reason) {
					case RawTargetCodeInjection: "target-code-injection";
				}
		};
	}
}

enum RustVisibility {
	VPrivate;
	VPub;
	VPubCrate;
}

typedef RustFile = {
	var items:Array<RustItem>;
}

enum RustItem {
	RFn(f:RustFunction);
	RStruct(s:RustStruct);
	REnum(e:RustEnum);
	RImpl(i:RustImpl);
	RRaw(fragment:RustRawCode);
}

typedef RustStruct = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	@:optional var generics:Array<String>;
	var fields:Array<RustStructField>;
}

typedef RustStructField = {
	var name:String;
	var ty:RustType;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
}

typedef RustEnum = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	@:optional var generics:Array<String>;
	var derives:Array<String>;
	var variants:Array<RustEnumVariant>;
}

typedef RustEnumVariant = {
	var name:String;
	var args:Array<RustType>;
}

typedef RustImpl = {
	@:optional var generics:Array<String>;
	var forType:String;
	var functions:Array<RustFunction>;
}

typedef RustFunction = {
	var name:String;
	var isPub:Bool;
	@:optional var vis:RustVisibility;
	@:optional var isAsync:Bool;
	@:optional var generics:Array<String>;
	var args:Array<RustFnArg>;
	var ret:RustType;
	var body:RustBlock;
}

typedef RustFnArg = {
	var name:String;
	var ty:RustType;
}

enum RustType {
	RUnit;
	RBool;
	RI32;
	RF64;
	RString;
	RRef(inner:RustType, mutable:Bool);
	RPath(path:String);
}

typedef RustBlock = {
	var stmts:Array<RustStmt>;
	var tail:Null<RustExpr>;
}

typedef RustMatchArm = {
	var pat:RustPattern;
	var expr:RustExpr;
}

typedef RustStructLitField = {
	var name:String;
	var expr:RustExpr;
}

enum RustPattern {
	PWildcard;
	PBind(name:String);
	PAlias(name:String, pattern:RustPattern);
	PPath(path:String);
	PLitInt(v:Int);
	PLitBool(v:Bool);
	PLitString(v:String);
	PTupleStruct(path:String, fields:Array<RustPattern>);
	POr(patterns:Array<RustPattern>);
}

enum RustStmt {
	RLet(name:String, mutable:Bool, ty:Null<RustType>, expr:Null<RustExpr>);
	RSemi(e:RustExpr);
	// Like `RSemi`, but allows emitting statement-like expressions without a trailing semicolon
	// (e.g. unit-typed `if` / `match` / `{ ... }` blocks).
	RExpr(e:RustExpr, needsSemicolon:Bool);
	RReturn(e:Null<RustExpr>);
	RWhile(cond:RustExpr, body:RustBlock);
	RLoop(body:RustBlock);
	RFor(name:String, iter:RustExpr, body:RustBlock);
	RBreak;
	RContinue;
}

enum RustExpr {
	ERaw(fragment:RustRawCode);
	ELitInt(v:Int);
	ELitFloat(v:Float);
	ELitBool(v:Bool);
	ELitString(v:String);
	EPath(path:String);
	ECall(func:RustExpr, args:Array<RustExpr>);
	EMacroCall(name:String, args:Array<RustExpr>);
	EClosure(args:Array<String>, body:RustBlock, isMove:Bool);
	EBinary(op:String, left:RustExpr, right:RustExpr);
	EUnary(op:String, expr:RustExpr);
	ERange(start:RustExpr, end:RustExpr);
	ECast(expr:RustExpr, ty:String);
	EIndex(recv:RustExpr, index:RustExpr);
	EStructLit(path:String, fields:Array<RustStructLitField>);
	EBlock(b:RustBlock);
	EIf(cond:RustExpr, thenExpr:RustExpr, elseExpr:Null<RustExpr>);
	EMatch(scrutinee:RustExpr, arms:Array<RustMatchArm>);
	EAssign(lhs:RustExpr, rhs:RustExpr);
	EField(recv:RustExpr, field:String);
	// Typed async wrapper used for `@:rustAsync` lowering.
	//
	// Why
	// - The compiler historically emitted this shape as `ERaw("Box::pin(async move { ... })")`,
	//   which inflated metal fallback diagnostics even though the structure is compiler-owned and
	//   deterministic.
	//
	// What
	// - Represents `Box::pin(async move { <body> })` with a typed `RustBlock` payload.
	//
	// How
	// - Printer renders this constructor directly; traversal passes recurse into `body`.
	EPinAsyncMove(body:RustBlock);
	EAwait(expr:RustExpr);
}
