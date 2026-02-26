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
	BorrowScopeTighteningPass

	Why
	- Rust-first profiles should keep mutable/read borrows short where possible.
	- Borrow-scope work belongs in a dedicated pass pipeline stage, not ad-hoc expression codegen.

	What
	- Rewrites a conservative subset of borrow-alias patterns:
	  - `let b = recv.borrow(); <use b once>` -> `<use recv.borrow() once>`
	  - `let b = recv.borrow_mut(); <use b once>` -> `<use recv.borrow_mut() once>`
	- Supports immediate next-statement usage and block-tail usage.

	How
	- Runs after expression lowering on the Rust AST.
	- Only rewrites when all of the following hold:
	  - borrow alias is a plain `let` (non-`mut`) binding,
	  - alias is consumed exactly once,
	  - consumer is immediate (next statement or block tail),
	  - consumer expression has no closure/async-closure constructs.
	- This keeps evaluation order and ownership behavior stable while reducing artificial borrow
	  guard lifetimes introduced by temporary aliases.
**/
class BorrowScopeTighteningPass implements RustPass {
	var appliedMetrics:Map<String, Int> = [];
	var skippedMetrics:Map<String, Int> = [];

	public function new() {}

	public function name():String {
		return "borrow_scope_tightening";
	}

	public function run(file:RustFile, context:CompilationContext):RustFile {
		appliedMetrics = [];
		skippedMetrics = [];
		var rewritten:RustFile = {
			items: [for (item in file.items) rewriteItem(item)]
		};
		flushOptimizerMetrics(context);
		return rewritten;
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
			body: rewriteBlock(f.body, false)
		};
	}

	function rewriteBlock(block:RustBlock, inLoopContext:Bool):RustBlock {
		var stmts = [for (stmt in block.stmts) rewriteStmt(stmt, inLoopContext)];
		var tail = block.tail == null ? null : rewriteExpr(block.tail, inLoopContext);
		var rewrittenStmts = tightenImmediateBorrowAliases(stmts, tail, inLoopContext);
		var rewrittenTail = tail;
		if (rewrittenTail != null && rewrittenStmts.length > 0) {
			var alias = extractBorrowAlias(rewrittenStmts[rewrittenStmts.length - 1]);
			if (alias != null) {
				if (!canRewriteTailAliasTarget(alias.target)) {
					recordSkipped("borrow_scope_tightening.skipped.tail_local_target");
					recordLoopSkipped(inLoopContext, "tail_local_target");
				} else if (containsClosureExpr(rewrittenTail)) {
					recordSkipped("borrow_scope_tightening.skipped.tail_closure_consumer");
					recordLoopSkipped(inLoopContext, "tail_closure_consumer");
				} else {
					var aliasCount = countPathUsesInExpr(rewrittenTail, alias.name);
					if (aliasCount == 1) {
						rewrittenTail = replacePathInExpr(rewrittenTail, alias.name, borrowCall(alias.target, alias.method));
						rewrittenStmts.pop();
						recordApplied("borrow_scope_tightening.applied.tail_alias_inline");
						recordLoopApplied(inLoopContext, "borrow_scope_tightening_tail_alias_inline");
					} else {
						recordSkipped("borrow_scope_tightening.skipped.tail_non_single_use");
						recordLoopSkipped(inLoopContext, "tail_non_single_use");
					}
				}
			}
		}
		return {
			stmts: rewrittenStmts,
			tail: rewrittenTail
		};
	}

	function rewriteStmt(stmt:RustStmt, inLoopContext:Bool):RustStmt {
		return switch (stmt) {
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : rewriteExpr(expr, inLoopContext));
			case RSemi(expr):
				RSemi(rewriteExpr(expr, inLoopContext));
			case RExpr(expr, needsSemicolon):
				RExpr(rewriteExpr(expr, inLoopContext), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : rewriteExpr(expr, inLoopContext));
			case RWhile(cond, body):
				RWhile(rewriteExpr(cond, inLoopContext), rewriteBlock(body, true));
			case RLoop(body):
				RLoop(rewriteBlock(body, true));
			case RFor(name, iter, body):
				RFor(name, rewriteExpr(iter, inLoopContext), rewriteBlock(body, true));
			case RBreak | RContinue:
				stmt;
		};
	}

	function rewriteExpr(expr:RustExpr, inLoopContext:Bool):RustExpr {
		var rewritten = switch (expr) {
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				expr;
			case ECall(func, args):
				ECall(rewriteExpr(func, inLoopContext), [for (arg in args) rewriteExpr(arg, inLoopContext)]);
			case EMacroCall(name, args):
				EMacroCall(name, [for (arg in args) rewriteExpr(arg, inLoopContext)]);
			case EClosure(args, body, isMove):
				EClosure(args, rewriteBlock(body, false), isMove);
			case EBinary(op, left, right):
				EBinary(op, rewriteExpr(left, inLoopContext), rewriteExpr(right, inLoopContext));
			case EUnary(op, inner):
				EUnary(op, rewriteExpr(inner, inLoopContext));
			case ERange(start, end):
				ERange(rewriteExpr(start, inLoopContext), rewriteExpr(end, inLoopContext));
			case ECast(inner, ty):
				ECast(rewriteExpr(inner, inLoopContext), ty);
			case EIndex(recv, index):
				EIndex(rewriteExpr(recv, inLoopContext), rewriteExpr(index, inLoopContext));
			case EStructLit(path, fields):
				EStructLit(path, [for (field in fields) rewriteStructField(field, inLoopContext)]);
			case EBlock(innerBlock):
				EBlock(rewriteBlock(innerBlock, inLoopContext));
			case EIf(cond, thenExpr, elseExpr):
				EIf(rewriteExpr(cond, inLoopContext), rewriteExpr(thenExpr, inLoopContext), elseExpr == null ? null : rewriteExpr(elseExpr, inLoopContext));
			case EMatch(scrutinee, arms):
				EMatch(rewriteExpr(scrutinee, inLoopContext), [for (arm in arms) rewriteMatchArm(arm, inLoopContext)]);
			case EAssign(lhs, rhs):
				EAssign(rewriteExpr(lhs, inLoopContext), rewriteExpr(rhs, inLoopContext));
			case EField(recv, field):
				EField(rewriteExpr(recv, inLoopContext), field);
			case EPinAsyncMove(body):
				EPinAsyncMove(rewriteBlock(body, false));
			case EAwait(inner):
				EAwait(rewriteExpr(inner, inLoopContext));
		};
		return simplifyExpr(rewritten);
	}

	function simplifyExpr(expr:RustExpr):RustExpr {
		return switch (expr) {
			case EBlock(block):
				if (block.stmts.length == 0 && block.tail != null) block.tail else expr;
			case _:
				expr;
		};
	}

	function rewriteStructField(field:RustStructLitField, inLoopContext:Bool):RustStructLitField {
		return {
			name: field.name,
			expr: rewriteExpr(field.expr, inLoopContext)
		};
	}

	function rewriteMatchArm(arm:RustMatchArm, inLoopContext:Bool):RustMatchArm {
		return {
			pat: arm.pat,
			expr: rewriteExpr(arm.expr, inLoopContext)
		};
	}

	function tightenImmediateBorrowAliases(stmts:Array<RustStmt>, tail:Null<RustExpr>, inLoopContext:Bool):Array<RustStmt> {
		var out:Array<RustStmt> = [];
		var i = 0;
		while (i < stmts.length) {
			var current = stmts[i];
			if (i + 1 < stmts.length) {
				var alias = extractBorrowAlias(current);
				if (alias != null) {
					var nextStmt = stmts[i + 1];
					var tightened = rewriteConsumerStmt(nextStmt, alias.name, alias.target, alias.method);
					if (tightened == null) {
						recordSkipped("borrow_scope_tightening.skipped.consumer_not_rewritable");
						recordLoopSkipped(inLoopContext, "consumer_not_rewritable");
					} else if (hasPathUseAfter(stmts, tail, i + 1, alias.name)) {
						recordSkipped("borrow_scope_tightening.skipped.alias_used_after_consumer");
						recordLoopSkipped(inLoopContext, "alias_used_after_consumer");
					} else {
						recordApplied("borrow_scope_tightening.applied.immediate_alias_inline");
						recordLoopApplied(inLoopContext, "borrow_scope_tightening_immediate_alias_inline");
						out.push(tightened);
						i += 2;
						continue;
					}
				}
			}
			out.push(current);
			i += 1;
		}
		return out;
	}

	function hasPathUseAfter(stmts:Array<RustStmt>, tail:Null<RustExpr>, fromIndex:Int, pathName:String):Bool {
		var i = fromIndex + 1;
		while (i < stmts.length) {
			if (countPathUsesInStmt(stmts[i], pathName) > 0)
				return true;
			i += 1;
		}
		if (tail != null && countPathUsesInExpr(tail, pathName) > 0)
			return true;
		return false;
	}

	function rewriteConsumerStmt(stmt:RustStmt, aliasName:String, target:RustExpr, method:String):Null<RustStmt> {
		var replacement = borrowCall(target, method);
		return switch (stmt) {
			case RSemi(expr):
				rewriteConsumerExprStmt(expr, aliasName, replacement, e -> RSemi(e));
			case RExpr(expr, needsSemicolon):
				rewriteConsumerExprStmt(expr, aliasName, replacement, e -> RExpr(e, needsSemicolon));
			case RReturn(expr):
				if (expr == null) null else rewriteConsumerExprStmt(expr, aliasName, replacement, e -> RReturn(e));
			case RLet(name, mutable, ty, expr):
				if (name == aliasName || expr == null) {
					null;
				} else {
					rewriteConsumerExprStmt(expr, aliasName, replacement, e -> RLet(name, mutable, ty, e));
				}
			case RWhile(_, _) | RLoop(_) | RFor(_, _, _) | RBreak | RContinue:
				null;
		};
	}

	function rewriteConsumerExprStmt(expr:RustExpr, aliasName:String, replacement:RustExpr, wrap:RustExpr->RustStmt):Null<RustStmt> {
		if (containsClosureExpr(expr))
			return null;
		var uses = countPathUsesInExpr(expr, aliasName);
		if (uses != 1)
			return null;
		return wrap(replacePathInExpr(expr, aliasName, replacement));
	}

	/**
		Why
		- Rust drops temporaries in block-tail expressions after local bindings in the same block.
		- Rewriting `let b = local.borrow(); b.field` to `local.borrow().field` at block tail can
		  trigger `E0597` when `local` is dropped before the temporary borrow guard.

		What
		- Restricts tail rewrites to non-local borrow targets.

		How
		- Skip tail alias rewrites when the borrow receiver is a plain local path (`EPath`).
		- Immediate next-statement rewrites remain enabled; they do not rely on block-tail drop order.
	**/
	function canRewriteTailAliasTarget(target:RustExpr):Bool {
		return switch (target) {
			case EPath(_):
				false;
			case _:
				true;
		};
	}

	function extractBorrowAlias(stmt:RustStmt):Null<{name:String, target:RustExpr, method:String}> {
		return switch (stmt) {
			case RLet(name, mutable, _, expr):
				if (mutable || expr == null) {
					null;
				} else {
					switch (expr) {
						case ECall(EField(target, method), []):
							if (method != "borrow" && method != "borrow_mut") {
								null;
							} else {
								{
									name: name,
									target: target,
									method: method
								};
							}
						case _:
							null;
					}
				}
			case _:
				null;
		};
	}

	inline function borrowCall(target:RustExpr, method:String):RustExpr {
		return ECall(EField(target, method), []);
	}

	function countPathUsesInExpr(expr:RustExpr, pathName:String):Int {
		return switch (expr) {
			case EPath(path):
				path == pathName ? 1 : 0;
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
				0;
			case ECall(func, args):
				var total = countPathUsesInExpr(func, pathName);
				for (arg in args)
					total += countPathUsesInExpr(arg, pathName);
				total;
			case EMacroCall(_, args):
				var total = 0;
				for (arg in args)
					total += countPathUsesInExpr(arg, pathName);
				total;
			case EClosure(_, body, _):
				countPathUsesInBlock(body, pathName);
			case EBinary(_, left, right):
				countPathUsesInExpr(left, pathName) + countPathUsesInExpr(right, pathName);
			case EUnary(_, inner):
				countPathUsesInExpr(inner, pathName);
			case ERange(start, end):
				countPathUsesInExpr(start, pathName) + countPathUsesInExpr(end, pathName);
			case ECast(inner, _):
				countPathUsesInExpr(inner, pathName);
			case EIndex(recv, index):
				countPathUsesInExpr(recv, pathName) + countPathUsesInExpr(index, pathName);
			case EStructLit(_, fields):
				var total = 0;
				for (field in fields)
					total += countPathUsesInExpr(field.expr, pathName);
				total;
			case EBlock(block):
				countPathUsesInBlock(block, pathName);
			case EIf(cond, thenExpr, elseExpr):
				countPathUsesInExpr(cond,
					pathName) + countPathUsesInExpr(thenExpr, pathName) + (elseExpr == null ? 0 : countPathUsesInExpr(elseExpr, pathName));
			case EMatch(scrutinee, arms):
				var total = countPathUsesInExpr(scrutinee, pathName);
				for (arm in arms)
					total += countPathUsesInExpr(arm.expr, pathName);
				total;
			case EAssign(lhs, rhs):
				countPathUsesInExpr(lhs, pathName) + countPathUsesInExpr(rhs, pathName);
			case EField(recv, _):
				countPathUsesInExpr(recv, pathName);
			case EPinAsyncMove(body):
				countPathUsesInBlock(body, pathName);
			case EAwait(inner):
				countPathUsesInExpr(inner, pathName);
		};
	}

	function countPathUsesInBlock(block:RustBlock, pathName:String):Int {
		var total = 0;
		for (stmt in block.stmts)
			total += countPathUsesInStmt(stmt, pathName);
		if (block.tail != null)
			total += countPathUsesInExpr(block.tail, pathName);
		return total;
	}

	function countPathUsesInStmt(stmt:RustStmt, pathName:String):Int {
		return switch (stmt) {
			case RLet(_, _, _, expr):
				expr == null ? 0 : countPathUsesInExpr(expr, pathName);
			case RSemi(expr):
				countPathUsesInExpr(expr, pathName);
			case RExpr(expr, _):
				countPathUsesInExpr(expr, pathName);
			case RReturn(expr):
				expr == null ? 0 : countPathUsesInExpr(expr, pathName);
			case RWhile(cond, body):
				countPathUsesInExpr(cond, pathName) + countPathUsesInBlock(body, pathName);
			case RLoop(body):
				countPathUsesInBlock(body, pathName);
			case RFor(_, iter, body):
				countPathUsesInExpr(iter, pathName) + countPathUsesInBlock(body, pathName);
			case RBreak | RContinue:
				0;
		};
	}

	function containsClosureExpr(expr:RustExpr):Bool {
		return switch (expr) {
			case EClosure(_, _, _) | EPinAsyncMove(_):
				true;
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				false;
			case ECall(func, args):
				if (containsClosureExpr(func)) true else {
					var found = false;
					for (arg in args)
						if (containsClosureExpr(arg)) {
							found = true;
							break;
						}
					found;
				}
			case EMacroCall(_, args):
				var found = false;
				for (arg in args)
					if (containsClosureExpr(arg)) {
						found = true;
						break;
					}
				found;
			case EBinary(_, left, right): containsClosureExpr(left) || containsClosureExpr(right);
			case EUnary(_, inner):
				containsClosureExpr(inner);
			case ERange(start, end): containsClosureExpr(start) || containsClosureExpr(end);
			case ECast(inner, _):
				containsClosureExpr(inner);
			case EIndex(recv, index): containsClosureExpr(recv) || containsClosureExpr(index);
			case EStructLit(_, fields):
				var found = false;
				for (field in fields)
					if (containsClosureExpr(field.expr)) {
						found = true;
						break;
					}
				found;
			case EBlock(block):
				containsClosureBlock(block);
			case EIf(cond, thenExpr, elseExpr): containsClosureExpr(cond) || containsClosureExpr(thenExpr) || (elseExpr != null
					&& containsClosureExpr(elseExpr));
			case EMatch(scrutinee, arms):
				if (containsClosureExpr(scrutinee)) true else {
					var found = false;
					for (arm in arms)
						if (containsClosureExpr(arm.expr)) {
							found = true;
							break;
						}
					found;
				}
			case EAssign(lhs, rhs): containsClosureExpr(lhs) || containsClosureExpr(rhs);
			case EField(recv, _):
				containsClosureExpr(recv);
			case EAwait(inner):
				containsClosureExpr(inner);
		};
	}

	function containsClosureBlock(block:RustBlock):Bool {
		for (stmt in block.stmts)
			if (containsClosureStmt(stmt))
				return true;
		return block.tail != null && containsClosureExpr(block.tail);
	}

	function containsClosureStmt(stmt:RustStmt):Bool {
		return switch (stmt) {
			case RLet(_, _, _, expr): expr != null && containsClosureExpr(expr);
			case RSemi(expr):
				containsClosureExpr(expr);
			case RExpr(expr, _):
				containsClosureExpr(expr);
			case RReturn(expr): expr != null && containsClosureExpr(expr);
			case RWhile(cond, body): containsClosureExpr(cond) || containsClosureBlock(body);
			case RLoop(body):
				containsClosureBlock(body);
			case RFor(_, iter, body): containsClosureExpr(iter) || containsClosureBlock(body);
			case RBreak | RContinue:
				false;
		};
	}

	function replacePathInExpr(expr:RustExpr, pathName:String, replacement:RustExpr):RustExpr {
		return switch (expr) {
			case EPath(path):
				path == pathName ? replacement : expr;
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
				expr;
			case ECall(func, args):
				ECall(replacePathInExpr(func, pathName, replacement), [for (arg in args) replacePathInExpr(arg, pathName, replacement)]);
			case EMacroCall(name, args):
				EMacroCall(name, [for (arg in args) replacePathInExpr(arg, pathName, replacement)]);
			case EClosure(args, body, isMove):
				EClosure(args, replacePathInBlock(body, pathName, replacement), isMove);
			case EBinary(op, left, right):
				EBinary(op, replacePathInExpr(left, pathName, replacement), replacePathInExpr(right, pathName, replacement));
			case EUnary(op, inner):
				EUnary(op, replacePathInExpr(inner, pathName, replacement));
			case ERange(start, end):
				ERange(replacePathInExpr(start, pathName, replacement), replacePathInExpr(end, pathName, replacement));
			case ECast(inner, ty):
				ECast(replacePathInExpr(inner, pathName, replacement), ty);
			case EIndex(recv, index):
				EIndex(replacePathInExpr(recv, pathName, replacement), replacePathInExpr(index, pathName, replacement));
			case EStructLit(path, fields):
				EStructLit(path, [
					for (field in fields)
						{
							name: field.name,
							expr: replacePathInExpr(field.expr, pathName, replacement)
						}
				]);
			case EBlock(block):
				EBlock(replacePathInBlock(block, pathName, replacement));
			case EIf(cond, thenExpr, elseExpr):
				EIf(replacePathInExpr(cond, pathName, replacement), replacePathInExpr(thenExpr, pathName, replacement),
					elseExpr == null ? null : replacePathInExpr(elseExpr, pathName, replacement));
			case EMatch(scrutinee, arms):
				EMatch(replacePathInExpr(scrutinee, pathName, replacement), [
					for (arm in arms)
						{
							pat: arm.pat,
							expr: replacePathInExpr(arm.expr, pathName, replacement)
						}
				]);
			case EAssign(lhs, rhs):
				EAssign(replacePathInExpr(lhs, pathName, replacement), replacePathInExpr(rhs, pathName, replacement));
			case EField(recv, field):
				EField(replacePathInExpr(recv, pathName, replacement), field);
			case EPinAsyncMove(body):
				EPinAsyncMove(replacePathInBlock(body, pathName, replacement));
			case EAwait(inner):
				EAwait(replacePathInExpr(inner, pathName, replacement));
		};
	}

	function replacePathInBlock(block:RustBlock, pathName:String, replacement:RustExpr):RustBlock {
		return {
			stmts: [for (stmt in block.stmts) replacePathInStmt(stmt, pathName, replacement)],
			tail: block.tail == null ? null : replacePathInExpr(block.tail, pathName, replacement)
		};
	}

	function replacePathInStmt(stmt:RustStmt, pathName:String, replacement:RustExpr):RustStmt {
		return switch (stmt) {
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : replacePathInExpr(expr, pathName, replacement));
			case RSemi(expr):
				RSemi(replacePathInExpr(expr, pathName, replacement));
			case RExpr(expr, needsSemicolon):
				RExpr(replacePathInExpr(expr, pathName, replacement), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : replacePathInExpr(expr, pathName, replacement));
			case RWhile(cond, body):
				RWhile(replacePathInExpr(cond, pathName, replacement), replacePathInBlock(body, pathName, replacement));
			case RLoop(body):
				RLoop(replacePathInBlock(body, pathName, replacement));
			case RFor(name, iter, body):
				RFor(name, replacePathInExpr(iter, pathName, replacement), replacePathInBlock(body, pathName, replacement));
			case RBreak | RContinue:
				stmt;
		};
	}

	inline function recordApplied(metricId:String, count:Int = 1):Void {
		if (metricId == null || metricId.length == 0 || count <= 0)
			return;
		appliedMetrics.set(metricId, (appliedMetrics.exists(metricId) ? appliedMetrics.get(metricId) : 0) + count);
	}

	inline function recordSkipped(reasonId:String, count:Int = 1):Void {
		if (reasonId == null || reasonId.length == 0 || count <= 0)
			return;
		skippedMetrics.set(reasonId, (skippedMetrics.exists(reasonId) ? skippedMetrics.get(reasonId) : 0) + count);
	}

	inline function recordLoopApplied(inLoopContext:Bool, metricSuffix:String):Void {
		if (!inLoopContext)
			return;
		recordApplied("loop_optimizations.applied." + metricSuffix);
	}

	inline function recordLoopSkipped(inLoopContext:Bool, reasonSuffix:String):Void {
		if (!inLoopContext)
			return;
		recordSkipped("loop_optimizations.skipped." + reasonSuffix);
	}

	function flushOptimizerMetrics(context:CompilationContext):Void {
		for (metricId => count in appliedMetrics)
			context.recordOptimizerApplied(metricId, count);
		for (reasonId => count in skippedMetrics)
			context.recordOptimizerSkipped(reasonId, count);
	}
}
