package reflaxe.rust.passes;

import reflaxe.rust.ast.RustAST;
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustFunction;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustMatchArm;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustStructLitField;

/**
	Shared traversal helpers for Rust AST passes.

	Why
	- Profile passes need consistent recursive traversal over the same tree shapes.
	- Re-implementing recursion in each pass is error-prone and makes behavior drift likely.

	What
	- Small mapper utilities that walk files/functions/blocks/expressions and let a pass inject
	  targeted rewrites.

	How
	- Passes provide a closure for statement and/or expression transformation.
	- Helpers preserve original structure and only replace visited nodes.
**/
class RustPassTools {
	public static function mapFile(file:RustFile, mapStmt:RustStmt->RustStmt, mapExpr:RustExpr->RustExpr):RustFile {
		return {
			items: [for (item in file.items) mapItem(item, mapStmt, mapExpr)]
		};
	}

	static function mapItem(item:RustItem, mapStmt:RustStmt->RustStmt, mapExpr:RustExpr->RustExpr):RustItem {
		return switch (item) {
			case RFn(f):
				RFn(mapFunction(f, mapStmt, mapExpr));
			case RImpl(i):
				RImpl({
					generics: i.generics,
					forType: i.forType,
					functions: [for (f in i.functions) mapFunction(f, mapStmt, mapExpr)]
				});
			case RStruct(_) | REnum(_) | RRaw(_):
				item;
		}
	}

	public static function mapFunction(f:RustFunction, mapStmt:RustStmt->RustStmt, mapExpr:RustExpr->RustExpr):RustFunction {
		return {
			name: f.name,
			isPub: f.isPub,
			vis: f.vis,
			isAsync: f.isAsync,
			generics: f.generics,
			args: f.args,
			ret: f.ret,
			body: mapBlock(f.body, mapStmt, mapExpr)
		};
	}

	public static function mapBlock(b:RustBlock, mapStmt:RustStmt->RustStmt, mapExpr:RustExpr->RustExpr):RustBlock {
		return {
			stmts: [for (s in b.stmts) mapStmtDeep(s, mapStmt, mapExpr)],
			tail: b.tail == null ? null : mapExprDeep(b.tail, mapExpr)
		};
	}

	public static function mapStmtDeep(s:RustStmt, mapStmt:RustStmt->RustStmt, mapExpr:RustExpr->RustExpr):RustStmt {
		var deep:RustStmt = switch (s) {
			case RLet(name, mutable, ty, expr):
				RLet(name, mutable, ty, expr == null ? null : mapExprDeep(expr, mapExpr));
			case RSemi(e):
				RSemi(mapExprDeep(e, mapExpr));
			case RExpr(e, needsSemicolon):
				RExpr(mapExprDeep(e, mapExpr), needsSemicolon);
			case RReturn(e):
				RReturn(e == null ? null : mapExprDeep(e, mapExpr));
			case RWhile(cond, body):
				RWhile(mapExprDeep(cond, mapExpr), mapBlock(body, mapStmt, mapExpr));
			case RLoop(body):
				RLoop(mapBlock(body, mapStmt, mapExpr));
			case RFor(name, iter, body):
				RFor(name, mapExprDeep(iter, mapExpr), mapBlock(body, mapStmt, mapExpr));
			case RBreak:
				RBreak;
			case RContinue:
				RContinue;
		};
		return mapStmt(deep);
	}

	public static function mapExprDeep(e:RustExpr, mapExpr:RustExpr->RustExpr):RustExpr {
		var deep:RustExpr = switch (e) {
			case ERaw(_) | ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_) | EPath(_):
				e;
			case ECall(func, args):
				ECall(mapExprDeep(func, mapExpr), [for (arg in args) mapExprDeep(arg, mapExpr)]);
			case EMacroCall(name, args):
				EMacroCall(name, [for (arg in args) mapExprDeep(arg, mapExpr)]);
			case EClosure(args, body, isMove):
				EClosure(args, mapBlock(body, s -> s, mapExpr), isMove);
			case EBinary(op, left, right):
				EBinary(op, mapExprDeep(left, mapExpr), mapExprDeep(right, mapExpr));
			case EUnary(op, expr):
				EUnary(op, mapExprDeep(expr, mapExpr));
			case ERange(start, end):
				ERange(mapExprDeep(start, mapExpr), mapExprDeep(end, mapExpr));
			case ECast(expr, ty):
				ECast(mapExprDeep(expr, mapExpr), ty);
			case EIndex(recv, index):
				EIndex(mapExprDeep(recv, mapExpr), mapExprDeep(index, mapExpr));
			case EStructLit(path, fields):
				EStructLit(path, [for (field in fields) mapStructField(field, mapExpr)]);
			case EBlock(block):
				EBlock(mapBlock(block, s -> s, mapExpr));
			case EIf(cond, thenExpr, elseExpr):
				EIf(mapExprDeep(cond, mapExpr), mapExprDeep(thenExpr, mapExpr), elseExpr == null ? null : mapExprDeep(elseExpr, mapExpr));
			case EMatch(scrutinee, arms):
				EMatch(mapExprDeep(scrutinee, mapExpr), [for (arm in arms) mapMatchArm(arm, mapExpr)]);
			case EAssign(lhs, rhs):
				EAssign(mapExprDeep(lhs, mapExpr), mapExprDeep(rhs, mapExpr));
			case EField(recv, field):
				EField(mapExprDeep(recv, mapExpr), field);
			case EAwait(expr):
				EAwait(mapExprDeep(expr, mapExpr));
		};
		return mapExpr(deep);
	}

	static function mapStructField(field:RustStructLitField, mapExpr:RustExpr->RustExpr):RustStructLitField {
		return {
			name: field.name,
			expr: mapExprDeep(field.expr, mapExpr)
		};
	}

	static function mapMatchArm(arm:RustMatchArm, mapExpr:RustExpr->RustExpr):RustMatchArm {
		return {
			pat: arm.pat,
			expr: mapExprDeep(arm.expr, mapExpr)
		};
	}
}
