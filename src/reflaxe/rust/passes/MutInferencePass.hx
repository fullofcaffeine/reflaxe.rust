package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustFunction;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustMatchArm;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustStructLitField;

/**
	MutInferencePass

	Why
	- Rust `let` bindings are immutable by default.
	- Lowering and cleanup passes can temporarily over-approximate or under-approximate mutability.
	- Mutability decisions must respect lexical block boundaries; whole-function name sets are too coarse
	  once compiler-generated helper names like `__b` or `_g_current` repeat in nested blocks.

	What
	- Recomputes `let mut` per block from actual mutation evidence.
	- Rewrites each `RLet` so `mutable` matches the requirements observed in the same rewritten block
	  tree, while preserving stronger mutability hints that were already proven earlier by typed
	  lowering.

	How
	- Recursively rewrites nested blocks first (`EBlock`, closures, async move bodies, loop bodies).
	- After a block is rewritten, collect mutable-binding requirements from that block and its nested
	  expressions, then normalize only that block's own `RLet` statements.
	- Existing `mutable = true` flags are preserved because the typed compiler pass knows about source
	  metadata such as `@:rustMutating`, which is not recoverable from the lowered Rust AST alone.
	- Real mutation signals are:
	  - direct assignment (`name = ...`)
	  - index-root assignment (`name[..] = ...`)
	  - explicit mutable reference use (`&mut name`)
	  - bindings initialized from `borrow_mut()` guards
**/
class MutInferencePass implements RustPass {
	public function new() {}

	public function name():String {
		return "mut_inference";
	}

	public function run(file:RustFile, _context:CompilationContext):RustFile {
		return {
			items: [for (item in file.items) rewriteItem(item)]
		};
	}

	function rewriteItem(item:RustItem):RustItem {
		return switch (item) {
			case RFn(f):
				RFn(rewriteFunction(f));
			case RImpl(i):
				RImpl({
					generics: i.generics,
					forType: i.forType,
					functions: [for (f in i.functions) rewriteFunction(f)]
				});
			case RStruct(_) | REnum(_) | RRaw(_):
				item;
		};
	}

	function rewriteFunction(f:RustFunction):RustFunction {
		return {
			name: f.name,
			isPub: f.isPub,
			vis: f.vis,
			isAsync: f.isAsync,
			generics: f.generics,
			args: f.args,
			ret: f.ret,
			body: rewriteBlock(f.body)
		};
	}

	function rewriteBlock(block:RustBlock):RustBlock {
		var rewrittenStmts = [for (stmt in block.stmts) rewriteStmt(stmt)];
		var rewrittenTail = block.tail == null ? null : rewriteExpr(block.tail);
		var assigned = collectAssignedNames({
			stmts: rewrittenStmts,
			tail: rewrittenTail
		});
		return {
			stmts: [for (stmt in rewrittenStmts) applyMutability(stmt, assigned)],
			tail: rewrittenTail
		};
	}

	function rewriteStmt(stmt:RustStmt):RustStmt {
		return switch (stmt) {
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : rewriteExpr(expr));
			case RSemi(expr):
				RSemi(rewriteExpr(expr));
			case RExpr(expr, needsSemicolon):
				RExpr(rewriteExpr(expr), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : rewriteExpr(expr));
			case RWhile(cond, body):
				RWhile(rewriteExpr(cond), rewriteBlock(body));
			case RLoop(body):
				RLoop(rewriteBlock(body));
			case RFor(name, iter, body):
				RFor(name, rewriteExpr(iter), rewriteBlock(body));
			case RBreak | RContinue:
				stmt;
		};
	}

	function rewriteExpr(expr:RustExpr):RustExpr {
		return switch (expr) {
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				expr;
			case ECall(func, args):
				ECall(rewriteExpr(func), [for (arg in args) rewriteExpr(arg)]);
			case EMacroCall(name, args):
				EMacroCall(name, [for (arg in args) rewriteExpr(arg)]);
			case EClosure(args, body, isMove):
				EClosure(args, rewriteBlock(body), isMove);
			case EBinary(op, left, right):
				EBinary(op, rewriteExpr(left), rewriteExpr(right));
			case EUnary(op, inner):
				EUnary(op, rewriteExpr(inner));
			case ERange(start, end):
				ERange(rewriteExpr(start), rewriteExpr(end));
			case ECast(inner, ty):
				ECast(rewriteExpr(inner), ty);
			case EIndex(recv, index):
				EIndex(rewriteExpr(recv), rewriteExpr(index));
			case EStructLit(path, fields):
				EStructLit(path, [for (field in fields) rewriteStructField(field)]);
			case EBlock(block):
				EBlock(rewriteBlock(block));
			case EIf(cond, thenExpr, elseExpr):
				EIf(rewriteExpr(cond), rewriteExpr(thenExpr), elseExpr == null ? null : rewriteExpr(elseExpr));
			case EMatch(scrutinee, arms):
				EMatch(rewriteExpr(scrutinee), [for (arm in arms) rewriteMatchArm(arm)]);
			case EAssign(lhs, rhs):
				EAssign(rewriteExpr(lhs), rewriteExpr(rhs));
			case EField(recv, field):
				EField(rewriteExpr(recv), field);
			case EPinAsyncMove(body):
				EPinAsyncMove(rewriteBlock(body));
			case EAwait(inner):
				EAwait(rewriteExpr(inner));
		};
	}

	function rewriteStructField(field:RustStructLitField):RustStructLitField {
		return {
			name: field.name,
			expr: rewriteExpr(field.expr)
		};
	}

	function rewriteMatchArm(arm:RustMatchArm):RustMatchArm {
		return {
			pat: arm.pat,
			expr: rewriteExpr(arm.expr)
		};
	}

	function collectAssignedNames(block:RustBlock):Map<String, Bool> {
		var out:Map<String, Bool> = [];
		var visitExpr:RustExpr->Void = null;
		var visitStmt:RustStmt->Void = null;
		var visitBlock:RustBlock->Void = null;

		visitExpr = function(expr:RustExpr):Void {
			switch (expr) {
				case EAssign(lhs, rhs):
					markAssignmentTarget(lhs, out);
					visitExpr(rhs);
				case ECall(func, args):
					visitExpr(func);
					for (arg in args)
						visitExpr(arg);
				case EMacroCall(_, args):
					for (arg in args)
						visitExpr(arg);
				case EClosure(_, body, _):
					visitBlock(body);
				case EBinary(_, left, right):
					visitExpr(left);
					visitExpr(right);
				case EUnary(op, inner):
					switch (inner) {
						case EPath(name):
							if (StringTools.startsWith(op, "&mut")) out.set(name, true);
						case _:
					}
					visitExpr(inner);
				case ERange(start, end):
					visitExpr(start);
					visitExpr(end);
				case ECast(inner, _):
					visitExpr(inner);
				case EIndex(recv, index):
					visitExpr(recv);
					visitExpr(index);
				case EStructLit(_, fields):
					for (field in fields)
						visitExpr(field.expr);
				case EBlock(innerBlock):
					visitBlock(innerBlock);
				case EIf(cond, thenExpr, elseExpr):
					visitExpr(cond);
					visitExpr(thenExpr);
					if (elseExpr != null)
						visitExpr(elseExpr);
				case EMatch(scrutinee, arms):
					visitExpr(scrutinee);
					for (arm in arms)
						visitExpr(arm.expr);
				case EField(recv, _):
					visitExpr(recv);
				case EPinAsyncMove(body):
					visitBlock(body);
				case EAwait(inner):
					visitExpr(inner);
				case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
			}
		};

		visitStmt = function(stmt:RustStmt):Void {
			switch (stmt) {
				case RLet(name, _, _, expr):
					if (expr != null) {
						if (exprProducesMutableGuard(expr))
							out.set(name, true);
						visitExpr(expr);
					}
				case RSemi(expr) | RExpr(expr, _):
					visitExpr(expr);
				case RReturn(expr):
					if (expr != null)
						visitExpr(expr);
				case RWhile(cond, body):
					visitExpr(cond);
					visitBlock(body);
				case RLoop(body):
					visitBlock(body);
				case RFor(_, iter, body):
					visitExpr(iter);
					visitBlock(body);
				case RBreak | RContinue:
			}
		};

		visitBlock = function(innerBlock:RustBlock):Void {
			for (stmt in innerBlock.stmts)
				visitStmt(stmt);
			if (innerBlock.tail != null)
				visitExpr(innerBlock.tail);
		};

		visitBlock(block);
		return out;
	}

	function exprProducesMutableGuard(expr:RustExpr):Bool {
		return switch (expr) {
			case ECall(EField(_, "borrow_mut"), []):
				true;
			case _:
				false;
		};
	}

	function markAssignmentTarget(lhs:RustExpr, out:Map<String, Bool>):Void {
		switch (lhs) {
			case EPath(name):
				out.set(name, true);
			case EIndex(recv, _):
				markAssignmentTarget(recv, out);
			case EField(_, _):
			case _:
		}
	}

	function applyMutability(stmt:RustStmt, assigned:Map<String, Bool>):RustStmt {
		return switch (stmt) {
			case RLet(name, mutable, ty, expr):
				var shouldBeMutable = name != "_" && (mutable || assigned.exists(name));
				if (mutable != shouldBeMutable) RLet(name, shouldBeMutable, ty, expr) else stmt;
			case _:
				stmt;
		};
	}
}
