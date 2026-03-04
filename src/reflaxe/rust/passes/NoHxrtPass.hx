package reflaxe.rust.passes;

import haxe.macro.Context;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustType;

/**
	NoHxrtPass

	Why
	- `-D rust_no_hxrt` is a hard boundary contract: generated code must not reference `hxrt`.
	- Omitting the runtime dependency without validation would fail later at Cargo build time with
	  low-signal unresolved-path errors.

	What
	- Scans emitted Rust AST nodes and detects any `hxrt` path usage in types, expressions, patterns,
	  and raw code items.
	- Emits a single actionable compile error per module when violations are found.

	How
	- Runs only when `CompilationContext.build.noHxrt` is enabled.
	- Traverses typed AST structures (not printed source text) and records representative samples.
	- `RRaw` blocks are scanned line-by-line, ignoring pure comment lines.
**/
class NoHxrtPass implements RustPass {
	static inline final MAX_SAMPLES:Int = 8;

	public function new() {}

	public function name():String {
		return "no_hxrt";
	}

	public function run(file:RustFile, context:CompilationContext):RustFile {
		if (!context.build.noHxrt)
			return file;

		var violationCount = 0;
		var samples:Array<String> = [];

		inline function record(sample:String):Void {
			violationCount++;
			if (samples.length >= MAX_SAMPLES)
				return;
			if (!samples.contains(sample))
				samples.push(sample);
		}

		inline function recordPath(kind:String, path:String):Void {
			if (path == null)
				return;
			if (isHxrtPath(path))
				record(kind + " `" + path + "`");
		}

		var scanType:RustType->Void = null;
		var scanPattern:RustPattern->Void = null;
		var scanBlock:RustBlock->Void = null;
		var scanStmt:RustStmt->Void = null;
		var scanExpr:RustExpr->Void = null;

		scanType = function(ty:RustType):Void {
			switch (ty) {
				case RRef(inner, _):
					scanType(inner);
				case RPath(path):
					recordPath("type", path);
				case _:
			}
		};

		scanPattern = function(pat:RustPattern):Void {
			switch (pat) {
				case PPath(path):
					recordPath("pattern", path);
				case PTupleStruct(path, fields):
					recordPath("pattern", path);
					for (field in fields)
						scanPattern(field);
				case POr(patterns):
					for (entry in patterns)
						scanPattern(entry);
				case _:
			}
		};

		scanBlock = function(block:RustBlock):Void {
			for (stmt in block.stmts)
				scanStmt(stmt);
			if (block.tail != null)
				scanExpr(block.tail);
		};

		scanStmt = function(stmt:RustStmt):Void {
			switch (stmt) {
				case RLet(_, _, ty, expr):
					if (ty != null)
						scanType(ty);
					if (expr != null)
						scanExpr(expr);
				case RSemi(expr):
					scanExpr(expr);
				case RExpr(expr, _):
					scanExpr(expr);
				case RReturn(expr):
					if (expr != null)
						scanExpr(expr);
				case RWhile(cond, body):
					scanExpr(cond);
					scanBlock(body);
				case RLoop(body):
					scanBlock(body);
				case RFor(_, iter, body):
					scanExpr(iter);
					scanBlock(body);
				case RBreak | RContinue:
			}
		};

		scanExpr = function(expr:RustExpr):Void {
			switch (expr) {
				case ERaw(raw):
					if (containsHxrt(raw))
						record("raw expression containing `hxrt::`");
				case EPath(path):
					recordPath("path", path);
				case ECall(func, args):
					scanExpr(func);
					for (arg in args)
						scanExpr(arg);
				case EMacroCall(_, args):
					for (arg in args)
						scanExpr(arg);
				case EClosure(_, body, _):
					scanBlock(body);
				case EBinary(_, left, right):
					scanExpr(left);
					scanExpr(right);
				case EUnary(_, value):
					scanExpr(value);
				case ERange(start, end):
					scanExpr(start);
					scanExpr(end);
				case ECast(value, ty):
					scanExpr(value);
					recordPath("cast", ty);
				case EIndex(recv, index):
					scanExpr(recv);
					scanExpr(index);
				case EStructLit(path, fields):
					recordPath("struct", path);
					for (field in fields)
						scanExpr(field.expr);
				case EBlock(block):
					scanBlock(block);
				case EIf(cond, thenExpr, elseExpr):
					scanExpr(cond);
					scanExpr(thenExpr);
					if (elseExpr != null)
						scanExpr(elseExpr);
				case EMatch(scrutinee, arms):
					scanExpr(scrutinee);
					for (arm in arms) {
						scanPattern(arm.pat);
						scanExpr(arm.expr);
					}
				case EAssign(lhs, rhs):
					scanExpr(lhs);
					scanExpr(rhs);
				case EField(recv, _):
					scanExpr(recv);
				case EPinAsyncMove(body):
					scanBlock(body);
				case EAwait(value):
					scanExpr(value);
				case ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
			}
		};

		function scanRawItem(raw:String):Void {
			if (raw == null || raw.length == 0)
				return;
			for (line in raw.split("\n")) {
				var trimmed = StringTools.trim(line);
				if (trimmed.length == 0)
					continue;
				if (StringTools.startsWith(trimmed, "//"))
					continue;
				if (containsHxrt(trimmed)) {
					record("raw item `" + clip(trimmed, 88) + "`");
				}
			}
		}

		for (item in file.items) {
			switch (item) {
				case RFn(f):
					for (arg in f.args)
						scanType(arg.ty);
					scanType(f.ret);
					scanBlock(f.body);
				case RStruct(s):
					for (field in s.fields)
						scanType(field.ty);
				case REnum(e):
					for (variant in e.variants) {
						for (arg in variant.args)
							scanType(arg);
					}
				case RImpl(i):
					recordPath("impl", i.forType);
					for (fn in i.functions) {
						for (arg in fn.args)
							scanType(arg.ty);
						scanType(fn.ret);
						scanBlock(fn.body);
					}
				case RRaw(raw):
					scanRawItem(raw);
			}
		}

		if (violationCount > 0) {
			var moduleLabel = context.currentModuleLabel != null ? context.currentModuleLabel : "<unknown>";
			var detail = samples.length > 0 ? samples.join("; ") : "<no sample captured>";
			#if eval
			var diagPos = context.diagnosticPos(moduleLabel);
			if (diagPos == null)
				diagPos = Context.currentPos();
			Context.error("`-D rust_no_hxrt` violation in module `"
				+ moduleLabel
				+ "`: generated Rust still references `hxrt` "
				+ violationCount
				+ " time(s). Samples: "
				+ detail
				+ ". This module still relies on portable runtime semantics; remove `-D rust_no_hxrt` or refactor to Rust-first typed APIs.",
				diagPos);
			#end
		}

		return file;
	}

	static inline function isHxrtPath(path:String):Bool {
		return containsHxrt(path);
	}

	static inline function containsHxrt(value:String):Bool {
		if (value == null)
			return false;
		return value.indexOf("hxrt::") != -1 || value.indexOf("hxrt.") != -1;
	}

	static function clip(value:String, max:Int):String {
		if (value == null)
			return "";
		if (value.length <= max)
			return value;
		return value.substr(0, max - 3) + "...";
	}
}
