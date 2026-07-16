package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustAssociatedItem;
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustFunction;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustMatchArm;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustStructLitField;
import reflaxe.rust.ast.RustPathAnalysis;

/**
	CloneElisionPass

	Why
	- Portable/metal output should avoid redundant `.clone()` noise.
	- Elision must stay conservative so ownership/borrow behavior remains stable.

	What
	- Applies three safe clone reductions:
	  - `.clone()` on always-safe literal/value expressions.
	  - nested `.clone().clone()` collapsed to one `.clone()`.
	  - last-use local `path.clone()` used as a `match` scrutinee (outside loop/closure contexts).
	  - last-use local `path.clone()` boxed via `hxrt::dynamic::from(...)` (outside loop/closure contexts).

	How
	- Recursively rewrites Rust AST items/functions/blocks/expressions, including trait default bodies
	  and associated constant initializers.
	- Recognizes only an argument-free structural `clone` member; a generic member with the same name
	  is not an optimization candidate.
	- Excludes paths shadowed by closure parameters, match-arm patterns, sequential `let` bindings, or
	  `for` binders from outer-local use counts and rewrite evidence.
	- Restricts last-use elision to top-level statement expressions where the move site is explicit
	  and the local is not used later (`match` scrutinees, `hxrt::dynamic::from(...)`).
	- Disables last-use elision inside loops and closure/async-closure bodies to avoid move-safety drift.
**/
class CloneElisionPass implements RustPass {
	var appliedMetrics:Map<String, Int> = [];
	var skippedMetrics:Map<String, Int> = [];
	var currentMovableBindings:Map<String, Bool> = [];

	public function new() {}

	public function name():String {
		return "clone_elision";
	}

	public function run(file:RustFile, context:CompilationContext):RustFile {
		appliedMetrics = [];
		skippedMetrics = [];
		currentMovableBindings = [];
		var rewritten:RustFile = {
			items: [for (item in file.items) rewriteItem(item)]
		};
		flushOptimizerMetrics(context);
		return rewritten;
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
				if (method.body == null) {
					item;
				} else {
					var previous = currentMovableBindings;
					currentMovableBindings = [];
					if (method.receiver != null)
						currentMovableBindings.set("self", false);
					for (parameter in method)
						currentMovableBindings.set(parameter.name.name, !looksReferenceType(parameter.type));
					var body = rewriteBlock(method.body, false);
					currentMovableBindings = previous;
					AssocFunction(method.withBody(body));
				}
			case AssocConst(declaration):
				if (declaration.value == null) {
					item;
				} else {
					var previous = currentMovableBindings;
					currentMovableBindings = [];
					var value = rewriteExpr(declaration.value, false);
					currentMovableBindings = previous;
					AssocConst(declaration.withValue(value));
				}
			case AssocType(_) | AssocRaw(_): item;
		};
	}

	function rewriteFunction(f:RustFunction):RustFunction {
		var prevMovableBindings = currentMovableBindings;
		currentMovableBindings = [];
		for (arg in f.args) {
			currentMovableBindings.set(arg.name, !looksReferenceType(arg.ty));
		}
		var body = rewriteBlock(f.body, false);
		currentMovableBindings = prevMovableBindings;
		return {
			name: f.name,
			isPub: f.isPub,
			vis: f.vis,
			isAsync: f.isAsync,
			generics: f.generics,
			args: f.args,
			ret: f.ret,
			body: body
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
		var rewrittenTail = if (disableLastUseElision || tail == null) {
			tail;
		} else {
			rewriteTailCloneArgs(tail, rewrittenStmts);
		}
		return {
			stmts: rewrittenStmts,
			tail: rewrittenTail
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
			case ERaw(_) | ESelf | ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
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
			case ECall(EField(target, member), []) if (RustPathAnalysis.matchesPlainMember(member, "clone")):
				if (isAlwaysCloneSafeExpr(target)) {
					recordApplied("clone_elision.applied.literal_clone");
					target;
				} else {
					switch (target) {
						case ECall(EField(inner, innerMember), []) if (RustPathAnalysis.matchesPlainMember(innerMember, "clone")):
							recordApplied("clone_elision.applied.nested_clone");
							ECall(EField(inner, innerMember), []);
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
			case ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
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
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : rewriteCallCloneArgs(expr, index, stmts, tail));
			case RSemi(expr):
				RSemi(rewriteCallCloneArgs(expr, index, stmts, tail));
			case RExpr(expr, needsSemicolon):
				RExpr(rewriteCallCloneArgs(expr, index, stmts, tail), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : rewriteCallCloneArgs(expr, index, stmts, tail));
			case RWhile(_, _) | RLoop(_) | RFor(_, _, _) | RBreak | RContinue:
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
			if (countPathUsesInExpr(ownerExpr, name) != 1)
				return "multiple_uses_in_expr";
			if (hasPathUseAfter(stmts, tail, index, name))
				return "path_used_after_stmt";
			return null;
		}
		return rewriteLastUseCloneSites(expr, localName -> localMoveSkipReason(localName, expr));
	}

	function rewriteTailCloneArgs(expr:RustExpr, stmts:Array<RustStmt>):RustExpr {
		var movableLocals = collectMovableLocalsBeforeIndex(stmts, stmts.length);
		function localMoveSkipReason(name:String, ownerExpr:RustExpr):Null<String> {
			if (!movableLocals.exists(name))
				return "missing_local_binding";
			if (!movableLocals.get(name))
				return "non_movable_or_reference_typed";
			if (countPathUsesInExpr(ownerExpr, name) != 1)
				return "multiple_uses_in_expr";
			return null;
		}
		return rewriteLastUseCloneSites(expr, localName -> localMoveSkipReason(localName, expr));
	}

	function collectMovableLocalsBeforeIndex(stmts:Array<RustStmt>, index:Int):Map<String, Bool> {
		var out:Map<String, Bool> = [];
		if (currentMovableBindings != null) {
			for (name in currentMovableBindings.keys()) {
				out.set(name, currentMovableBindings.get(name));
			}
		}
		for (i in 0...index) {
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
			case RBorrow(_, _, _):
				true;
			case RUnit | RBool | RI32 | RF64 | RString | RNamed(_) | RTuple(_) | RSlice(_) | RArray(_, _) | RTraitObject(_):
				false;
		};
	}

	/**
		Rewrites last-use `.clone()` sites that are safe to convert into moves.

		Why
		- Generic helpers over native Rust `Option<T>` / `Result<T, E>` should not require
		  artificial `Clone` bounds just because codegen matched on an owned local via
		  `match value.clone() { ... }`.
		- The same last-use reasoning also applies to boxed dynamic calls such as
		  `hxrt::dynamic::from(local.clone())`.
		- Generic nested call-arg elision is intentionally not attempted here because the
		  enclosing Rust expression tree can still use the same local later in ways that are
		  easy to misclassify after lowering.

		What
		- Removes `.clone()` from supported move sites when the local is:
		  - a simple local path,
		  - movable (not a reference-typed binding),
		  - used exactly once in the owning expression,
		  - not used after the containing statement.

		How
		- The pass operates on Rust AST after lowering, so it can reason about the actual emitted
		  move site (`match` scrutinee / `hxrt::dynamic::from(...)`) without duplicating typed-AST
		  lowering logic.
	**/
	function rewriteLastUseCloneSites(expr:RustExpr, localMoveSkipReason:String->Null<String>):RustExpr {
		return switch (expr) {
			case ECall(EPath(dynamicPath), [ECall(EField(EPath(localPath), member), [])])
				if (RustPathAnalysis.matchesPlainRelative(dynamicPath, ["hxrt", "dynamic", "from"])
					&& RustPathAnalysis.matchesPlainMember(member, "clone")
					&& RustPathAnalysis.localIdentifierName(localPath) != null):
				var localName = RustPathAnalysis.localIdentifierName(localPath);
				var skipReason = localMoveSkipReason(localName);
				if (skipReason == null) {
					recordApplied("clone_elision.applied.last_use_dynamic_from");
					ECall(EPath(dynamicPath), [EPath(localPath)]);
				} else {
					recordSkipped("clone_elision.skipped.last_use_dynamic_from." + skipReason);
					expr;
				}
			case EMatch(ECall(EField(EPath(localPath), member), []), arms)
				if (RustPathAnalysis.matchesPlainMember(member, "clone") && RustPathAnalysis.localIdentifierName(localPath) != null):
				var localName = RustPathAnalysis.localIdentifierName(localPath);
				var skipReason = localMoveSkipReason(localName);
				var rewrittenArms = [
					for (arm in arms)
						{
							pat: arm.pat,
							expr: rewriteLastUseCloneSites(arm.expr, matchArmMoveSkipReason(arm, localMoveSkipReason))
						}
				];
				if (skipReason == null) {
					recordApplied("clone_elision.applied.last_use_match_scrutinee");
					EMatch(EPath(localPath), rewrittenArms);
				} else {
					recordSkipped("clone_elision.skipped.last_use_match_scrutinee." + skipReason);
					EMatch(ECall(EField(EPath(localPath), member), []), rewrittenArms);
				}
			case ECall(func, args):
				var rewrittenFunc = rewriteLastUseCloneSites(func, localMoveSkipReason);
				var rewrittenArgs = [for (arg in args) rewriteLastUseCloneSites(arg, localMoveSkipReason)];
				ECall(rewrittenFunc, rewrittenArgs);
			case EMacroCall(name, args):
				EMacroCall(name, [for (arg in args) rewriteLastUseCloneSites(arg, localMoveSkipReason)]);
			case EBinary(op, left, right):
				EBinary(op, rewriteLastUseCloneSites(left, localMoveSkipReason), rewriteLastUseCloneSites(right, localMoveSkipReason));
			case EUnary(op, inner):
				EUnary(op, rewriteLastUseCloneSites(inner, localMoveSkipReason));
			case ERange(start, end):
				ERange(rewriteLastUseCloneSites(start, localMoveSkipReason), rewriteLastUseCloneSites(end, localMoveSkipReason));
			case ECast(inner, ty):
				ECast(rewriteLastUseCloneSites(inner, localMoveSkipReason), ty);
			case EIndex(recv, index):
				EIndex(rewriteLastUseCloneSites(recv, localMoveSkipReason), rewriteLastUseCloneSites(index, localMoveSkipReason));
			case EStructLit(path, fields):
				EStructLit(path, [
					for (field in fields)
						{
							name: field.name,
							expr: rewriteLastUseCloneSites(field.expr, localMoveSkipReason)
						}
				]);
			case EBlock(block):
				EBlock(rewriteLastUseCloneBlock(block, localMoveSkipReason));
			case EIf(cond, thenExpr, elseExpr):
				EIf(rewriteLastUseCloneSites(cond, localMoveSkipReason), rewriteLastUseCloneSites(thenExpr, localMoveSkipReason),
					elseExpr == null ? null : rewriteLastUseCloneSites(elseExpr, localMoveSkipReason));
			case EMatch(scrutinee, arms):
				EMatch(rewriteLastUseCloneSites(scrutinee, localMoveSkipReason), [
					for (arm in arms)
						{
							pat: arm.pat,
							expr: rewriteLastUseCloneSites(arm.expr, matchArmMoveSkipReason(arm, localMoveSkipReason))
						}
				]);
			case EAssign(lhs, rhs):
				EAssign(rewriteLastUseCloneSites(lhs, localMoveSkipReason), rewriteLastUseCloneSites(rhs, localMoveSkipReason));
			case EField(recv, field):
				EField(rewriteLastUseCloneSites(recv, localMoveSkipReason), field);
			case EClosure(_, _, _) | EPinAsyncMove(_) | EAwait(_) | ERaw(_) | ESelf | ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				expr;
		};
	}

	/**
		Rewrites a nested block without carrying outer-binding evidence through a new `let`.

		Why
		- Rust evaluates a `let` initializer in the old scope and introduces the new binding only for
		  later statements and the block tail.
		- Reusing the spelling of an outer movable local for a reference-typed inner local can make clone
		  removal change the resulting type, so name-only evidence must stop at the lexical boundary.

		What
		- Rewrites each initializer with the current predicate, then rejects outer evidence for the newly
		  bound spelling while rewriting subsequent siblings and the tail.

		How
		- Advances an immutable predicate chain after each non-wildcard `RLet`; the original predicate is
		  still used for the initializer because the chain advances only after that statement is visited.
	**/
	function rewriteLastUseCloneBlock(block:RustBlock, outerSkipReason:String->Null<String>):RustBlock {
		var currentSkipReason = outerSkipReason;
		var rewrittenStmts:Array<RustStmt> = [];
		for (stmt in block.stmts) {
			rewrittenStmts.push(rewriteLastUseCloneStmt(stmt, currentSkipReason));
			switch (stmt) {
				case RLet(name, _, _, _) if (name != "_"):
					currentSkipReason = bindingMoveSkipReason(name, currentSkipReason);
				case _:
			}
		}
		return {
			stmts: rewrittenStmts,
			tail: block.tail == null ? null : rewriteLastUseCloneSites(block.tail, currentSkipReason)
		};
	}

	/**
		Protects match-arm bindings from outer-local move evidence.

		Why
		- A path inside an arm can spell the same name as a movable local outside the match while
		  resolving to the arm pattern's new binding.

		What
		- Returns a deterministic `shadowed_binding` rejection for names introduced by the arm pattern.

		How
		- Uses structural pattern binding analysis before delegating every unshadowed name to the
		  enclosing move-safety predicate.
	**/
	function matchArmMoveSkipReason(arm:RustMatchArm, outerSkipReason:String->Null<String>):String->Null<String> {
		return localName -> RustPathAnalysis.patternBindsName(arm.pat, localName) ? "shadowed_binding" : outerSkipReason(localName);
	}

	/**
		Builds the move-safety predicate after one lexical binding enters scope.

		Why
		- The outer predicate owns type and last-use facts for a different binding even when its name is
		  reused, so delegating the reused spelling would apply evidence to the wrong Rust value.

		What
		- Rejects the newly bound spelling deterministically and delegates every other local unchanged.

		How
		- `rewriteLastUseCloneBlock` installs the returned predicate only after rewriting the binding's
		  initializer, matching Rust's lexical evaluation order.
	**/
	function bindingMoveSkipReason(bindingName:String, outerSkipReason:String->Null<String>):String->Null<String> {
		return localName -> localName == bindingName ? "shadowed_binding" : outerSkipReason(localName);
	}

	function rewriteLastUseCloneStmt(stmt:RustStmt, localMoveSkipReason:String->Null<String>):RustStmt {
		return switch (stmt) {
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : rewriteLastUseCloneSites(expr, localMoveSkipReason));
			case RSemi(expr):
				RSemi(rewriteLastUseCloneSites(expr, localMoveSkipReason));
			case RExpr(expr, needsSemicolon):
				RExpr(rewriteLastUseCloneSites(expr, localMoveSkipReason), needsSemicolon);
			case RReturn(expr):
				RReturn(expr == null ? null : rewriteLastUseCloneSites(expr, localMoveSkipReason));
			// Loop statements remain opaque here because their bodies may execute repeatedly. Their lexical
			// binders are nevertheless modeled by use counting, so they cannot create false outer last-use
			// evidence for a later rewrite site in the same owning expression.
			case RWhile(_, _) | RLoop(_) | RFor(_, _, _):
				stmt;
			case RBreak | RContinue:
				stmt;
		};
	}

	/**
		Reports whether a clone candidate has a later use in the same outer binding scope.

		Why
		- Last-use elision is valid across a later same-named shadow, but not across a use in that shadow's
		  initializer because the initializer still executes in the outer scope.
		- A candidate can itself be inside the shadowing `let` initializer, after which every sibling and
		  the tail belongs to the new binding.

		What
		- Handles both the current-statement binder and later binders while preserving initializer-first
		  Rust evaluation order.

		How
		- Expression-local multiplicity is checked by the caller. This helper checks only later statements
		  and the tail, stopping after a same-named initializer reports no outer use.
	**/
	function hasPathUseAfter(stmts:Array<RustStmt>, tail:Null<RustExpr>, fromIndex:Int, pathName:String):Bool {
		// A candidate inside a same-named `let` initializer is the final outer-scope use: the binding
		// enters scope immediately after that statement, before any following sibling or the tail.
		if (fromIndex >= 0 && fromIndex < stmts.length) {
			switch (stmts[fromIndex]) {
				case RLet(name, _, _, _) if (name == pathName):
					return false;
				case _:
			}
		}
		var i = fromIndex + 1;
		while (i < stmts.length) {
			var stmt = stmts[i];
			if (countPathUsesInStmt(stmt, pathName) > 0)
				return true;
			// The initializer above was evaluated in the outer scope. Only after it reports no use may
			// the new binding terminate the scan for later siblings and the block tail.
			switch (stmt) {
				case RLet(name, _, _, _) if (name == pathName):
					return false;
				case _:
			}
			i += 1;
		}
		if (tail != null && countPathUsesInExpr(tail, pathName) > 0)
			return true;
		return false;
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
				countPathUsesInExpr(cond, pathName) + countPathUsesInBlock(body, pathName);
			case RLoop(body):
				countPathUsesInBlock(body, pathName);
			case RFor(name, iter, body):
				var total = countPathUsesInExpr(iter, pathName);
				if (name != pathName)
					total += countPathUsesInBlock(body, pathName);
				total;
			case RBreak | RContinue:
				0;
		};
	}

	/**
		Counts uses of one outer binding across a lexical Rust block.

		Why
		- Counting every same-spelled path in a nested block mistakes inner `let` and `for` bindings for
		  later uses of the outer local, producing both missed optimizations and unsafe move evidence.

		What
		- Counts a shadowing `let` initializer in the outer scope, then stops at that binding for all later
		  siblings and the tail. Statement-specific recursion handles a `for` iterable before its binder.

		How
		- Walks statements in source order and flips a local shadow flag only after visiting the matching
		  `RLet`, mirroring `rewriteLastUseCloneBlock` exactly.
	**/
	function countPathUsesInBlock(block:RustBlock, pathName:String):Int {
		var total = 0;
		var shadowed = false;
		for (stmt in block.stmts) {
			if (shadowed)
				break;
			total += countPathUsesInStmt(stmt, pathName);
			switch (stmt) {
				case RLet(name, _, _, _) if (name == pathName):
					shadowed = true;
				case _:
			}
		}
		if (!shadowed && block.tail != null)
			total += countPathUsesInExpr(block.tail, pathName);
		return total;
	}

	function countPathUsesInExpr(expr:RustExpr, pathName:String):Int {
		return switch (expr) {
			case EPath(p):
				RustPathAnalysis.localIdentifierName(p) == pathName ? 1 : 0;
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
			case EClosure(args, body, _):
				if (RustPathAnalysis.closureParametersBindName(args, pathName)) {
					0;
				} else {
					countPathUsesInBlock(body, pathName);
				}
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
				countPathUsesInBlock(block, pathName);
			case EIf(cond, thenExpr, elseExpr):
				countPathUsesInExpr(cond,
					pathName) + countPathUsesInExpr(thenExpr, pathName) + (elseExpr == null ? 0 : countPathUsesInExpr(elseExpr, pathName));
			case EMatch(scrutinee, arms):
				var total = countPathUsesInExpr(scrutinee, pathName);
				for (arm in arms) {
					if (!RustPathAnalysis.patternBindsName(arm.pat, pathName))
						total += countPathUsesInExpr(arm.expr, pathName);
				}
				total;
			case EAssign(lhs, rhs):
				countPathUsesInExpr(lhs, pathName) + countPathUsesInExpr(rhs, pathName);
			case EField(recv, _):
				countPathUsesInExpr(recv, pathName);
			case EPinAsyncMove(body):
				countPathUsesInBlock(body, pathName);
			case ERaw(_) | ESelf | ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
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
			case ECall(EPath(dynamicPath), [ECall(EField(EPath(localPath), member), [])])
				if (RustPathAnalysis.matchesPlainRelative(dynamicPath, ["hxrt", "dynamic", "from"])
					&& RustPathAnalysis.matchesPlainMember(member, "clone")
					&& RustPathAnalysis.localIdentifierName(localPath) != null):
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
			case ERaw(_) | ESelf | ELitUnit | ELitInt(_) | ELitUInt32(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
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
