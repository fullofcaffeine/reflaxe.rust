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
import reflaxe.rust.ast.RustAST.RustType;

/**
	StatementCleanupPass

	Why
	- Some typed lowering paths are semantically correct but still produce Rust warning-shapes such as
	  `let mut x; x = value;`, dead discarded path statements (`x;`), and initialized temporaries that
	  are never referenced again.
	- Those artifacts are especially harmful in `#![deny(warnings)]` fixtures because they obscure real
	  regressions behind compiler-generated noise.

	What
	- Performs conservative block-local cleanup after expression lowering.
	- Rewrites three patterns:
	  1) `let x; x = rhs;` -> `let x = rhs;` (keeping `mut` only when later writes still need it)
	  2) `let tmp = rhs;` where `tmp` is never mentioned again -> `let _ = rhs;`
	  3) pure discarded statements like `x;` or `123;` -> removed

	How
	- Recursively rewrites nested blocks/expressions first, then applies block-local cleanup to the
	  rewritten statement list.
	- Name-usage checks treat `ERaw` as a typed blind spot and conservatively scan its text for
	  identifier references, because some std/native fallback boundaries still emit raw Rust that can
	  mention local bindings.
	- The pass stays intentionally conservative: it only collapses direct local assignments and only
	  removes discarded expressions when they are side-effect-free.
**/
class StatementCleanupPass implements RustPass {
	public function new() {}

	public function name():String {
		return "statement_cleanup";
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
		var stmts = [for (stmt in block.stmts) rewriteStmt(stmt)];
		var tail = block.tail == null ? null : rewriteExpr(block.tail);
		return cleanupBlock(stmts, tail);
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
				EStructLit(path, [for (field in fields) rewriteStructLitField(field)]);
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

	function rewriteStructLitField(field:RustStructLitField):RustStructLitField {
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

	function cleanupBlock(stmts:Array<RustStmt>, tail:Null<RustExpr>):RustBlock {
		var out:Array<RustStmt> = [];
		var pendingDecls:Array<{name:String, ty:Null<RustType>}> = [];

		function findPendingDecl(name:String):Null<{name:String, ty:Null<RustType>}> {
			for (decl in pendingDecls) {
				if (decl.name == name)
					return decl;
			}
			return null;
		}

		function flushPendingMentionedBy(stmt:RustStmt):Void {
			if (pendingDecls.length == 0)
				return;
			var remaining:Array<{name:String, ty:Null<RustType>}> = [];
			for (decl in pendingDecls) {
				if (stmtMentionsName(stmt, decl.name)) {
					out.push(RLet(decl.name, false, decl.ty, null));
				} else {
					remaining.push(decl);
				}
			}
			pendingDecls = remaining;
		}

		function flushAllPending():Void {
			if (pendingDecls.length == 0)
				return;
			for (decl in pendingDecls)
				out.push(RLet(decl.name, false, decl.ty, null));
			pendingDecls = [];
		}

		var i = 0;
		while (i < stmts.length) {
			var stmt = stmts[i];
			switch (stmt) {
				case RLet(name, _, ty, null):
					pendingDecls.push({name: name, ty: ty});
					i++;
					continue;
				case _:
			}

			var collapsed = switch (stmt) {
				case RSemi(EAssign(EPath(name), rhs)) | RExpr(EAssign(EPath(name), rhs), true):
					var pending = findPendingDecl(name);
					if (pending != null) {
						pendingDecls = [for (decl in pendingDecls) if (decl.name != name) decl];
						var mutable = hasDirectAssignmentAfter(stmts, tail, i + 1, name);
						RLet(name, mutable, pending.ty, rhs);
					} else {
						null;
					}
				case RSemi(EBlock(block)) | RExpr(EBlock(block), true):
					collapsePendingBlockAssignment(block, pendingDecls, stmts, tail, i);
				case _:
					null;
			}

			if (collapsed != null) {
				switch (collapsed) {
					case RLet(name, _, _, _):
						pendingDecls = [for (decl in pendingDecls) if (decl.name != name) decl];
					case _:
				}
				if (!isDeadDiscardStmt(collapsed))
					out.push(rewriteUnusedBindingIfNeeded(collapsed, stmts, tail, i + 1));
				i++;
				continue;
			}

			flushPendingMentionedBy(stmt);

			if (!isDeadDiscardStmt(stmt))
				out.push(rewriteUnusedBindingIfNeeded(stmt, stmts, tail, i + 1));
			i++;
		}
		flushAllPending();
		return {stmts: out, tail: tail};
	}

	function collapsePendingBlockAssignment(block:RustBlock, pendingDecls:Array<{name:String, ty:Null<RustType>}>, stmts:Array<RustStmt>, tail:Null<RustExpr>,
			currentIndex:Int):Null<RustStmt> {
		if (block.stmts.length == 0)
			return null;
		if (block.tail != null) {
			for (decl in pendingDecls) {
				if (exprMentionsName(block.tail, decl.name))
					return null;
			}
		}

		var lastStmt = block.stmts[block.stmts.length - 1];
		var assignment = switch (lastStmt) {
			case RSemi(EAssign(EPath(name), rhs)) | RExpr(EAssign(EPath(name), rhs), true):
				{name: name, rhs: rhs};
			case _:
				null;
		};
		if (assignment == null)
			return null;

		var pending = null;
		for (decl in pendingDecls) {
			if (decl.name == assignment.name) {
				pending = decl;
				break;
			}
		}
		if (pending == null)
			return null;

		for (j in 0...block.stmts.length - 1) {
			if (stmtMentionsName(block.stmts[j], assignment.name))
				return null;
		}

		var mutable = hasDirectAssignmentAfter(stmts, tail, currentIndex + 1, assignment.name);
		var initExpr = if (block.stmts.length == 1 && block.tail == null) {
			assignment.rhs;
		} else {
			EBlock({
				stmts: block.stmts.slice(0, block.stmts.length - 1),
				tail: assignment.rhs
			});
		};
		return RLet(assignment.name, mutable, pending.ty, initExpr);
	}

	function hasDirectAssignmentAfter(stmts:Array<RustStmt>, tail:Null<RustExpr>, startIndex:Int, name:String):Bool {
		for (i in startIndex...stmts.length) {
			if (stmtHasDirectAssignmentToName(stmts[i], name))
				return true;
		}
		return tail != null && exprHasDirectAssignmentToName(tail, name);
	}

	function stmtHasDirectAssignmentToName(stmt:RustStmt, name:String):Bool {
		return switch (stmt) {
			case RLet(_, _, _, expr): expr != null && exprHasDirectAssignmentToName(expr, name);
			case RSemi(expr) | RExpr(expr, _) | RReturn(expr): expr != null && exprHasDirectAssignmentToName(expr, name);
			case RWhile(cond, body): exprHasDirectAssignmentToName(cond, name) || blockHasDirectAssignmentToName(body, name);
			case RLoop(body):
				blockHasDirectAssignmentToName(body, name);
			case RFor(_, iter, body): exprHasDirectAssignmentToName(iter, name) || blockHasDirectAssignmentToName(body, name);
			case RBreak | RContinue:
				false;
		};
	}

	function blockHasDirectAssignmentToName(block:RustBlock, name:String):Bool {
		for (stmt in block.stmts) {
			if (stmtHasDirectAssignmentToName(stmt, name))
				return true;
		}
		return block.tail != null && exprHasDirectAssignmentToName(block.tail, name);
	}

	function exprHasDirectAssignmentToName(expr:RustExpr, name:String):Bool {
		return switch (expr) {
			case EAssign(EPath(lhs), rhs): lhs == name || exprHasDirectAssignmentToName(rhs, name);
			case EAssign(lhs, rhs): exprHasDirectAssignmentToName(lhs, name) || exprHasDirectAssignmentToName(rhs, name);
			case ECall(func, args): exprHasDirectAssignmentToName(func, name) || anyExprHasDirectAssignmentToName(args, name);
			case EMacroCall(_, args):
				anyExprHasDirectAssignmentToName(args, name);
			case EClosure(_, body, _):
				blockHasDirectAssignmentToName(body, name);
			case EBinary(_, left, right): exprHasDirectAssignmentToName(left, name) || exprHasDirectAssignmentToName(right, name);
			case EUnary(_, inner) | ECast(inner, _) | EAwait(inner):
				exprHasDirectAssignmentToName(inner, name);
			case ERange(start, end): exprHasDirectAssignmentToName(start, name) || exprHasDirectAssignmentToName(end, name);
			case EIndex(recv, index): exprHasDirectAssignmentToName(recv, name) || exprHasDirectAssignmentToName(index, name);
			case EStructLit(_, fields):
				anyFieldHasDirectAssignmentToName(fields, name);
			case EBlock(block):
				blockHasDirectAssignmentToName(block, name);
			case EIf(cond, thenExpr, elseExpr): exprHasDirectAssignmentToName(cond,
					name) || exprHasDirectAssignmentToName(thenExpr, name) || (elseExpr != null
					&& exprHasDirectAssignmentToName(elseExpr, name));
			case EMatch(scrutinee, arms): exprHasDirectAssignmentToName(scrutinee, name) || anyArmHasDirectAssignmentToName(arms, name);
			case EField(recv, _):
				exprHasDirectAssignmentToName(recv, name);
			case EPinAsyncMove(body):
				blockHasDirectAssignmentToName(body, name);
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				false;
		};
	}

	function rewriteUnusedBindingIfNeeded(stmt:RustStmt, remainingStmts:Array<RustStmt>, tail:Null<RustExpr>, nextIndex:Int):RustStmt {
		return switch (stmt) {
			case RLet(name, _, ty, expr)
				if (name != "_"
					&& !StringTools.startsWith(name, "__hx_")
					&& expr != null
					&& !blockMentionsNameAfter(remainingStmts, tail, nextIndex, name)):
				RLet("_", false, ty, expr);
			case _:
				stmt;
		};
	}

	function blockMentionsNameAfter(stmts:Array<RustStmt>, tail:Null<RustExpr>, startIndex:Int, name:String):Bool {
		for (i in startIndex...stmts.length) {
			if (stmtMentionsName(stmts[i], name))
				return true;
		}
		return tail != null && exprMentionsName(tail, name);
	}

	function stmtMentionsName(stmt:RustStmt, name:String):Bool {
		return switch (stmt) {
			case RLet(bindName, _, _, expr): bindName == name || (expr != null && exprMentionsName(expr, name));
			case RSemi(expr) | RExpr(expr, _) | RReturn(expr): expr != null && exprMentionsName(expr, name);
			case RWhile(cond, body): exprMentionsName(cond, name) || blockMentionsNameInBlock(body, name);
			case RLoop(body):
				blockMentionsNameInBlock(body, name);
			case RFor(bindName, iter, body): bindName == name || exprMentionsName(iter, name) || blockMentionsNameInBlock(body, name);
			case RBreak | RContinue:
				false;
		};
	}

	function blockMentionsNameInBlock(block:RustBlock, name:String):Bool {
		return blockMentionsNameAfter(block.stmts, block.tail, 0, name);
	}

	function exprMentionsName(expr:RustExpr, name:String):Bool {
		return switch (expr) {
			case EPath(path):
				path == name;
			case ECall(func, args): exprMentionsName(func, name) || anyExprMentionsName(args, name);
			case EMacroCall(_, args):
				anyExprMentionsName(args, name);
			case EClosure(args, body, _): arrayHasString(args, name) || blockMentionsNameInBlock(body, name);
			case EBinary(_, left, right): exprMentionsName(left, name) || exprMentionsName(right, name);
			case EUnary(_, inner) | ECast(inner, _) | EAwait(inner):
				exprMentionsName(inner, name);
			case ERange(start, end): exprMentionsName(start, name) || exprMentionsName(end, name);
			case EIndex(recv, index): exprMentionsName(recv, name) || exprMentionsName(index, name);
			case EStructLit(_, fields):
				anyFieldMentionsName(fields, name);
			case EBlock(block):
				blockMentionsNameInBlock(block, name);
			case EIf(cond, thenExpr, elseExpr): exprMentionsName(cond,
					name) || exprMentionsName(thenExpr, name) || (elseExpr != null && exprMentionsName(elseExpr, name));
			case EMatch(scrutinee, arms): exprMentionsName(scrutinee, name) || anyArmMentionsName(arms, name);
			case EAssign(lhs, rhs): exprMentionsName(lhs, name) || exprMentionsName(rhs, name);
			case EField(recv, _):
				exprMentionsName(recv, name);
			case EPinAsyncMove(body):
				blockMentionsNameInBlock(body, name);
			case ERaw(raw):
				rawMentionsName(raw, name);
			case ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
				false;
		};
	}

	function rawMentionsName(raw:String, name:String):Bool {
		if (raw == null || name == null || name.length == 0)
			return false;
		var start = 0;
		while (true) {
			var idx = raw.indexOf(name, start);
			if (idx == -1)
				return false;
			var beforeOk = idx == 0 || !isRustIdentChar(raw.charCodeAt(idx - 1));
			var end = idx + name.length;
			var afterOk = end >= raw.length || !isRustIdentChar(raw.charCodeAt(end));
			if (beforeOk && afterOk)
				return true;
			start = idx + 1;
		}
		return false;
	}

	function isRustIdentChar(code:Int):Bool {
		return (code >= "a".code && code <= "z".code)
			|| (code >= "A".code && code <= "Z".code)
			|| (code >= "0".code && code <= "9".code)
			|| code == "_".code;
	}

	function isDeadDiscardStmt(stmt:RustStmt):Bool {
		return switch (stmt) {
			case RSemi(expr) | RExpr(expr, true):
				isPureExpr(expr);
			case RExpr(EBlock(block), false): block.stmts.length == 0 && block.tail == null;
			case _:
				false;
		};
	}

	function isPureExpr(expr:RustExpr):Bool {
		return switch (expr) {
			case EPath(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
				true;
			case EField(recv, _):
				isPureExpr(recv);
			case EUnary(op, inner): (op == "!" || op == "-" || op == "&" || op == "*") && isPureExpr(inner);
			case EBinary(_, left, right): isPureExpr(left) && isPureExpr(right);
			case ERange(start, end): isPureExpr(start) && isPureExpr(end);
			case ECast(inner, _):
				isPureExpr(inner);
			case EIndex(recv, index): isPureExpr(recv) && isPureExpr(index);
			case EStructLit(_, fields):
				allFieldExprsPure(fields);
			case EBlock(block): allBlockStmtsPure(block.stmts) && (block.tail == null || isPureExpr(block.tail));
			case ERaw(_) | ECall(_, _) | EMacroCall(_, _) | EClosure(_, _, _) | EIf(_, _, _) | EMatch(_, _) | EAssign(_, _) | EPinAsyncMove(_) | EAwait(_):
				false;
		};
	}

	function allBlockStmtsPure(stmts:Array<RustStmt>):Bool {
		for (stmt in stmts) {
			if (stmtHasSideEffects(stmt))
				return false;
		}
		return true;
	}

	function stmtHasSideEffects(stmt:RustStmt):Bool {
		return switch (stmt) {
			case RLet(_, _, _, expr): expr != null && !isPureExpr(expr);
			case RSemi(expr) | RExpr(expr, _):
				!isPureExpr(expr);
			case RReturn(_) | RWhile(_, _) | RLoop(_) | RFor(_, _, _) | RBreak | RContinue:
				true;
		};
	}

	function allFieldExprsPure(fields:Array<RustStructLitField>):Bool {
		for (field in fields) {
			if (!isPureExpr(field.expr))
				return false;
		}
		return true;
	}

	function anyExprHasDirectAssignmentToName(exprs:Array<RustExpr>, name:String):Bool {
		for (expr in exprs) {
			if (exprHasDirectAssignmentToName(expr, name))
				return true;
		}
		return false;
	}

	function anyFieldHasDirectAssignmentToName(fields:Array<RustStructLitField>, name:String):Bool {
		for (field in fields) {
			if (exprHasDirectAssignmentToName(field.expr, name))
				return true;
		}
		return false;
	}

	function anyArmHasDirectAssignmentToName(arms:Array<RustMatchArm>, name:String):Bool {
		for (arm in arms) {
			if (exprHasDirectAssignmentToName(arm.expr, name))
				return true;
		}
		return false;
	}

	function anyExprMentionsName(exprs:Array<RustExpr>, name:String):Bool {
		for (expr in exprs) {
			if (exprMentionsName(expr, name))
				return true;
		}
		return false;
	}

	function anyFieldMentionsName(fields:Array<RustStructLitField>, name:String):Bool {
		for (field in fields) {
			if (exprMentionsName(field.expr, name))
				return true;
		}
		return false;
	}

	function anyArmMentionsName(arms:Array<RustMatchArm>, name:String):Bool {
		for (arm in arms) {
			if (exprMentionsName(arm.expr, name))
				return true;
		}
		return false;
	}

	function arrayHasString(values:Array<String>, name:String):Bool {
		for (value in values) {
			if (value == name)
				return true;
		}
		return false;
	}
}
