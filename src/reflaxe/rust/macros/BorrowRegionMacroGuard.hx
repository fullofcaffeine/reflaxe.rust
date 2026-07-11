package reflaxe.rust.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import reflaxe.rust.RustDiagnostic;
import reflaxe.rust.RustDiagnostic.RustDiagnosticId;

/**
	BorrowRegionMacroGuard

	Why
	- Haxe has no native lifetime parameters, so `rust.Ref<T>`, `rust.MutRef<T>`,
	  `rust.Slice<T>`, and related borrow-only surfaces need a scoped discipline before
	  generated Rust reaches the Rust borrow checker.
	- The scoped helper macros (`Borrow.withRef`, `SliceTools.with`, etc.) are the first
	  reliable place to reject obvious escapes while still pointing at user Haxe code.

	What
	- Performs a conservative syntax-level check over a scoped borrow callback.
	- Rejects direct borrow-token escapes:
	  - callback tail expression is the token,
	  - `return token`,
	  - assignment of the token to another slot,
	  - returned array/object literals that directly contain the token,
	  - returned closures that capture the token.

	How
	- The helper receives the callback parameter name before the owning macro expands/inlines
	  the callback body.
	- It treats only syntactic escape positions as hard errors, so ordinary calls like
	  `Borrow.withRef(v, r -> use(r))` remain accepted.
	- This is not a full borrow checker. The compiler's typed-AST borrow-region analyzer covers
	  the first alias/storage/overlap slice, while deeper lifetime reasoning remains documented
	  follow-up work in `docs/lifetime-encoding.md`.
**/
class BorrowRegionMacroGuard {
	public static function rejectEscapingBorrow(helperLabel:String, tokenKind:String, tokenName:String, body:Expr):Void {
		if (body == null || tokenName == null || tokenName.length == 0)
			return;

		scan(body, true, helperLabel, tokenKind, tokenName);
	}

	static function scan(expr:Expr, escapePosition:Bool, helperLabel:String, tokenKind:String, tokenName:String):Void {
		if (expr == null)
			return;

		var current = unwrap(expr);
		if (escapePosition && isTokenRef(current, tokenName)) {
			error(helperLabel, tokenKind, tokenName, "Return an owned value derived from the borrow instead of the borrow token itself.", current.pos);
			return;
		}

		switch (current.expr) {
			case EBlock(exprs):
				for (i in 0...exprs.length)
					scan(exprs[i], escapePosition && i == exprs.length - 1, helperLabel, tokenKind, tokenName);

			case EReturn(value):
				if (value != null)
					scan(value, true, helperLabel, tokenKind, tokenName);

			case EBinop(OpAssign, left, right):
				if (isTokenRef(right, tokenName)) {
					error(helperLabel, tokenKind, tokenName, "Do not assign the borrow token out of its scoped callback.", right.pos);
					return;
				}
				scan(left, false, helperLabel, tokenKind, tokenName);
				scan(right, false, helperLabel, tokenKind, tokenName);

			case EBinop(OpAssignOp(_), left, right):
				scan(left, false, helperLabel, tokenKind, tokenName);
				scan(right, false, helperLabel, tokenKind, tokenName);

			case EVars(vars):
				for (v in vars) {
					if (v.expr != null)
						scan(v.expr, false, helperLabel, tokenKind, tokenName);
				}

			case EIf(condition, ifExpr, elseExpr):
				scan(condition, false, helperLabel, tokenKind, tokenName);
				scan(ifExpr, escapePosition, helperLabel, tokenKind, tokenName);
				if (elseExpr != null)
					scan(elseExpr, escapePosition, helperLabel, tokenKind, tokenName);

			case ESwitch(subject, cases, defaultExpr):
				scan(subject, false, helperLabel, tokenKind, tokenName);
				for (caseExpr in cases) {
					for (value in caseExpr.values)
						scan(value, false, helperLabel, tokenKind, tokenName);
					if (caseExpr.guard != null)
						scan(caseExpr.guard, false, helperLabel, tokenKind, tokenName);
					if (caseExpr.expr != null)
						scan(caseExpr.expr, escapePosition, helperLabel, tokenKind, tokenName);
				}
				if (defaultExpr != null)
					scan(defaultExpr, escapePosition, helperLabel, tokenKind, tokenName);

			case ETry(tryExpr, catches):
				scan(tryExpr, escapePosition, helperLabel, tokenKind, tokenName);
				for (catchExpr in catches)
					scan(catchExpr.expr, escapePosition, helperLabel, tokenKind, tokenName);

			case EArrayDecl(values):
				if (escapePosition) {
					for (value in values) {
						if (literalDirectlyContainsToken(value, tokenName)) {
							error(helperLabel, tokenKind, tokenName, "Do not return an array literal that contains the borrow token.", value.pos);
							return;
						}
					}
				}
				for (value in values)
					scan(value, false, helperLabel, tokenKind, tokenName);

			case EObjectDecl(fields):
				if (escapePosition) {
					for (field in fields) {
						if (literalDirectlyContainsToken(field.expr, tokenName)) {
							error(helperLabel, tokenKind, tokenName, "Do not return an object literal that contains the borrow token.", field.expr.pos);
							return;
						}
					}
				}
				for (field in fields)
					scan(field.expr, false, helperLabel, tokenKind, tokenName);

			case EFunction(_, fn):
				if (escapePosition && fn != null && referencesToken(fn.expr, tokenName, true)) {
					error(helperLabel, tokenKind, tokenName, "Do not return a closure that captures the borrow token.", current.pos);
				}
			// Nested callbacks can be scoped borrow helpers themselves. Their boundary is checked by
			// the owning helper or by typed analyses such as SendSyncAnalyzer.

			case _:
				ExprTools.iter(current, child -> scan(child, false, helperLabel, tokenKind, tokenName));
		}
	}

	static function referencesToken(expr:Expr, tokenName:String, descendIntoFunctions:Bool):Bool {
		if (expr == null)
			return false;

		var found = false;
		function visit(e:Expr):Void {
			if (found || e == null)
				return;
			var current = unwrap(e);
			if (isTokenRef(current, tokenName)) {
				found = true;
				return;
			}
			switch (current.expr) {
				case EFunction(_, _) if (!descendIntoFunctions):
					return;
				case _:
					ExprTools.iter(current, visit);
			}
		}
		visit(expr);
		return found;
	}

	static function literalDirectlyContainsToken(expr:Expr, tokenName:String):Bool {
		if (expr == null)
			return false;

		var current = unwrap(expr);
		if (isTokenRef(current, tokenName))
			return true;

		return switch (current.expr) {
			case EArrayDecl(values):
				{
					for (value in values) {
						if (literalDirectlyContainsToken(value, tokenName))
							return true;
					}
					false;
				}
			case EObjectDecl(fields):
				{
					for (field in fields) {
						if (literalDirectlyContainsToken(field.expr, tokenName))
							return true;
					}
					false;
				}
			case _:
				false;
		}
	}

	static function isTokenRef(expr:Expr, tokenName:String):Bool {
		var current = unwrap(expr);
		return switch (current.expr) {
			case EConst(CIdent(name)):
				name == tokenName;
			case _:
				false;
		}
	}

	static function unwrap(expr:Expr):Expr {
		var current = expr;
		while (current != null) {
			switch (current.expr) {
				case EParenthesis(inner) | ECast(inner, _) | ECheckType(inner, _) | EMeta(_, inner):
					current = inner;
					continue;
				case _:
			}
			break;
		}
		return current;
	}

	static function error(helperLabel:String, tokenKind:String, tokenName:String, detail:String, pos:haxe.macro.Expr.Position):Void {
		RustDiagnostic.error(RustDiagnosticId.BorrowRegion, "Rust borrow region violation: " + helperLabel + " creates " + tokenKind + " `" + tokenName
			+ "` that must not escape its callback region. " + detail,
			pos);
	}
}
#end
