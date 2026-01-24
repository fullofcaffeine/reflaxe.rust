package reflaxe.rust.ast;

import reflaxe.rust.ast.RustAST;

class RustASTPrinter {
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
		return printExpr(e, 0);
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

	static function printStruct(s: RustAST.RustStruct): String {
		var head = (s.isPub ? "pub " : "") + "struct " + s.name;
		if (s.fields.length == 0) {
			return head + " { }";
		}

		var lines: Array<String> = [];
		for (f in s.fields) {
			var prefix = f.isPub ? "pub " : "";
			lines.push("    " + prefix + f.name + ": " + printType(f.ty) + ",");
		}
		return head + " {\n" + lines.join("\n") + "\n}";
	}

	static function printEnum(e: RustAST.RustEnum): String {
		var parts: Array<String> = [];
		if (e.derives.length > 0) {
			parts.push("#[derive(" + e.derives.join(", ") + ")]");
		}

		var head = (e.isPub ? "pub " : "") + "enum " + e.name;
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
		var head = "impl " + i.forType;
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
		if (f.isPub) sigParts.push("pub");
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
			case RSemi(e):
				printExpr(e, indent) + ";";
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
			case EField(recv, field): printExpr(recv, indent) + "." + field;
			case ECall(func, args): {
				var a = args.map(x -> printExpr(x, indent)).join(", ");
				printExpr(func, indent) + "(" + a + ")";
			}
			case EClosure(args, body): {
				var a = args.join(", ");
				"|" + a + "| " + printBlock(body, indent);
			}
			case EMacroCall(name, args): {
				var a = args.map(x -> printExpr(x, indent)).join(", ");
				if (name == "vec") {
					name + "![" + a + "]";
				} else {
					name + "!(" + a + ")";
				}
			}
			case EBinary(op, left, right):
				"(" + printExpr(left, indent) + " " + op + " " + printExpr(right, indent) + ")";
			case EUnary(op, expr):
				"(" + op + printExpr(expr, indent) + ")";
			case ERange(start, end):
				printExpr(start, indent) + ".." + printExpr(end, indent);
			case ECast(expr, ty):
				"(" + printExpr(expr, indent) + " as " + ty + ")";
			case EIndex(recv, index):
				printExpr(recv, indent) + "[" + printExpr(index, indent) + "]";
			case EAssign(lhs, rhs):
				printExpr(lhs, indent) + " = " + printExpr(rhs, indent);
			case EBlock(b):
				printBlock(b, indent);
			case EIf(cond, thenExpr, elseExpr): {
				var thenPrinted = printIfBranch(thenExpr, indent);
				if (elseExpr == null) {
					"if " + printExpr(cond, indent) + " " + thenPrinted;
				} else {
					var elsePrinted = printIfBranch(elseExpr, indent);
					"if " + printExpr(cond, indent) + " " + thenPrinted + " else " + elsePrinted;
				}
			}
			case EMatch(scrutinee, arms): {
				var ind = indentString(indent);
				var innerInd = indentString(indent + 1);

				var lines: Array<String> = [];
				for (a in arms) {
					var pat = printPattern(a.pat);
					var ex = printExpr(a.expr, indent + 1);
					var needsComma = switch (a.expr) {
						case EBlock(_): false;
						case _: true;
					}
					lines.push(innerInd + pat + " => " + ex + (needsComma ? "," : ""));
				}

				if (lines.length == 0) {
					"match " + printExpr(scrutinee, indent) + " { }";
				} else {
					"match " + printExpr(scrutinee, indent) + " {\n" + lines.join("\n") + "\n" + ind + "}";
				}
			}
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
