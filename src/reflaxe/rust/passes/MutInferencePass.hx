package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustAssociatedItem;
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustFunction;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustMatchArm;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustStructLitField;
import reflaxe.rust.ast.RustPathAnalysis;

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
	- Tracks structural closure/match patterns plus nested `let` and `for` bindings while walking
	  expressions, evaluating initializers/iterables before each new lexical shadow enters scope.
	- Counts captured closure and async-move writes as repeated mutation evidence so declaration-only
	  initialization cannot erase required outer mutability.
	- After a block is rewritten, collect mutable-binding requirements from that block and its nested
	  expressions, then normalize only that block's own `RLet` statements.
	- Existing `mutable = true` flags are preserved because the typed compiler pass knows about source
	  metadata such as `@:rustMutating`, which is not recoverable from the lowered Rust AST alone.
	- Real mutation signals are:
	  - direct assignment (`name = ...`)
	  - index-root assignment (`name[..] = ...`)
	  - explicit mutable reference use (`&mut name`)
	  - bindings initialized from an exact, argument-free `borrow_mut()` member call
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
			case RAttributed(value):
				RAttributed(value.withTarget(rewriteItem(value.target)));
			case RModule(declaration):
				if (!declaration.isInline)
					item;
				else
					RModule(declaration.withItems([for (child in declaration) rewriteItem(child)]));
			case RFn(f):
				RFn(rewriteFunction(f));
			case RTrait(declaration):
				RTrait(declaration.withItems([for (associated in declaration) rewriteAssociatedItem(associated)]));
			case RImpl(i):
				RImpl(i.withItems([for (associated in i) rewriteAssociatedItem(associated)]));
			case RInnerAttribute(_) | RComment(_) | RUse(_) | RConst(_) | RStatic(_) | RTypeAlias(_) | RStruct(_) | REnum(_) | RRaw(_):
				item;
		};
	}

	function rewriteAssociatedItem(item:RustAssociatedItem):RustAssociatedItem {
		return switch (item) {
			case AssocFunction(method):
				method.body == null ? item : AssocFunction(method.withBody(rewriteBlock(method.body)));
			case AssocType(_) | AssocConst(_) | AssocRaw(_): item;
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
			case ERaw(_) | ESelf | ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
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
		var hardMutable:Map<String, Bool> = [];
		var declarationOnly:Map<String, Bool> = [];
		var visitExpr:RustExpr->Void = null;
		var visitStmt:RustStmt->Bool->Void = null;
		var visitBlock:RustBlock->Bool->Void = null;
		var shadowPatterns:Array<RustPattern> = [];
		var shadowNames:Array<String> = [];

		function isLexicallyShadowed(name:String):Bool {
			for (shadowName in shadowNames) {
				if (shadowName == name)
					return true;
			}
			for (pattern in shadowPatterns) {
				if (RustPathAnalysis.patternBindsName(pattern, name))
					return true;
			}
			return false;
		}

		/**
			Why
			- Rust allows `let x; x = value;` without `mut` when that assignment is the first and only
			  write along each execution path.
			- Branch initialization (`if (...) x = a else x = b`) is common in Haxe stdlib code and should
			  not be reclassified as mutation just because the lowered Rust AST contains assignments.

			What
			- Track declaration-only locals in the current block before scanning mutation evidence.

			How
			- After collecting assignment evidence, path-count direct writes for declaration-only locals.
			  If no path writes more than once and no hard mutability signal (`&mut`, `borrow_mut`) exists,
			  remove the synthetic mutability requirement.
		**/
		function collectDeclarationOnly(stmt:RustStmt):Void {
			switch (stmt) {
				case RLet(name, _, _, null) if (name != "_"):
					declarationOnly.set(name, true);
				case _:
			}
		}

		for (stmt in block.stmts)
			collectDeclarationOnly(stmt);

		visitExpr = function(expr:RustExpr):Void {
			switch (expr) {
				case EAssign(lhs, rhs):
					markAssignmentTarget(lhs, out, isLexicallyShadowed);
					visitExpr(rhs);
				case ECall(func, args):
					visitExpr(func);
					for (arg in args)
						visitExpr(arg);
				case EMacroCall(_, args):
					for (arg in args)
						visitExpr(arg);
				case EClosure(parameters, body, _):
					for (parameter in parameters)
						shadowPatterns.push(parameter.patternValue);
					visitBlock(body, false);
					for (_ in parameters)
						shadowPatterns.pop();
				case EBinary(_, left, right):
					visitExpr(left);
					visitExpr(right);
				case EUnary(op, inner):
					switch (inner) {
						case EPath(path):
							if (StringTools.startsWith(op, "&mut")) {
								var name = RustPathAnalysis.localIdentifierName(path);
								if (name != null && !isLexicallyShadowed(name)) {
									out.set(name, true);
									hardMutable.set(name, true);
								}
							}
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
					visitBlock(innerBlock, false);
				case EIf(cond, thenExpr, elseExpr):
					visitExpr(cond);
					visitExpr(thenExpr);
					if (elseExpr != null)
						visitExpr(elseExpr);
				case EMatch(scrutinee, arms):
					visitExpr(scrutinee);
					for (arm in arms) {
						shadowPatterns.push(arm.pat);
						visitExpr(arm.expr);
						shadowPatterns.pop();
					}
				case EField(recv, _):
					visitExpr(recv);
				case EPinAsyncMove(body):
					visitBlock(body, false);
				case EAwait(inner):
					visitExpr(inner);
				case ERaw(_) | ESelf | ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
			}
		};

		visitStmt = function(stmt:RustStmt, collectOwnLetEvidence:Bool):Void {
			switch (stmt) {
				case RLet(name, _, _, expr):
					if (expr != null) {
						if (collectOwnLetEvidence && exprProducesMutableGuard(expr) && !isLexicallyShadowed(name)) {
							out.set(name, true);
							hardMutable.set(name, true);
						}
						visitExpr(expr);
					}
				case RSemi(expr) | RExpr(expr, _):
					visitExpr(expr);
				case RReturn(expr):
					if (expr != null)
						visitExpr(expr);
				case RWhile(cond, body):
					visitExpr(cond);
					visitBlock(body, false);
				case RLoop(body):
					visitBlock(body, false);
				case RFor(name, iter, body):
					visitExpr(iter);
					var shadows = name != "_";
					if (shadows)
						shadowNames.push(name);
					visitBlock(body, false);
					if (shadows)
						shadowNames.pop();
				case RBreak | RContinue:
			}
		};

		visitBlock = function(innerBlock:RustBlock, isRootBlock:Bool):Void {
			var localShadowCount = 0;
			for (stmt in innerBlock.stmts) {
				// A Rust let initializer is evaluated before its new binding enters scope. The fresh nested
				// block has already been rewritten independently, so only the root collector owns direct
				// borrow-guard evidence for the let itself.
				visitStmt(stmt, isRootBlock);
				if (!isRootBlock) {
					switch (stmt) {
						case RLet(name, _, _, _) if (name != "_"):
							shadowNames.push(name);
							localShadowCount++;
						case _:
					}
				}
			}
			if (innerBlock.tail != null)
				visitExpr(innerBlock.tail);
			for (_ in 0...localShadowCount)
				shadowNames.pop();
		};

		visitBlock(block, true);
		for (name in declarationOnly.keys()) {
			if (out.exists(name) && !hardMutable.exists(name) && maxDirectWritesOnPathInBlock(block, name, true) <= 1)
				out.remove(name);
		}
		return out;
	}

	/**
		Counts writes to one binding along the busiest control-flow path while respecting nested binders.

		Why
		- Declaration-only `let x;` needs no `mut` for one initialization, but a later closure/async
		  capture or repeated path write does.
		- A nested `let x`, `for x`, closure parameter, or match pattern changes which declaration that
		  spelling denotes; counting by text without its lexical boundary creates false evidence.

		What
		- Preserves the first declaration-only root binding when requested, visits a nested `let`
		  initializer before installing its shadow, and stops counting that nested name afterward.

		How
		- Root callers pass `preserveDeclarationOnlyRoot = true`; every recursive block passes `false`.
		- Any captured write in a closure or async-move body is conservatively worth two writes because
		  Rust requires the captured source binding to be mutable and the body may execute later/repeatedly.
	**/
	function maxDirectWritesOnPathInBlock(block:RustBlock, target:String, preserveDeclarationOnlyRoot:Bool):Int {
		var total = 0;
		var targetShadowed = false;
		var preservedRootDeclaration = false;
		for (stmt in block.stmts) {
			if (targetShadowed)
				break;
			total += maxDirectWritesOnPathInStmt(stmt, target);
			switch (stmt) {
				case RLet(name, _, _, expr) if (name == target):
					if (preserveDeclarationOnlyRoot && !preservedRootDeclaration && expr == null)
						preservedRootDeclaration = true;
					else
						targetShadowed = true;
				case _:
			}
		}
		if (!targetShadowed && block.tail != null)
			total += maxDirectWritesOnPathInExpr(block.tail, target);
		return total;
	}

	function maxDirectWritesOnPathInStmt(stmt:RustStmt, target:String):Int {
		return switch (stmt) {
			case RLet(_, _, _, expr):
				expr == null ? 0 : maxDirectWritesOnPathInExpr(expr, target);
			case RSemi(expr) | RExpr(expr, _):
				maxDirectWritesOnPathInExpr(expr, target);
			case RReturn(expr):
				expr == null ? 0 : maxDirectWritesOnPathInExpr(expr, target);
			case RWhile(cond, body):
				(maxDirectWritesOnPathInExpr(cond, target) > 0 || maxDirectWritesOnPathInBlock(body, target, false) > 0) ? 2 : 0;
			case RLoop(body):
				maxDirectWritesOnPathInBlock(body, target, false) > 0 ? 2 : 0;
			case RFor(name, iter, body):
				var iterWrites = maxDirectWritesOnPathInExpr(iter, target);
				var bodyWrites = name == target ? 0 : maxDirectWritesOnPathInBlock(body, target, false);
				(iterWrites > 0 || bodyWrites > 0) ? 2 : 0;
			case RBreak | RContinue:
				0;
		}
	}

	function maxDirectWritesOnPathInExpr(expr:RustExpr, target:String):Int {
		return switch (expr) {
			case EAssign(lhs, rhs):
				(directAssignsTarget(lhs, target) ? 1 : 0) + maxDirectWritesOnPathInExpr(rhs, target);
			case ECall(func, args):
				maxDirectWritesOnPathInExpr(func, target) + sumMaxExprWrites(args, target);
			case EMacroCall(_, args):
				sumMaxExprWrites(args, target);
			case EClosure(parameters, body, _):
				if (RustPathAnalysis.closureParametersBindName(parameters, target)) {
					0;
				} else {
					maxDirectWritesOnPathInBlock(body, target, false) > 0 ? 2 : 0;
				}
			case EBinary(_, left, right):
				maxDirectWritesOnPathInExpr(left, target) + maxDirectWritesOnPathInExpr(right, target);
			case EUnary(_, inner):
				maxDirectWritesOnPathInExpr(inner, target);
			case ERange(start, end):
				maxDirectWritesOnPathInExpr(start, target) + maxDirectWritesOnPathInExpr(end, target);
			case ECast(inner, _):
				maxDirectWritesOnPathInExpr(inner, target);
			case EIndex(recv, index):
				maxDirectWritesOnPathInExpr(recv, target) + maxDirectWritesOnPathInExpr(index, target);
			case EStructLit(_, fields):
				var total = 0;
				for (field in fields)
					total += maxDirectWritesOnPathInExpr(field.expr, target);
				total;
			case EBlock(innerBlock):
				maxDirectWritesOnPathInBlock(innerBlock, target, false);
			case EIf(cond, thenExpr, elseExpr):
				var elseWrites = elseExpr == null ? 0 : maxDirectWritesOnPathInExpr(elseExpr, target);
				maxDirectWritesOnPathInExpr(cond, target) + Std.int(Math.max(maxDirectWritesOnPathInExpr(thenExpr, target), elseWrites));
			case EMatch(scrutinee, arms):
				var armMax = 0;
				for (arm in arms) {
					var writes = RustPathAnalysis.patternBindsName(arm.pat, target) ? 0 : maxDirectWritesOnPathInExpr(arm.expr, target);
					if (writes > armMax)
						armMax = writes;
				}
				maxDirectWritesOnPathInExpr(scrutinee, target) + armMax;
			case EField(recv, _):
				maxDirectWritesOnPathInExpr(recv, target);
			case EPinAsyncMove(body):
				maxDirectWritesOnPathInBlock(body, target, false) > 0 ? 2 : 0;
			case EAwait(inner):
				maxDirectWritesOnPathInExpr(inner, target);
			case ERaw(_) | ESelf | ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				0;
		}
	}

	function sumMaxExprWrites(exprs:Array<RustExpr>, target:String):Int {
		var total = 0;
		for (expr in exprs)
			total += maxDirectWritesOnPathInExpr(expr, target);
		return total;
	}

	function directAssignsTarget(lhs:RustExpr, target:String):Bool {
		return switch (lhs) {
			case EPath(path):
				RustPathAnalysis.localIdentifierName(path) == target;
			case _:
				false;
		}
	}

	function exprProducesMutableGuard(expr:RustExpr):Bool {
		return switch (expr) {
			case ECall(EField(_, member), []) if (RustPathAnalysis.matchesPlainMember(member, "borrow_mut")):
				true;
			case _:
				false;
		};
	}

	function markAssignmentTarget(lhs:RustExpr, out:Map<String, Bool>, isShadowed:String->Bool):Void {
		switch (lhs) {
			case EPath(path):
				var name = RustPathAnalysis.localIdentifierName(path);
				if (name != null && !isShadowed(name))
					out.set(name, true);
			case EIndex(recv, _):
				markAssignmentTarget(recv, out, isShadowed);
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
