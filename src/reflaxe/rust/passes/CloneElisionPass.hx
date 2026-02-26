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
	CloneElisionPass

	Why
	- Portable/metal output should avoid redundant `.clone()` noise.
	- Elision must stay conservative so ownership/borrow behavior remains stable.

	What
	- Applies three safe clone reductions:
	  - `.clone()` on always-safe literal/value expressions.
	  - nested `.clone().clone()` collapsed to one `.clone()`.
	  - last-use local `path.clone()` in direct call arguments (outside loop/closure contexts).

	How
	- Recursively rewrites Rust AST items/functions/blocks/expressions.
	- Restricts last-use elision to top-level statement expressions that are direct calls/macros.
	- Disables last-use elision inside loops and closure/async-closure bodies to avoid move-safety drift.
**/
class CloneElisionPass implements RustPass {
	var appliedMetrics:Map<String, Int> = [];
	var skippedMetrics:Map<String, Int> = [];

	public function new() {}

	public function name():String {
		return "clone_elision";
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

	function rewriteBlock(block:RustBlock, disableLastUseElision:Bool):RustBlock {
		var stmts = [for (stmt in block.stmts) rewriteStmt(stmt, disableLastUseElision)];
		var tail = block.tail == null ? null : rewriteExpr(block.tail, disableLastUseElision);
		var rewrittenStmts = if (disableLastUseElision) {
			var skippedCandidates = countDynamicFromCloneCandidatesInStmts(stmts, tail);
			if (skippedCandidates > 0)
				recordSkipped("clone_elision.skipped.last_use_dynamic_from.disabled_context", skippedCandidates);
			stmts;
		} else {
			elideLastUseCallArgClones(stmts, tail);
		}
		return {
			stmts: rewrittenStmts,
			tail: tail
		};
	}

	function rewriteStmt(stmt:RustStmt, disableLastUseElision:Bool):RustStmt {
		return switch (stmt) {
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : rewriteExpr(expr, disableLastUseElision));
			case RSemi(expr):
				RSemi(rewriteExpr(expr, disableLastUseElision));
			case RExpr(expr, needsSemicolon):
				RExpr(rewriteExpr(expr, disableLastUseElision), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : rewriteExpr(expr, disableLastUseElision));
			case RWhile(cond, body):
				RWhile(rewriteExpr(cond, disableLastUseElision), rewriteBlock(body, true));
			case RLoop(body):
				RLoop(rewriteBlock(body, true));
			case RFor(name, iter, body):
				RFor(name, rewriteExpr(iter, disableLastUseElision), rewriteBlock(body, true));
			case RBreak | RContinue:
				stmt;
		};
	}

	function rewriteExpr(expr:RustExpr, disableLastUseElision:Bool):RustExpr {
		var rewritten = switch (expr) {
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				expr;
			case ECall(func, args):
				ECall(rewriteExpr(func, disableLastUseElision), [for (arg in args) rewriteExpr(arg, disableLastUseElision)]);
			case EMacroCall(name, args):
				EMacroCall(name, [for (arg in args) rewriteExpr(arg, disableLastUseElision)]);
			case EClosure(args, body, isMove):
				EClosure(args, rewriteBlock(body, true), isMove);
			case EBinary(op, left, right):
				EBinary(op, rewriteExpr(left, disableLastUseElision), rewriteExpr(right, disableLastUseElision));
			case EUnary(op, inner):
				EUnary(op, rewriteExpr(inner, disableLastUseElision));
			case ERange(start, end):
				ERange(rewriteExpr(start, disableLastUseElision), rewriteExpr(end, disableLastUseElision));
			case ECast(inner, ty):
				ECast(rewriteExpr(inner, disableLastUseElision), ty);
			case EIndex(recv, index):
				EIndex(rewriteExpr(recv, disableLastUseElision), rewriteExpr(index, disableLastUseElision));
			case EStructLit(path, fields):
				EStructLit(path, [for (field in fields) rewriteStructField(field, disableLastUseElision)]);
			case EBlock(block):
				EBlock(rewriteBlock(block, disableLastUseElision));
			case EIf(cond, thenExpr, elseExpr):
				EIf(rewriteExpr(cond, disableLastUseElision), rewriteExpr(thenExpr, disableLastUseElision),
					elseExpr == null ? null : rewriteExpr(elseExpr, disableLastUseElision));
			case EMatch(scrutinee, arms):
				EMatch(rewriteExpr(scrutinee, disableLastUseElision), [for (arm in arms) rewriteMatchArm(arm, disableLastUseElision)]);
			case EAssign(lhs, rhs):
				EAssign(rewriteExpr(lhs, disableLastUseElision), rewriteExpr(rhs, disableLastUseElision));
			case EField(recv, field):
				EField(rewriteExpr(recv, disableLastUseElision), field);
			case EPinAsyncMove(body):
				EPinAsyncMove(rewriteBlock(body, true));
			case EAwait(inner):
				EAwait(rewriteExpr(inner, disableLastUseElision));
		};
		return simplifyCloneExpr(rewritten);
	}

	function rewriteStructField(field:RustStructLitField, disableLastUseElision:Bool):RustStructLitField {
		return {
			name: field.name,
			expr: rewriteExpr(field.expr, disableLastUseElision)
		};
	}

	function rewriteMatchArm(arm:RustMatchArm, disableLastUseElision:Bool):RustMatchArm {
		return {
			pat: arm.pat,
			expr: rewriteExpr(arm.expr, disableLastUseElision)
		};
	}

	function simplifyCloneExpr(expr:RustExpr):RustExpr {
		return switch (expr) {
			case ECall(EField(target, "clone"), []):
				if (isAlwaysCloneSafeExpr(target)) {
					recordApplied("clone_elision.applied.literal_clone");
					target;
				} else {
					switch (target) {
						case ECall(EField(inner, "clone"), []):
							recordApplied("clone_elision.applied.nested_clone");
							ECall(EField(inner, "clone"), []);
						case _:
							expr;
					}
				}
			case _:
				expr;
		};
	}

	function isAlwaysCloneSafeExpr(expr:RustExpr):Bool {
		return switch (expr) {
			case ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
				true;
			case EUnary(_, inner):
				isAlwaysCloneSafeExpr(inner);
			case EBinary(_, left, right): isAlwaysCloneSafeExpr(left) && isAlwaysCloneSafeExpr(right);
			case ERange(start, end): isAlwaysCloneSafeExpr(start) && isAlwaysCloneSafeExpr(end);
			case ECast(inner, _):
				isAlwaysCloneSafeExpr(inner);
			case _:
				false;
		};
	}

	function elideLastUseCallArgClones(stmts:Array<RustStmt>, tail:Null<RustExpr>):Array<RustStmt> {
		var out:Array<RustStmt> = [];
		for (index in 0...stmts.length) {
			var stmt = stmts[index];
			out.push(rewriteStmtCallCloneArgs(stmt, index, stmts, tail));
		}
		return out;
	}

	function rewriteStmtCallCloneArgs(stmt:RustStmt, index:Int, stmts:Array<RustStmt>, tail:Null<RustExpr>):RustStmt {
		return switch (stmt) {
			case RSemi(expr):
				RSemi(rewriteCallCloneArgs(expr, index, stmts, tail));
			case RExpr(expr, needsSemicolon):
				RExpr(rewriteCallCloneArgs(expr, index, stmts, tail), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : rewriteCallCloneArgs(expr, index, stmts, tail));
			case RLet(_, _, _, _) | RWhile(_, _) | RLoop(_) | RFor(_, _, _) | RBreak | RContinue:
				stmt;
		};
	}

	function rewriteCallCloneArgs(expr:RustExpr, index:Int, stmts:Array<RustStmt>, tail:Null<RustExpr>):RustExpr {
		var movableLocals = collectMovableLocalsBeforeIndex(stmts, index);
		function localMoveSkipReason(name:String, ownerExpr:RustExpr):Null<String> {
			if (!movableLocals.exists(name))
				return "missing_local_binding";
			if (!movableLocals.get(name))
				return "non_movable_or_reference_typed";
			if (!isSimpleLocalPath(name))
				return "non_simple_local_path";
			if (countPathUsesInExpr(ownerExpr, name) != 1)
				return "multiple_uses_in_expr";
			if (hasPathUseAfter(stmts, tail, index, name))
				return "path_used_after_stmt";
			return null;
		}
		return rewriteDynamicFromCloneCall(expr, localName -> localMoveSkipReason(localName, expr));
	}

	function collectMovableLocalsBeforeIndex(stmts:Array<RustStmt>, index:Int):Map<String, Bool> {
		var out:Map<String, Bool> = [];
		for (i in 0...index + 1) {
			switch (stmts[i]) {
				case RLet(name, _, ty, _):
					if (ty == null) {
						out.set(name, false);
					} else {
						out.set(name, !looksReferenceType(ty));
					}
				case _:
			}
		}
		return out;
	}

	function looksReferenceType(ty:reflaxe.rust.ast.RustAST.RustType):Bool {
		return switch (ty) {
			case RRef(_, _):
				true;
			case RPath(path):
				StringTools.startsWith(StringTools.trim(path), "&");
			case RUnit | RBool | RI32 | RF64 | RString:
				false;
		};
	}

	function rewriteDynamicFromCloneCall(expr:RustExpr, localMoveSkipReason:String->Null<String>):RustExpr {
		return switch (expr) {
			case ECall(EPath("hxrt::dynamic::from"), [ECall(EField(EPath(localName), "clone"), [])]):
				var skipReason = localMoveSkipReason(localName);
				if (skipReason == null) {
					recordApplied("clone_elision.applied.last_use_dynamic_from");
					ECall(EPath("hxrt::dynamic::from"), [EPath(localName)]);
				} else {
					recordSkipped("clone_elision.skipped.last_use_dynamic_from." + skipReason);
					expr;
				}
			case ECall(func, args):
				ECall(rewriteDynamicFromCloneCall(func, localMoveSkipReason), [for (arg in args) rewriteDynamicFromCloneCall(arg, localMoveSkipReason)]);
			case EMacroCall(name, args):
				EMacroCall(name, [for (arg in args) rewriteDynamicFromCloneCall(arg, localMoveSkipReason)]);
			case EBinary(op, left, right):
				EBinary(op, rewriteDynamicFromCloneCall(left, localMoveSkipReason), rewriteDynamicFromCloneCall(right, localMoveSkipReason));
			case EUnary(op, inner):
				EUnary(op, rewriteDynamicFromCloneCall(inner, localMoveSkipReason));
			case ERange(start, end):
				ERange(rewriteDynamicFromCloneCall(start, localMoveSkipReason), rewriteDynamicFromCloneCall(end, localMoveSkipReason));
			case ECast(inner, ty):
				ECast(rewriteDynamicFromCloneCall(inner, localMoveSkipReason), ty);
			case EIndex(recv, index):
				EIndex(rewriteDynamicFromCloneCall(recv, localMoveSkipReason), rewriteDynamicFromCloneCall(index, localMoveSkipReason));
			case EStructLit(path, fields):
				EStructLit(path, [
					for (field in fields)
						{
							name: field.name,
							expr: rewriteDynamicFromCloneCall(field.expr, localMoveSkipReason)
						}
				]);
			case EBlock(block):
				EBlock({
					stmts: [for (stmt in block.stmts) rewriteDynamicFromCloneStmt(stmt, localMoveSkipReason)],
					tail: block.tail == null ? null : rewriteDynamicFromCloneCall(block.tail, localMoveSkipReason)
				});
			case EIf(cond, thenExpr, elseExpr):
				EIf(rewriteDynamicFromCloneCall(cond, localMoveSkipReason), rewriteDynamicFromCloneCall(thenExpr, localMoveSkipReason),
					elseExpr == null ? null : rewriteDynamicFromCloneCall(elseExpr, localMoveSkipReason));
			case EMatch(scrutinee, arms):
				EMatch(rewriteDynamicFromCloneCall(scrutinee, localMoveSkipReason), [
					for (arm in arms)
						{
							pat: arm.pat,
							expr: rewriteDynamicFromCloneCall(arm.expr, localMoveSkipReason)
						}
				]);
			case EAssign(lhs, rhs):
				EAssign(rewriteDynamicFromCloneCall(lhs, localMoveSkipReason), rewriteDynamicFromCloneCall(rhs, localMoveSkipReason));
			case EField(recv, field):
				EField(rewriteDynamicFromCloneCall(recv, localMoveSkipReason), field);
			case EClosure(_, _, _) | EPinAsyncMove(_) | EAwait(_) | ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				expr;
		};
	}

	function rewriteDynamicFromCloneStmt(stmt:RustStmt, localMoveSkipReason:String->Null<String>):RustStmt {
		return switch (stmt) {
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : rewriteDynamicFromCloneCall(expr, localMoveSkipReason));
			case RSemi(expr):
				RSemi(rewriteDynamicFromCloneCall(expr, localMoveSkipReason));
			case RExpr(expr, needsSemicolon):
				RExpr(rewriteDynamicFromCloneCall(expr, localMoveSkipReason), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : rewriteDynamicFromCloneCall(expr, localMoveSkipReason));
			case RWhile(cond, body):
				RWhile(rewriteDynamicFromCloneCall(cond, localMoveSkipReason), {
					stmts: [
						for (inner in body.stmts) rewriteDynamicFromCloneStmt(inner, localMoveSkipReason)
					],
					tail: body.tail == null ? null : rewriteDynamicFromCloneCall(body.tail, localMoveSkipReason)
				});
			case RLoop(body):
				RLoop({
					stmts: [
						for (inner in body.stmts) rewriteDynamicFromCloneStmt(inner, localMoveSkipReason)
					],
					tail: body.tail == null ? null : rewriteDynamicFromCloneCall(body.tail, localMoveSkipReason)
				});
			case RFor(name, iter, body):
				RFor(name, rewriteDynamicFromCloneCall(iter, localMoveSkipReason), {
					stmts: [
						for (inner in body.stmts) rewriteDynamicFromCloneStmt(inner, localMoveSkipReason)
					],
					tail: body.tail == null ? null : rewriteDynamicFromCloneCall(body.tail, localMoveSkipReason)
				});
			case RBreak | RContinue:
				stmt;
		};
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

	function isSimpleLocalPath(path:String):Bool {
		return path.indexOf("::") == -1;
	}

	function countPathUsesInStmt(stmt:RustStmt, pathName:String):Int {
		return switch (stmt) {
			case RLet(_, _, _, expr):
				expr == null ? 0 : countPathUsesInExpr(expr, pathName);
			case RSemi(expr) | RExpr(expr, _):
				countPathUsesInExpr(expr, pathName);
			case RReturn(expr):
				expr == null ? 0 : countPathUsesInExpr(expr, pathName);
			case RWhile(cond, body):
				var total = countPathUsesInExpr(cond, pathName);
				for (inner in body.stmts)
					total += countPathUsesInStmt(inner, pathName);
				if (body.tail != null)
					total += countPathUsesInExpr(body.tail, pathName);
				total;
			case RLoop(body):
				var total = 0;
				for (inner in body.stmts)
					total += countPathUsesInStmt(inner, pathName);
				if (body.tail != null)
					total += countPathUsesInExpr(body.tail, pathName);
				total;
			case RFor(_, iter, body):
				var total = countPathUsesInExpr(iter, pathName);
				for (inner in body.stmts)
					total += countPathUsesInStmt(inner, pathName);
				if (body.tail != null)
					total += countPathUsesInExpr(body.tail, pathName);
				total;
			case RBreak | RContinue:
				0;
		};
	}

	function countPathUsesInExpr(expr:RustExpr, pathName:String):Int {
		return switch (expr) {
			case EPath(p):
				p == pathName ? 1 : 0;
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
				var total = 0;
				for (stmt in body.stmts)
					total += countPathUsesInStmt(stmt, pathName);
				if (body.tail != null)
					total += countPathUsesInExpr(body.tail, pathName);
				total;
			case EBinary(_, left, right):
				countPathUsesInExpr(left, pathName) + countPathUsesInExpr(right, pathName);
			case EUnary(_, inner) | ECast(inner, _) | EAwait(inner):
				countPathUsesInExpr(inner, pathName);
			case ERange(start, end):
				countPathUsesInExpr(start, pathName) + countPathUsesInExpr(end, pathName);
			case EIndex(recv, index):
				countPathUsesInExpr(recv, pathName) + countPathUsesInExpr(index, pathName);
			case EStructLit(_, fields):
				var total = 0;
				for (field in fields)
					total += countPathUsesInExpr(field.expr, pathName);
				total;
			case EBlock(block):
				var total = 0;
				for (stmt in block.stmts)
					total += countPathUsesInStmt(stmt, pathName);
				if (block.tail != null)
					total += countPathUsesInExpr(block.tail, pathName);
				total;
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
				var total = 0;
				for (stmt in body.stmts)
					total += countPathUsesInStmt(stmt, pathName);
				if (body.tail != null)
					total += countPathUsesInExpr(body.tail, pathName);
				total;
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
				0;
		};
	}

	function countDynamicFromCloneCandidatesInStmts(stmts:Array<RustStmt>, tail:Null<RustExpr>):Int {
		var total = 0;
		for (stmt in stmts)
			total += countDynamicFromCloneCandidatesInStmt(stmt);
		if (tail != null)
			total += countDynamicFromCloneCandidatesInExpr(tail);
		return total;
	}

	function countDynamicFromCloneCandidatesInStmt(stmt:RustStmt):Int {
		return switch (stmt) {
			case RLet(_, _, _, expr):
				expr == null ? 0 : countDynamicFromCloneCandidatesInExpr(expr);
			case RSemi(expr) | RExpr(expr, _):
				countDynamicFromCloneCandidatesInExpr(expr);
			case RReturn(expr):
				expr == null ? 0 : countDynamicFromCloneCandidatesInExpr(expr);
			case RWhile(cond, body):
				var total = countDynamicFromCloneCandidatesInExpr(cond);
				for (inner in body.stmts)
					total += countDynamicFromCloneCandidatesInStmt(inner);
				if (body.tail != null)
					total += countDynamicFromCloneCandidatesInExpr(body.tail);
				total;
			case RLoop(body):
				var total = 0;
				for (inner in body.stmts)
					total += countDynamicFromCloneCandidatesInStmt(inner);
				if (body.tail != null)
					total += countDynamicFromCloneCandidatesInExpr(body.tail);
				total;
			case RFor(_, iter, body):
				var total = countDynamicFromCloneCandidatesInExpr(iter);
				for (inner in body.stmts)
					total += countDynamicFromCloneCandidatesInStmt(inner);
				if (body.tail != null)
					total += countDynamicFromCloneCandidatesInExpr(body.tail);
				total;
			case RBreak | RContinue:
				0;
		};
	}

	function countDynamicFromCloneCandidatesInExpr(expr:RustExpr):Int {
		return switch (expr) {
			case ECall(EPath("hxrt::dynamic::from"), [ECall(EField(EPath(_), "clone"), [])]):
				1;
			case ECall(func, args):
				var total = countDynamicFromCloneCandidatesInExpr(func);
				for (arg in args)
					total += countDynamicFromCloneCandidatesInExpr(arg);
				total;
			case EMacroCall(_, args):
				var total = 0;
				for (arg in args)
					total += countDynamicFromCloneCandidatesInExpr(arg);
				total;
			case EClosure(_, body, _):
				var total = 0;
				for (stmt in body.stmts)
					total += countDynamicFromCloneCandidatesInStmt(stmt);
				if (body.tail != null)
					total += countDynamicFromCloneCandidatesInExpr(body.tail);
				total;
			case EBinary(_, left, right):
				countDynamicFromCloneCandidatesInExpr(left) + countDynamicFromCloneCandidatesInExpr(right);
			case EUnary(_, inner) | ECast(inner, _) | EAwait(inner):
				countDynamicFromCloneCandidatesInExpr(inner);
			case ERange(start, end):
				countDynamicFromCloneCandidatesInExpr(start) + countDynamicFromCloneCandidatesInExpr(end);
			case EIndex(recv, index):
				countDynamicFromCloneCandidatesInExpr(recv) + countDynamicFromCloneCandidatesInExpr(index);
			case EStructLit(_, fields):
				var total = 0;
				for (field in fields)
					total += countDynamicFromCloneCandidatesInExpr(field.expr);
				total;
			case EBlock(block):
				var total = 0;
				for (stmt in block.stmts)
					total += countDynamicFromCloneCandidatesInStmt(stmt);
				if (block.tail != null)
					total += countDynamicFromCloneCandidatesInExpr(block.tail);
				total;
			case EIf(cond, thenExpr, elseExpr):
				countDynamicFromCloneCandidatesInExpr(cond) + countDynamicFromCloneCandidatesInExpr(thenExpr) +
				(elseExpr == null ? 0 : countDynamicFromCloneCandidatesInExpr(elseExpr));
			case EMatch(scrutinee, arms):
				var total = countDynamicFromCloneCandidatesInExpr(scrutinee);
				for (arm in arms)
					total += countDynamicFromCloneCandidatesInExpr(arm.expr);
				total;
			case EAssign(lhs, rhs):
				countDynamicFromCloneCandidatesInExpr(lhs) + countDynamicFromCloneCandidatesInExpr(rhs);
			case EField(recv, _):
				countDynamicFromCloneCandidatesInExpr(recv);
			case EPinAsyncMove(body):
				var total = 0;
				for (stmt in body.stmts)
					total += countDynamicFromCloneCandidatesInStmt(stmt);
				if (body.tail != null)
					total += countDynamicFromCloneCandidatesInExpr(body.tail);
				total;
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				0;
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

	function flushOptimizerMetrics(context:CompilationContext):Void {
		for (metricId => count in appliedMetrics)
			context.recordOptimizerApplied(metricId, count);
		for (reasonId => count in skippedMetrics)
			context.recordOptimizerSkipped(reasonId, count);
	}
}
