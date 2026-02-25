package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustStmt;

/**
	MutInferencePass

	Why
	- Rust `let` bindings are immutable by default.
	- Overusing `let mut` creates warning noise (`unused_mut`) and hides real mutation intent.

	What
	- Downgrades `let mut name = ...` to `let name = ...` when the binding is never assigned.

	How
	- Two-phase pass:
	  1) collect assigned identifiers (`name = ...`) and index-assignment roots (`name[..] = ...`)
	  2) rewrite `RLet(... mutable=true ...)` to immutable when the identifier is absent from the set.
**/
class MutInferencePass implements RustPass {
	public function new() {}

	public function name():String {
		return "mut_inference";
	}

	public function run(file:RustFile, _context:CompilationContext):RustFile {
		var assigned:Map<String, Bool> = collectAssignedNames(file);
		return RustPassTools.mapFile(file, s -> rewriteStmt(s, assigned), e -> e);
	}

	function collectAssignedNames(file:RustFile):Map<String, Bool> {
		var out:Map<String, Bool> = [];
		var visitExpr:RustExpr->Void = null;
		var visitStmt:RustStmt->Void = null;
		var visitBlock:reflaxe.rust.ast.RustAST.RustBlock->Void = null;

		visitExpr = function(e:RustExpr):Void {
			switch (e) {
				case EAssign(lhs, rhs):
					markAssignmentTarget(lhs, out);
					visitExpr(rhs);
				case ECall(func, args):
					switch (func) {
						case EField(EPath(name), _):
							// Conservative rule: method call on a local binding may require `&mut self`
							// (for example `Vec::push`). Keep the binding mutable in that case.
							out.set(name, true);
						case _:
					}
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
							// Explicit mutable reference usage always requires mutable binding.
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
				case EBlock(block):
					visitBlock(block);
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
				case EAwait(inner):
					visitExpr(inner);
				case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
			}
		}

		visitStmt = function(s:RustStmt):Void {
			switch (s) {
				case RLet(_, _, _, expr):
					if (expr != null)
						visitExpr(expr);
				case RSemi(e) | RExpr(e, _):
					visitExpr(e);
				case RReturn(e):
					if (e != null)
						visitExpr(e);
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
		}

		visitBlock = function(b:reflaxe.rust.ast.RustAST.RustBlock):Void {
			for (stmt in b.stmts)
				visitStmt(stmt);
			if (b.tail != null)
				visitExpr(b.tail);
		}

		for (item in file.items) {
			switch (item) {
				case RFn(f):
					visitBlock(f.body);
				case RImpl(i):
					for (f in i.functions)
						visitBlock(f.body);
				case _:
			}
		}

		return out;
	}

	function markAssignmentTarget(lhs:RustExpr, out:Map<String, Bool>):Void {
		switch (lhs) {
			case EPath(name):
				out.set(name, true);
			case EIndex(recv, _):
				markAssignmentTarget(recv, out);
			case EField(_, _):
				// Field assignment does not require mutability on the binding itself.
			case _:
		}
	}

	function rewriteStmt(s:RustStmt, assigned:Map<String, Bool>):RustStmt {
		return switch (s) {
			case RLet(name, mutable, ty, expr):
				if (mutable && !assigned.exists(name)) {
					RLet(name, false, ty, expr);
				} else {
					s;
				}
			case _:
				s;
		}
	}
}
