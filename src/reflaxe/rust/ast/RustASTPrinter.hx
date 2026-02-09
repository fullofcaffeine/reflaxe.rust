package reflaxe.rust.ast;

import reflaxe.rust.ast.RustAST;

class RustASTPrinter {
	// Rust-ish precedence levels used to avoid excessive parentheses.
	// Higher number = tighter binding.
	static inline var PREC_LOWEST = 0;
	static inline var PREC_ASSIGN = 10;
	static inline var PREC_OR = 20;
	static inline var PREC_AND = 30;
	static inline var PREC_EQ = 35;
	static inline var PREC_CMP = 40;
	static inline var PREC_ADD = 60;
	static inline var PREC_MUL = 70;
	static inline var PREC_CAST = 80;
	static inline var PREC_UNARY = 85;
	static inline var PREC_POSTFIX = 90; // call/field/index
	static inline var PREC_PRIMARY = 100;

	public static function printFile(file: RustAST.RustFile): String {
		var parts: Array<String> = [];
		for (item in file.items) {
			parts.push(printItem(item));
		}
		var out = parts.filter(p -> StringTools.trim(p).length > 0).join("\n\n");
		return out.length > 0 ? (out + "\n") : "";
	}

	/**
	 * Minimal expression printer for code injection expansion.
	 *
	 * This intentionally prints a single expression without any surrounding context.
	 */
	public static function printExprForInjection(e: RustAST.RustExpr): String {
		return printExprPrec(e, 0, PREC_LOWEST);
	}

	static function printItem(item: RustAST.RustItem): String {
		return switch (item) {
			case RFn(f): printFunction(f, 0);
			case RStruct(s): printStruct(s);
			case REnum(e): printEnum(e);
			case RImpl(i): printImpl(i);
			case RRaw(s): s;
		}
	}

	static function visibilityToken(vis: Null<RustAST.RustVisibility>, isPub: Bool): Null<String> {
		var v = vis != null ? vis : (isPub ? RustAST.RustVisibility.VPub : RustAST.RustVisibility.VPrivate);
		return switch (v) {
			case VPrivate: null;
			case VPub: "pub";
			case VPubCrate: "pub(crate)";
		}
	}

	static function visibilityPrefix(vis: Null<RustAST.RustVisibility>, isPub: Bool): String {
		var t = visibilityToken(vis, isPub);
		return t == null ? "" : (t + " ");
	}

	static function printStruct(s: RustAST.RustStruct): String {
		var head = visibilityPrefix(s.vis, s.isPub) + "struct " + s.name;
		if (s.generics != null && s.generics.length > 0) {
			head += "<" + s.generics.join(", ") + ">";
		}
		if (s.fields.length == 0) {
			return head + " { }";
		}

		var lines: Array<String> = [];
		for (f in s.fields) {
			var prefix = visibilityPrefix(f.vis, f.isPub);
			lines.push("    " + prefix + f.name + ": " + printType(f.ty) + ",");
		}
		return head + " {\n" + lines.join("\n") + "\n}";
	}

	static function printEnum(e: RustAST.RustEnum): String {
		var parts: Array<String> = [];
		if (e.derives.length > 0) {
			parts.push("#[derive(" + e.derives.join(", ") + ")]");
		}

		var head = visibilityPrefix(e.vis, e.isPub) + "enum " + e.name;
		if (e.variants.length == 0) {
			parts.push(head + " { }");
			return parts.join("\n");
		}

		var lines: Array<String> = [];
		for (v in e.variants) {
			if (v.args.length == 0) {
				lines.push("    " + v.name + ",");
			} else {
				var args = v.args.map(a -> printType(a)).join(", ");
				lines.push("    " + v.name + "(" + args + "),");
			}
		}
		parts.push(head + " {\n" + lines.join("\n") + "\n}");
		return parts.join("\n");
	}

	static function printImpl(i: RustAST.RustImpl): String {
		var head = "impl";
		if (i.generics != null && i.generics.length > 0) {
			head += "<" + i.generics.join(", ") + ">";
		}
		head += " " + i.forType;
		if (i.functions.length == 0) {
			return head + " { }";
		}

		var parts: Array<String> = [];
		for (f in i.functions) {
			parts.push(printFunction(f, 1));
		}
		var body = parts.filter(p -> StringTools.trim(p).length > 0).join("\n\n");
		return head + " {\n" + body + "\n}";
	}

	static function printFunction(f: RustAST.RustFunction, indent: Int): String {
		var sigParts: Array<String> = [];
		var tok = visibilityToken(f.vis, f.isPub);
		if (tok != null) sigParts.push(tok);
		sigParts.push("fn");
		var name = f.name;
		if (f.generics != null && f.generics.length > 0) {
			name += "<" + f.generics.join(", ") + ">";
		}
		sigParts.push(name);

		var args = f.args.map(a -> '${a.name}: ${printType(a.ty)}').join(", ");
		var sig = sigParts.join(" ") + '($args)';
		if (f.ret != RUnit) {
			sig += ' -> ${printType(f.ret)}';
		}

		var ind = indentString(indent);
		return ind + sig + " " + printBlock(f.body, indent);
	}

	static function printType(t: RustAST.RustType): String {
		return switch (t) {
			case RUnit: "()";
			case RBool: "bool";
			case RI32: "i32";
			case RF64: "f64";
			case RString: "String";
			case RRef(inner, mutable): "&" + (mutable ? "mut " : "") + printType(inner);
			case RPath(path): path;
		}
	}

	static function printBlock(b: RustAST.RustBlock, indent: Int): String {
		var ind = indentString(indent);
		var innerInd = indentString(indent + 1);

		var lines: Array<String> = [];
		for (s in b.stmts) {
			lines.push(innerInd + printStmt(s, indent + 1));
		}
		if (b.tail != null) {
			lines.push(innerInd + printExpr(b.tail, indent + 1));
		}

		if (lines.length == 0) {
			return "{ }";
		}

		return "{\n" + lines.join("\n") + "\n" + ind + "}";
	}

	static function printStmt(s: RustAST.RustStmt, indent: Int): String {
		return switch (s) {
			case RLet(name, mutable, ty, expr): {
				var out = "let";
				if (mutable) out += " mut";
				out += " " + name;
				if (ty != null) out += ": " + printType(ty);
				if (expr != null) out += " = " + printExpr(expr, indent);
				out + ";";
			}
			case RSemi(e): {
				// Avoid `;;` when an injected raw expression already includes a trailing semicolon.
				var printed = printExpr(e, indent);
				var trimmed = StringTools.rtrim(printed);
				if (StringTools.endsWith(trimmed, ";")) trimmed else trimmed + ";";
			}
			case RExpr(e, needsSemicolon):
				printExpr(e, indent) + (needsSemicolon ? ";" : "");
			case RReturn(e):
				e == null ? "return;" : ("return " + printExpr(e, indent) + ";");
			case RWhile(cond, body):
				"while " + printExpr(cond, indent) + " " + printBlock(body, indent);
			case RLoop(body):
				"loop " + printBlock(body, indent);
			case RFor(name, iter, body):
				"for " + name + " in " + printExpr(iter, indent) + " " + printBlock(body, indent);
		}
	}

	static function printExpr(e: RustAST.RustExpr, indent: Int): String {
		return printExprPrec(e, indent, PREC_LOWEST);
	}

	static function printExprPrec(e: RustAST.RustExpr, indent: Int, ctxPrec: Int): String {
		return switch (e) {
			case ERaw(s): s;
			case ELitInt(v): Std.string(v);
			case ELitFloat(v): {
				// Rust requires a decimal point for float literals in some contexts (e.g. `1.`).
				var s = Std.string(v);
				if (s.indexOf(".") == -1 && s.indexOf("e") == -1 && s.indexOf("E") == -1) s += ".0";
				s;
			}
			case ELitBool(v): v ? "true" : "false";
			case ELitString(v): '"' + escapeStringLiteral(v) + '"';
			case EPath(path): path;
			case EField(recv, field): {
				var recvStr = printExprPrec(recv, indent, PREC_POSTFIX);
				var out = recvStr + "." + field;
				wrapIfNeeded(out, PREC_POSTFIX, ctxPrec);
			}
			case ECall(func, args): {
				var a = args.map(x -> printExprPrec(x, indent, PREC_LOWEST)).join(", ");
				var fnStr = printExprPrec(func, indent, PREC_POSTFIX);
				var out = fnStr + "(" + a + ")";
				wrapIfNeeded(out, PREC_POSTFIX, ctxPrec);
			}
			case EClosure(args, body, isMove): {
				var a = args.join(", ");
				var out = (isMove ? "move " : "") + "|" + a + "| " + printBlock(body, indent);
				wrapIfNeeded(out, PREC_LOWEST, ctxPrec);
			}
			case EMacroCall(name, args): {
				var a = args.map(x -> printExprPrec(x, indent, PREC_LOWEST)).join(", ");
				if (name == "vec") {
					wrapIfNeeded(name + "![" + a + "]", PREC_PRIMARY, ctxPrec);
				} else {
					wrapIfNeeded(name + "!(" + a + ")", PREC_PRIMARY, ctxPrec);
				}
			}
			case EBinary(op, left, right): {
				var prec = binaryPrec(op);
				var leftStr = printExprPrec(left, indent, prec);
				// Preserve grouping: for left-associative ops, parenthesize RHS when it has the same precedence.
				var rightStr = printExprPrec(right, indent, prec + 1);
				var out = leftStr + " " + op + " " + rightStr;
				wrapIfNeeded(out, prec, ctxPrec);
			}
			case EUnary(op, expr): {
				var inner = printExprPrec(expr, indent, PREC_UNARY);
				var out = op + inner;
				wrapIfNeeded(out, PREC_UNARY, ctxPrec);
			}
			case ERange(start, end): {
				var out = printExprPrec(start, indent, PREC_LOWEST) + ".." + printExprPrec(end, indent, PREC_LOWEST);
				wrapIfNeeded(out, PREC_LOWEST, ctxPrec);
			}
			case ECast(expr, ty): {
				var inner = printExprPrec(expr, indent, PREC_CAST);
				var out = inner + " as " + ty;
				wrapIfNeeded(out, PREC_CAST, ctxPrec);
			}
			case EIndex(recv, index):
				wrapIfNeeded(printExprPrec(recv, indent, PREC_POSTFIX) + "[" + printExprPrec(index, indent, PREC_LOWEST) + "]", PREC_POSTFIX, ctxPrec);
			case EStructLit(path, fields): {
				var parts = fields.map(f -> f.name + ": " + printExprPrec(f.expr, indent, PREC_LOWEST)).join(", ");
				var out = path + " { " + parts + " }";
				wrapIfNeeded(out, PREC_PRIMARY, ctxPrec);
			}
			case EAssign(lhs, rhs): {
				// Assignments accept any Rust expression on the RHS without needing parentheses.
				// Prefer `x = if ... { ... } else { ... }` over `x = (if ...)`.
				var out = printExprPrec(lhs, indent, PREC_ASSIGN) + " = " + printExprPrec(rhs, indent, PREC_LOWEST);
				wrapIfNeeded(out, PREC_ASSIGN, ctxPrec);
			}
			case EBlock(b):
				var out = printBlock(b, indent);
				wrapIfNeeded(out, PREC_LOWEST, ctxPrec);
			case EIf(cond, thenExpr, elseExpr): {
				var thenPrinted = printIfBranch(thenExpr, indent);
				if (elseExpr == null) {
					var out = "if " + printExprPrec(cond, indent, PREC_LOWEST) + " " + thenPrinted;
					wrapIfNeeded(out, PREC_LOWEST, ctxPrec);
				} else {
					var elsePrinted = printIfBranch(elseExpr, indent);
					var out = "if " + printExprPrec(cond, indent, PREC_LOWEST) + " " + thenPrinted + " else " + elsePrinted;
					wrapIfNeeded(out, PREC_LOWEST, ctxPrec);
				}
			}
			case EMatch(scrutinee, arms): {
				var ind = indentString(indent);
				var innerInd = indentString(indent + 1);

				var lines: Array<String> = [];
				for (a in arms) {
					var pat = printPattern(a.pat);
					var ex = printExprPrec(a.expr, indent + 1, PREC_LOWEST);
					var needsComma = switch (a.expr) {
						case EBlock(_): false;
						case _: true;
					}
					lines.push(innerInd + pat + " => " + ex + (needsComma ? "," : ""));
				}

				if (lines.length == 0) {
					wrapIfNeeded("match " + printExprPrec(scrutinee, indent, PREC_LOWEST) + " { }", PREC_LOWEST, ctxPrec);
				} else {
					var out = "match " + printExprPrec(scrutinee, indent, PREC_LOWEST) + " {\n" + lines.join("\n") + "\n" + ind + "}";
					wrapIfNeeded(out, PREC_LOWEST, ctxPrec);
				}
			}
		}
	}

	static function wrapIfNeeded(s: String, exprPrec: Int, ctxPrec: Int): String {
		return (exprPrec < ctxPrec) ? ("(" + s + ")") : s;
	}

	static function binaryPrec(op: String): Int {
		return switch (op) {
			case "*" | "/" | "%": PREC_MUL;
			case "+" | "-": PREC_ADD;
			case "==" | "!=": PREC_EQ;
			case "<" | "<=" | ">" | ">=": PREC_CMP;
			case "&&": PREC_AND;
			case "||": PREC_OR;
			case _: PREC_ADD;
		}
	}

	static function printPattern(p: RustAST.RustPattern): String {
		return switch (p) {
			case PWildcard: "_";
			case PBind(name): name;
			case PPath(path): path;
			case PLitInt(v): Std.string(v);
			case PLitBool(v): v ? "true" : "false";
			case PLitString(v): '"' + escapeStringLiteral(v) + '"';
			case PTupleStruct(path, fields): path + "(" + fields.map(printPattern).join(", ") + ")";
			case POr(patterns): patterns.map(printPattern).join(" | ");
		}
	}

	static function printIfBranch(e: RustAST.RustExpr, indent: Int): String {
		return switch (e) {
			case EBlock(_): printExpr(e, indent);
			case _: "{ " + printExpr(e, indent) + " }";
		}
	}

	static function indentString(level: Int): String {
		var out = new StringBuf();
		for (_ in 0...level) out.add("    ");
		return out.toString();
	}

	static function escapeStringLiteral(s: String): String {
		// Minimal escaping for Rust string literals.
		var out = new StringBuf();
		for (i in 0...s.length) {
			var ch = s.charAt(i);
			switch (ch) {
				case "\\": out.add("\\\\");
				case "\"": out.add("\\\"");
				case "\n": out.add("\\n");
				case "\r": out.add("\\r");
				case "\t": out.add("\\t");
				default: out.add(ch);
			}
		}
		return out.toString();
	}
}
