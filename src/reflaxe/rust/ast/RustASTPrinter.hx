package reflaxe.rust.ast;

import haxe.io.Bytes;
import reflaxe.rust.RustSourceMap.RustPrintedSourceFile;
import reflaxe.rust.RustSourceMap.RustPrintedSourceMapping;
import reflaxe.rust.RustSourceMap.RustSourceMapNodeKind;
import reflaxe.rust.ast.RustAST;
import reflaxe.rust.ast.RustAST.RustOrigin;
import reflaxe.rust.ast.RustAST.RustOriginTools;

class RustASTPrinter {
	static var activeSourceMapRecorder:Null<RustSourceMapPrinterRecorder> = null;
	// Rust-ish precedence levels used to avoid excessive parentheses.
	// Higher number = tighter binding.
	static inline var PREC_LOWEST = 0;
	static inline var PREC_ASSIGN = 10;
	static inline var PREC_OR = 20;
	static inline var PREC_AND = 30;
	static inline var PREC_BITOR = 32;
	static inline var PREC_BITXOR = 33;
	static inline var PREC_BITAND = 34;
	static inline var PREC_EQ = 35;
	static inline var PREC_CMP = 40;
	static inline var PREC_SHIFT = 50;
	static inline var PREC_ADD = 60;
	static inline var PREC_MUL = 70;
	static inline var PREC_CAST = 80;
	static inline var PREC_UNARY = 85;
	static inline var PREC_POSTFIX = 90; // call/field/index
	static inline var PREC_PRIMARY = 100;

	static function isComparisonLikeOp(op:String):Bool {
		return switch (op) {
			case "<", ">", "<=", ">=", "==", "!=": true;
			case _: false;
		}
	}

	static function isComparisonLikeExpr(expr:RustAST.RustExpr):Bool {
		return switch (RustOriginTools.withoutExpressionOrigin(expr)) {
			case EBinary(op, _, _): isComparisonLikeOp(op);
			case _: false;
		}
	}

	public static function printFile(file:RustAST.RustFile):String {
		var out = printItemSequence(file.items);
		return out.length > 0 ? (out + "\n") : "";
	}

	/**
		Prints byte-identical Rust while recording the ranges owned by origin wrappers.

		Why
		- Source mapping must reuse the canonical printer. A second printer would inevitably drift in
		  whitespace, precedence, or rustfmt-facing shape.
		- Nested expressions are assembled as strings, so recording final byte offsets directly inside
		  each recursive call is not possible until the parent places that string.

		What
		- Temporarily inserts private non-Rust sentinels around `ROrigin`, `SOrigin`, and `EOrigin`
		  output, then removes them while calculating final UTF-8 byte spans.
		- Returns the exact same `code` as `printFile` plus typed mapping metadata.

		How
		- Recording is deliberately non-reentrant because this static printer is used synchronously by
		  Reflaxe's output iterator.
		- Sentinel collision, imbalance, or duplicate closure fails closed; wrappers around syntax that
		  prints no bytes simply produce no mapping.
	**/
	public static function printFileWithSourceMap(file:RustAST.RustFile, generatedFile:String):RustPrintedSourceFile {
		if (activeSourceMapRecorder != null)
			throw "Rust source-map printer is not reentrant";
		var recorder = new RustSourceMapPrinterRecorder(generatedFile);
		activeSourceMapRecorder = recorder;
		var marked:String;
		try {
			marked = printFile(file);
		} catch (error:haxe.Exception) {
			activeSourceMapRecorder = null;
			throw error;
		}
		activeSourceMapRecorder = null;
		return recorder.finish(marked);
	}

	/**
		Prints an ordered item list with compact separators for declaration families Rust groups naturally.

		Why
		- Raw header/module blocks historically kept consecutive attributes, aliases, imports, and module
		  declarations adjacent. Treating every structural node as a paragraph would add thousands of
		  blank lines and make otherwise hand-written-quality output harder to scan.

		What
		- Uses one newline between consecutive inner attributes, uses, type aliases, or modules.
		- Uses one blank line for every other item boundary; outer attributes remain inside `RAttributed`
		  and therefore cannot be detached by separator logic.

		How
		- Both files and recursively inline modules call this same function so formatting cannot drift.
	**/
	static function printItemSequence(items:Array<RustAST.RustItem>):String {
		var present:Array<{item:RustAST.RustItem, text:String}> = [];
		for (item in items) {
			// Do this structural check before printing. In mapping mode an empty raw item would otherwise
			// contain only recorder sentinels and incorrectly participate in separator decisions.
			if (!itemPrintsContent(item))
				continue;
			var text = printItem(item);
			if (StringTools.trim(text).length > 0)
				present.push({item: item, text: text});
		}
		var out = new StringBuf();
		for (index in 0...present.length) {
			if (index > 0)
				out.add(compactItemBoundary(present[index - 1].item, present[index].item) ? "\n" : "\n\n");
			out.add(present[index].text);
		}
		return out.toString();
	}

	static function itemPrintsContent(item:RustAST.RustItem):Bool {
		return switch (RustOriginTools.withoutItemOrigin(item)) {
			case RItemGroup(group): {
				var visible = false;
				for (child in group) {
					if (itemPrintsContent(child)) {
						visible = true;
						break;
					}
				}
				visible;
			}
			case RRaw(fragment): StringTools.trim(fragment.code).length > 0;
			case _: true;
		};
	}

	static function compactItemBoundary(left:RustAST.RustItem, right:RustAST.RustItem):Bool {
		return switch [RustOriginTools.withoutItemOrigin(left), RustOriginTools.withoutItemOrigin(right)] {
			case [RInnerAttribute(_), RInnerAttribute(_)]: true;
			case [RUse(_), RUse(_)]: true;
			case [RTypeAlias(_), RTypeAlias(_)]: true;
			case [RModule(_), RModule(_)]: true;
			case _: false;
		}
	}

	/**
	 * Minimal expression printer for code injection expansion.
	 *
	 * This intentionally prints a single expression without any surrounding context.
	 */
	public static function printExprForInjection(e:RustAST.RustExpr):String {
		return printExprPrec(e, 0, PREC_LOWEST);
	}

	/**
		Prints a structural path in Rust type position.

		Why
		- Type paths use `Vec<T>` while expression paths require `Vec::<T>` for the same typed segment.
		- Keeping this choice in the printer prevents callers from embedding turbofish punctuation in
		  identifiers or generic arguments.

		What
		- Renders roots, qualified paths, path separators, identifiers, and all segment arguments.

		How
		- Pass a validated `RustPath`; complete rendered strings are intentionally not accepted.
	**/
	public static function printTypePath(path:RustAST.RustPath):String {
		return printPath(path, false);
	}

	/** Prints a structural path in expression position, including required turbofish punctuation. */
	public static function printExpressionPath(path:RustAST.RustPath):String {
		return printPath(path, true);
	}

	/** Prints a structural path in pattern position using Rust's expression-path generic syntax. */
	public static function printPatternPath(path:RustAST.RustPath):String {
		return printPath(path, true);
	}

	/**
		Prints one structural Rust type without declaration context.

		Why
		- Generic arguments, qualified paths, const arrays, and regression contracts need the exact
		  same type printer as fields and function signatures.

		What
		- Exposes the canonical type printer while keeping all punctuation decisions centralized here.

		How
		- Callers provide a typed `RustType`; no target-syntax string is parsed or accepted.
	**/
	public static function printTypeSyntax(type:RustAST.RustType):String {
		return printType(type);
	}

	/**
		Prints a validated generic declaration list including its angle delimiters.

		Why
		- Bounds, defaults, lifetimes, commas, and `const` markers previously arrived as opaque strings.

		What
		- Returns an empty string for an empty list or `<...>` for a non-empty structural list.

		How
		- Ordering and duplicate validation happens in `RustGenericParameters.of`; this method only owns
		  deterministic Rust syntax.
	**/
	public static function printGenericParameters(parameters:RustAST.RustGenericParameters):String {
		if (parameters == null || parameters.count == 0)
			return "";
		var parts:Array<String> = [];
		for (parameter in parameters)
			parts.push(printGenericParameter(parameter));
		return "<" + parts.join(", ") + ">";
	}

	static function printItem(item:RustAST.RustItem):String {
		return switch (item) {
			case ROrigin(origin, inner): recordSourceMap(RustSourceMapNodeKind.Item, origin, printItem(inner));
			case RItemGroup(group): printItemGroup(group);
			case RAttributed(value): printAttributedItem(value);
			case RInnerAttribute(attribute): printAttribute(attribute, true);
			case RComment(comment): printComment(comment);
			case RUse(declaration): printUse(declaration);
			case RModule(declaration): printModule(declaration);
			case RConst(declaration): printConstant(declaration);
			case RStatic(declaration): printStatic(declaration);
			case RTypeAlias(declaration): printTypeAlias(declaration);
			case RFn(f): printFunction(f, 0);
			case RStruct(s): printStruct(s);
			case REnum(e): printEnum(e);
			case RTrait(declaration): printTrait(declaration);
			case RImpl(i): printImpl(i);
			case RRaw(fragment): recordSourceMap(RustSourceMapNodeKind.Item, fragment.origin, fragment.code);
		}
	}

	static function printItemGroup(group:RustAST.RustItemGroup):String {
		if (group == null)
			throw "Cannot print a null Rust item group";
		var parts:Array<String> = [];
		for (item in group) {
			if (!itemPrintsContent(item))
				continue;
			var printed = printItem(item);
			if (StringTools.trim(printed).length > 0)
				parts.push(printed);
		}
		return parts.join("\n");
	}

	/** Prints outer attributes immediately adjacent to their structurally owned target item. */
	static function printAttributedItem(value:RustAST.RustAttributedItem):String {
		if (value == null)
			throw "Cannot print a null Rust attributed item";
		var parts:Array<String> = [];
		for (attribute in value)
			parts.push(printAttribute(attribute, false));
		parts.push(printItem(value.target));
		return parts.join("\n");
	}

	/**
		Prints one structural Rust attribute.

		Why / What / How
		- Attachment chooses `#[...]` versus `#![...]`; the attribute owns only its validated path and
		  closed input form. Exact single-line `doc` string attributes use idiomatic `///` / `//!` sugar;
		  every other string value reuses Rust literal escaping. Paths always use the canonical
		  type-position printer, so target punctuation never leaks into lowering.
	**/
	static function printAttribute(attribute:RustAST.RustAttribute, inner:Bool):String {
		if (attribute == null)
			throw "Cannot print a null Rust attribute";
		if (attribute.inputKind == AttributeStringValue
			&& attribute.path.plainRelativeIdentifierName() == "doc"
			&& attribute.stringPayload != null
			&& attribute.stringPayload.indexOf("\n") == -1
			&& attribute.stringPayload.indexOf("\r") == -1) {
			var prefix = inner ? "//!" : "///";
			return attribute.stringPayload.length == 0 ? prefix : prefix + " " + attribute.stringPayload;
		}
		var body = printTypePath(attribute.path);
		switch (attribute.inputKind) {
			case AttributeBare:
			case AttributePathList:
				var arguments:Array<String> = [];
				for (argument in attribute)
					arguments.push(printTypePath(argument));
				body += "(" + arguments.join(", ") + ")";
			case AttributeStringValue:
				if (attribute.stringPayload == null)
					throw "Rust string-valued attribute is missing its payload";
				body += ' = "' + escapeStringLiteral(attribute.stringPayload) + '"';
		}
		return "#" + (inner ? "!" : "") + "[" + body + "]";
	}

	static function printComment(comment:RustAST.RustComment):String {
		if (comment == null)
			throw "Cannot print a null Rust comment";
		return comment.text.length == 0 ? "//" : "// " + comment.text;
	}

	static function printUse(declaration:RustAST.RustUseDeclaration):String {
		if (declaration == null)
			throw "Cannot print a null Rust use declaration";
		var out = visibilityPrefix(declaration.visibility, false) + "use " + printTypePath(declaration.prefix);
		switch (declaration.kind) {
			case UseExact:
				if (declaration.alias != null)
					out += " as " + printIdentifier(declaration.alias);
			case UseGlob:
				out += "::*";
			case UseGroup:
				var members:Array<String> = [];
				for (member in declaration) {
					var printed = switch (member.kind) {
						case UseMemberPath:
							if (member.pathValue == null)
								throw "Rust grouped-use path member is missing its path";
							printTypePath(member.pathValue);
						case UseMemberSelf: "self";
						case UseMemberGlob: "*";
					};
					if (member.alias != null)
						printed += " as " + printIdentifier(member.alias);
					members.push(printed);
				}
				out += "::{" + members.join(", ") + "}";
		}
		return out + ";";
	}

	static function printModule(declaration:RustAST.RustModuleDeclaration):String {
		if (declaration == null)
			throw "Cannot print a null Rust module declaration";
		var head = visibilityPrefix(declaration.visibility, false) + "mod " + printIdentifier(declaration.name);
		if (!declaration.isInline)
			return head + ";";
		if (declaration.itemCount == 0)
			return head + " { }";
		var body = printItemSequence([for (item in declaration) item]);
		return head + " {\n" + indentMultiline(body, 1) + "\n}";
	}

	static function printConstant(declaration:RustAST.RustConstantDeclaration):String {
		if (declaration == null)
			throw "Cannot print a null Rust constant declaration";
		return visibilityPrefix(declaration.visibility, false) + "const " + printIdentifier(declaration.name) + ": "
			+ printType(declaration.type) + " = " + printExpr(declaration.value, 0) + ";";
	}

	static function printStatic(declaration:RustAST.RustStaticDeclaration):String {
		if (declaration == null)
			throw "Cannot print a null Rust static declaration";
		return visibilityPrefix(declaration.visibility, false) + "static " + printIdentifier(declaration.name) + ": "
			+ printType(declaration.type) + " = " + printExpr(declaration.value, 0) + ";";
	}

	static function printTypeAlias(declaration:RustAST.RustTypeAliasDeclaration):String {
		if (declaration == null)
			throw "Cannot print a null Rust type alias";
		return visibilityPrefix(declaration.visibility, false) + "type " + printIdentifier(declaration.name)
			+ printGenericParameters(declaration.generics) + " = " + printType(declaration.type) + ";";
	}

	static function indentMultiline(value:String, level:Int):String {
		var prefix = indentString(level);
		return value.split("\n").map(line -> prefix + line).join("\n");
	}

	static function visibilityToken(vis:Null<RustAST.RustVisibility>, isPub:Bool):Null<String> {
		var v = vis != null ? vis : (isPub ? RustAST.RustVisibility.VPub : RustAST.RustVisibility.VPrivate);
		return switch (v) {
			case VPrivate: null;
			case VPub: "pub";
			case VPubCrate: "pub(crate)";
		}
	}

	static function visibilityPrefix(vis:Null<RustAST.RustVisibility>, isPub:Bool):String {
		var t = visibilityToken(vis, isPub);
		return t == null ? "" : (t + " ");
	}

	static function printStruct(s:RustAST.RustStruct):String {
		var head = visibilityPrefix(s.vis, s.isPub) + "struct " + s.name + printGenericParameters(s.generics);
		if (s.fields.length == 0) {
			return head + " { }";
		}

		var lines:Array<String> = [];
		for (f in s.fields) {
			var prefix = visibilityPrefix(f.vis, f.isPub);
			lines.push("    " + prefix + f.name + ": " + printType(f.ty) + ",");
		}
		return head + " {\n" + lines.join("\n") + "\n}";
	}

	static function printEnum(e:RustAST.RustEnum):String {
		var parts:Array<String> = [];
		var head = visibilityPrefix(e.vis, e.isPub) + "enum " + e.name + printGenericParameters(e.generics);
		if (e.variants.length == 0) {
			parts.push(head + " { }");
			return parts.join("\n");
		}

		var lines:Array<String> = [];
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

	/** Prints one complete structural trait declaration and its associated-item surface. */
	static function printTrait(declaration:RustAST.RustTraitDeclaration):String {
		if (declaration == null)
			throw "Cannot print a null Rust trait declaration";
		var head = visibilityPrefix(declaration.visibility, false)
			+ "trait "
			+ printIdentifier(declaration.name)
			+ printGenericParameters(declaration.generics);
		var supertraits:Array<String> = [];
		for (bound in declaration.supertraitIterator())
			supertraits.push(printGenericBound(bound));
		if (supertraits.length > 0)
			head += ": " + supertraits.join(" + ");
		head += printWhereClause(declaration.whereClause);
		if (declaration.itemCount == 0)
			return head + " { }";
		var parts:Array<String> = [];
		for (item in declaration)
			parts.push(printAssociatedItem(item, 1));
		return head + " {\n" + parts.join("\n") + "\n}";
	}

	/**
		Prints an inherent or trait impl without consulting rendered type/path text.

		Why / What / How
		- `traitPath == null` is the validated inherent form; otherwise the path prints before `for`.
		- Inherent methods retain the historical blank separator, while trait-associated items remain
		  adjacent like rustfmt's trait-impl layout. Marker impls use the compact empty-body form.
	**/
	static function printImpl(i:RustAST.RustImpl):String {
		if (i == null)
			throw "Cannot print a null Rust impl declaration";
		var head = "impl" + printGenericParameters(i.generics) + " ";
		if (i.traitPath != null)
			head += printTypePath(i.traitPath) + " for ";
		head += printType(i.forType) + printWhereClause(i.whereClause);
		if (i.itemCount == 0)
			return head + " { }";

		var parts:Array<String> = [];
		for (item in i)
			parts.push(printAssociatedItem(item, 1));
		var separator = i.isTraitImpl ? "\n" : "\n\n";
		return head + " {\n" + parts.join(separator) + "\n}";
	}

	/** Prints one structural associated function, type, constant, or admitted raw metadata body. */
	static function printAssociatedItem(item:RustAST.RustAssociatedItem, indent:Int):String {
		if (item == null)
			throw "Cannot print a null Rust associated item";
		return switch (item) {
			case AssocFunction(method): printAssociatedFunction(method, indent);
			case AssocType(declaration): printAssociatedType(declaration, indent);
			case AssocConst(declaration): printAssociatedConstant(declaration, indent);
			case AssocRaw(fragment):
				recordSourceMap(RustSourceMapNodeKind.Item, fragment.origin, indentRawAssociated(fragment, indent));
		};
	}

	static function printAssociatedFunction(method:RustAST.RustAssociatedFunction, indent:Int):String {
		if (method == null)
			throw "Cannot print a null Rust associated function";
		var signature:Array<String> = [];
		var visibility = visibilityToken(method.visibility, false);
		if (visibility != null)
			signature.push(visibility);
		if (method.isAsync)
			signature.push("async");
		signature.push("fn");
		signature.push(printIdentifier(method.name) + printGenericParameters(method.generics));

		var parameters:Array<String> = [];
		if (method.receiver != null)
			parameters.push(printSelfReceiver(method.receiver));
		for (parameter in method)
			parameters.push(printIdentifier(parameter.name) + ": " + printType(parameter.type));
		var out = indentString(indent) + signature.join(" ") + "(" + parameters.join(", ") + ")";
		if (method.returnType != null)
			out += " -> " + printType(method.returnType);
		out += printWhereClause(method.whereClause);
		return method.body == null ? out + ";" : out + " " + printBlock(method.body, indent);
	}

	static function printSelfReceiver(receiver:RustAST.RustSelfReceiver):String {
		return switch (receiver) {
			case ReceiverValue(mutable): (mutable ? "mut " : "") + "self";
			case ReceiverBorrowed(mutable, lifetime): {
					var out = "&";
					if (lifetime != null)
						out += printLifetime(lifetime) + " ";
					if (mutable)
						out += "mut ";
					out + "self";
				}
			case ReceiverTyped(type, mutable): (mutable ? "mut " : "") + "self: " + printType(type);
		};
	}

	static function printAssociatedType(declaration:RustAST.RustAssociatedTypeDeclaration, indent:Int):String {
		if (declaration == null)
			throw "Cannot print a null Rust associated type";
		var out = indentString(indent) + "type " + printIdentifier(declaration.name) + printGenericParameters(declaration.generics);
		var bounds:Array<String> = [];
		for (bound in declaration)
			bounds.push(printGenericBound(bound));
		if (bounds.length > 0)
			out += ": " + bounds.join(" + ");
		if (declaration.value == null) {
			out += printWhereClause(declaration.whereClause);
		} else {
			out += " = " + printType(declaration.value);
			out += printWhereClause(declaration.whereClause);
		}
		return out + ";";
	}

	static function printAssociatedConstant(declaration:RustAST.RustAssociatedConstantDeclaration, indent:Int):String {
		if (declaration == null)
			throw "Cannot print a null Rust associated constant";
		var out = indentString(indent)
			+ visibilityPrefix(declaration.visibility, false)
			+ "const "
			+ printIdentifier(declaration.name)
			+ ": "
			+ printType(declaration.type);
		if (declaration.value != null)
			out += " = " + printExpr(declaration.value, indent);
		return out + ";";
	}

	static function indentRawAssociated(fragment:RustAST.RustRawCode, indent:Int):String {
		if (fragment == null)
			throw "Cannot print a null raw associated body";
		var prefix = indentString(indent);
		return [for (line in fragment.code.split("\n")) prefix + line].join("\n");
	}

	static function printWhereClause(clause:RustAST.RustWhereClause):String {
		if (clause == null)
			throw "Cannot print a null Rust where clause";
		if (clause.predicateCount == 0)
			return "";
		var predicates:Array<String> = [];
		for (predicate in clause)
			predicates.push(printWherePredicate(predicate));
		return " where " + predicates.join(", ");
	}

	static function printWherePredicate(predicate:RustAST.RustWherePredicate):String {
		if (predicate == null)
			throw "Cannot print a null Rust where predicate";
		return switch (predicate.kind) {
			case WhereTypeBounds: {
					if (predicate.typeValue == null)
						throw "Rust type where-predicate is missing its type";
					var bounds:Array<String> = [];
					for (bound in predicate.genericBoundIterator())
						bounds.push(printGenericBound(bound));
					printType(predicate.typeValue) + ": " + bounds.join(" + ");
				}
			case WhereLifetimeBounds: {
					if (predicate.lifetimeValue == null)
						throw "Rust lifetime where-predicate is missing its lifetime";
					var bounds:Array<String> = [];
					for (bound in predicate.lifetimeBoundIterator())
						bounds.push(printLifetime(bound));
					printLifetime(predicate.lifetimeValue) + ": " + bounds.join(" + ");
				}
		};
	}

	static function printFunction(f:RustAST.RustFunction, indent:Int):String {
		var sigParts:Array<String> = [];
		var tok = visibilityToken(f.vis, f.isPub);
		if (tok != null)
			sigParts.push(tok);
		if (f.isAsync == true)
			sigParts.push("async");
		sigParts.push("fn");
		var name = f.name + printGenericParameters(f.generics);
		sigParts.push(name);

		var args = f.args.map(a -> '${a.name}: ${printType(a.ty)}').join(", ");
		var sig = sigParts.join(" ") + '($args)';
		if (f.ret != RUnit) {
			sig += ' -> ${printType(f.ret)}';
		}

		var ind = indentString(indent);
		return ind + sig + " " + printBlock(f.body, indent);
	}

	static function printType(t:RustAST.RustType):String {
		return switch (t) {
			case RUnit: "()";
			case RBool: "bool";
			case RI32: "i32";
			case RF64: "f64";
			case RString: "String";
			case RNamed(path): printTypePath(path);
			case RBorrow(inner, mutable, lifetime): {
					var prefix = "&";
					if (lifetime != null)
						prefix += printLifetime(lifetime) + " ";
					if (mutable)
						prefix += "mut ";
					prefix + printType(inner);
				}
			case RTuple(elements): {
					if (elements.length == 0) {
						"()";
					} else if (elements.length == 1) {
						"(" + printType(elements[0]) + ",)";
					} else {
						"(" + elements.map(printType).join(", ") + ")";
					}
				}
			case RSlice(element): "[" + printType(element) + "]";
			case RArray(element, length): "[" + printType(element) + "; " + printConstArgument(length) + "]";
			case RTraitObject(object): {
					var bounds:Array<String> = [];
					for (bound in object)
						bounds.push(printGenericBound(bound));
					"dyn " + bounds.join(" + ");
				}
		}
	}

	static function printPath(path:RustAST.RustPath, expressionContext:Bool):String {
		if (path == null)
			throw "Cannot print a null Rust path";
		var renderedSegments:Array<String> = [];
		for (segment in path)
			renderedSegments.push(printPathSegment(segment, expressionContext));
		var tail = renderedSegments.join("::");
		return switch (path.root) {
			case PathRelative: tail;
			case PathAbsolute: "::" + tail;
			case PathCrate: tail.length == 0 ? "crate" : "crate::" + tail;
			case PathSelfModule: tail.length == 0 ? "self" : "self::" + tail;
			case PathSuper(depth): {
					var roots:Array<String> = [];
					for (_ in 0...depth)
						roots.push("super");
					var prefix = roots.join("::");
					tail.length == 0 ? prefix : prefix + "::" + tail;
				}
			case PathTypeSelf: tail.length == 0 ? "Self" : "Self::" + tail;
			case PathQualified(selfType, traitPath): {
					var head = "<" + printType(selfType);
					if (traitPath != null)
						head += " as " + printTypePath(traitPath);
					head += ">";
					head + "::" + tail;
				}
		};
	}

	static function printPathSegment(segment:RustAST.RustPathSegment, expressionContext:Bool):String {
		if (segment == null)
			throw "Cannot print a null Rust path segment";
		var out = printIdentifier(segment.identifier);
		switch (segment.argumentStyle) {
			case PathArgumentsNone:
			case PathArgumentsAngle:
				var arguments:Array<String> = [];
				for (index in 0...segment.genericArgumentCount)
					arguments.push(printGenericArgument(segment.genericArgumentAt(index)));
				out += (expressionContext ? "::<" : "<") + arguments.join(", ") + ">";
			case PathArgumentsParenthesized:
				var inputs:Array<String> = [];
				for (index in 0...segment.inputTypeCount)
					inputs.push(printType(segment.inputTypeAt(index)));
				out += "(" + inputs.join(", ") + ")";
				if (segment.outputType != null)
					out += " -> " + printType(segment.outputType);
		}
		return out;
	}

	static function printIdentifier(identifier:RustAST.RustIdentifier):String {
		if (identifier == null)
			throw "Cannot print a null Rust identifier";
		return (identifier.isRaw ? "r#" : "") + identifier.name;
	}

	static function printLifetime(lifetime:RustAST.RustLifetime):String {
		if (lifetime == null)
			throw "Cannot print a null Rust lifetime";
		return switch (lifetime.kind) {
			case LifetimeNamed:
				if (lifetime.name == null)
					throw "Named Rust lifetime is missing its identifier";
				"'" + printIdentifier(lifetime.name);
			case LifetimeStatic: "'static";
			case LifetimeInferred: "'_";
		};
	}

	static function printConstArgument(argument:RustAST.RustConstArgument):String {
		if (argument == null)
			throw "Cannot print a null Rust const argument";
		return switch (argument.kind) {
			case ConstInteger:
				if (argument.integerDigits == null)
					throw "Integer const argument is missing its value";
				(argument.integerNegative ? "-" : "") + argument.integerDigits;
			case ConstBoolean:
				if (argument.boolValue == null)
					throw "Boolean const argument is missing its value";
				argument.boolValue ? "true" : "false";
			case ConstPath:
				if (argument.pathValue == null)
					throw "Path const argument is missing its path";
				printExpressionPath(argument.pathValue);
		};
	}

	static function printGenericArgument(argument:RustAST.RustGenericArgument):String {
		return switch (argument) {
			case GenericType(type): printType(type);
			case GenericConst(value): printConstArgument(value);
			case GenericLifetime(lifetime): printLifetime(lifetime);
			case GenericInfer: "_";
		};
	}

	static function printGenericBound(bound:RustAST.RustGenericBound):String {
		return switch (bound) {
			case GenericTraitBound(path): printTypePath(path);
			case GenericRelaxedSized: "?Sized";
			case GenericLifetimeBound(lifetime): printLifetime(lifetime);
		};
	}

	static function printGenericParameter(parameter:RustAST.RustGenericParameter):String {
		return switch (parameter) {
			case GenericLifetimeParam(name, bounds): {
					var out = "'" + printIdentifier(name);
					if (bounds.length > 0)
						out += ": " + bounds.map(printLifetime).join(" + ");
					out;
				}
			case GenericTypeParam(name, bounds, defaultType): {
					var out = printIdentifier(name);
					if (bounds.length > 0)
						out += ": " + bounds.map(printGenericBound).join(" + ");
					if (defaultType != null)
						out += " = " + printType(defaultType);
					out;
				}
			case GenericConstParam(name, type, defaultValue): {
					var out = "const " + printIdentifier(name) + ": " + printType(type);
					if (defaultValue != null)
						out += " = " + printConstArgument(defaultValue);
					out;
				}
		};
	}

	static function printBlock(b:RustAST.RustBlock, indent:Int):String {
		var ind = indentString(indent);
		var innerInd = indentString(indent + 1);

		var lines:Array<String> = [];
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

	static function printStmt(s:RustAST.RustStmt, indent:Int):String {
		return switch (s) {
			case SOrigin(origin, statement): recordSourceMap(RustSourceMapNodeKind.Statement, origin, printStmt(statement, indent));
			case RLet(name, mutable, ty, expr): {
					var out = "let";
					if (mutable)
						out += " mut";
					out += " " + name;
					if (ty != null)
						out += ": " + printType(ty);
					if (expr != null)
						out += " = " + printExpr(expr, indent);
					out + ";";
				}
			case RSemi(e): {
					// Avoid `;;` when an injected raw expression already includes a trailing semicolon.
					var printed = printSemiExpression(e, indent);
					var alreadyTerminated = switch (RustOriginTools.withoutExpressionOrigin(e)) {
						case ERaw(fragment): StringTools.endsWith(StringTools.rtrim(fragment.code), ";");
						case _: false;
					};
					alreadyTerminated ? printed : printed + ";";
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
			case RBreak:
				"break;";
			case RContinue:
				"continue;";
		}
	}

	static function printExpr(e:RustAST.RustExpr, indent:Int):String {
		return printExprPrec(e, indent, PREC_LOWEST);
	}

	/** Trims raw statement whitespace inside provenance wrappers so recorder bytes stay invisible. */
	static function printSemiExpression(e:RustAST.RustExpr, indent:Int):String {
		return switch (e) {
			case EOrigin(origin, expression):
				recordSourceMap(RustSourceMapNodeKind.Expression, origin, printSemiExpression(expression, indent));
			case ERaw(fragment):
				recordSourceMap(RustSourceMapNodeKind.Expression, fragment.origin, StringTools.rtrim(fragment.code));
			case _: printExpr(e, indent);
		};
	}

	static function printExprPrec(e:RustAST.RustExpr, indent:Int, ctxPrec:Int):String {
		return switch (e) {
			case EOrigin(origin, expression):
				recordSourceMap(RustSourceMapNodeKind.Expression, origin, printExprPrec(expression, indent, ctxPrec));
			case ERaw(fragment): recordSourceMap(RustSourceMapNodeKind.Expression, fragment.origin, fragment.code);
			case ESelf: "self";
			case ELitUnit: "()";
			case ELitInt(v): Std.string(v);
			case ELitUInt32(bits): "0x" + StringTools.hex(bits, 8).toLowerCase() + "u32";
			case ELitFloat(v): {
					// Rust requires a decimal point for float literals in some contexts (e.g. `1.`).
					var s = Std.string(v);
					if (s.indexOf(".") == -1 && s.indexOf("e") == -1 && s.indexOf("E") == -1)
						s += ".0";
					s;
				}
			case ELitBool(v): v ? "true" : "false";
			case ELitString(v): '"' + escapeStringLiteral(v) + '"';
			case EPath(path): printExpressionPath(path);
			case EPinAsyncMove(body): {
					var out = "Box::pin(async move " + printBlock(body, indent) + ")";
					wrapIfNeeded(out, PREC_PRIMARY, ctxPrec);
				}
			case EAwait(expr): {
					var inner = printExprPrec(expr, indent, PREC_POSTFIX);
					var out = inner + ".await";
					wrapIfNeeded(out, PREC_POSTFIX, ctxPrec);
				}
			case EField(recv, field): {
					var recvStr = printExprPrec(recv, indent, PREC_POSTFIX);
					var out = recvStr + "." + printPathSegment(field.asPathSegment(), true);
					wrapIfNeeded(out, PREC_POSTFIX, ctxPrec);
				}
			case ECall(func, args): {
					var a = args.map(x -> printExprPrec(x, indent, PREC_LOWEST)).join(", ");
					var fnStr = printExprPrec(func, indent, PREC_POSTFIX);
					var out = fnStr + "(" + a + ")";
					wrapIfNeeded(out, PREC_POSTFIX, ctxPrec);
				}
			case EClosure(args, body, isMove): {
					var a = args.map(printClosureParameter).join(", ");
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
					if (isComparisonLikeOp(op) && isComparisonLikeExpr(left))
						leftStr = "(" + leftStr + ")";
					// Rust parsing gotcha: `x as i32 < 0` parses as `x as i32<0>` (generic arguments).
					// Force parens around casts when used in comparisons.
					if ((op == "<" || op == ">" || op == "<=" || op == ">=") && switch (RustOriginTools.withoutExpressionOrigin(left)) {
							case ECast(_, _): true;
							case _: false;
						}) {
						leftStr = "(" + leftStr + ")";
						}
					// Preserve grouping: for left-associative ops, parenthesize RHS when it has the same precedence.
					var rightStr = printExprPrec(right, indent, prec + 1);
					if (isComparisonLikeOp(op) && isComparisonLikeExpr(right))
						rightStr = "(" + rightStr + ")";
					if ((op == "<" || op == ">" || op == "<=" || op == ">=") && switch (RustOriginTools.withoutExpressionOrigin(right)) {
							case ECast(_, _): true;
							case _: false;
						}) {
						rightStr = "(" + rightStr + ")";
						}
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
					var out = inner + " as " + printType(ty);
					wrapIfNeeded(out, PREC_CAST, ctxPrec);
				}
			case EIndex(recv, index):
				wrapIfNeeded(printExprPrec(recv, indent, PREC_POSTFIX) + "[" + printExprPrec(index, indent, PREC_LOWEST) + "]", PREC_POSTFIX, ctxPrec);
			case EStructLit(path, fields): {
					var parts = fields.map(f -> f.name + ": " + printExprPrec(f.expr, indent, PREC_LOWEST)).join(", ");
					var out = printExpressionPath(path) + " { " + parts + " }";
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

					var lines:Array<String> = [];
					for (a in arms) {
						var pat = printPattern(a.pat);
						var ex = printExprPrec(a.expr, indent + 1, PREC_LOWEST);
						var needsComma = switch (RustOriginTools.withoutExpressionOrigin(a.expr)) {
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

	static function wrapIfNeeded(s:String, exprPrec:Int, ctxPrec:Int):String {
		return (exprPrec < ctxPrec) ? ("(" + s + ")") : s;
	}

	static function binaryPrec(op:String):Int {
		return switch (op) {
			case "*" | "/" | "%": PREC_MUL;
			case "+" | "-": PREC_ADD;
			case "<<" | ">>": PREC_SHIFT;
			case "&": PREC_BITAND;
			case "^": PREC_BITXOR;
			case "|": PREC_BITOR;
			case "==" | "!=": PREC_EQ;
			case "<" | "<=" | ">" | ">=": PREC_CMP;
			case "&&": PREC_AND;
			case "||": PREC_OR;
			case _: PREC_LOWEST;
		}
	}

	static function printPattern(p:RustAST.RustPattern, parenthesizeOr:Bool = false):String {
		return switch (p) {
			case PWildcard: "_";
			case PBind(name): name;
			case PAlias(name, pattern): name + " @ " + printPattern(pattern, true);
			case PPath(path): printPatternPath(path);
			case PLitInt(v): Std.string(v);
			case PLitUInt32(bits): "0x" + StringTools.hex(bits, 8).toLowerCase() + "u32";
			case PLitBool(v): v ? "true" : "false";
			case PLitString(v): '"' + escapeStringLiteral(v) + '"';
			case PTuple(fields): {
					if (fields.length == 0) {
						"()";
					} else if (fields.length == 1) {
						"(" + printPattern(fields[0], true) + ",)";
					} else {
						"(" + fields.map(field -> printPattern(field, true)).join(", ") + ")";
					}
				}
			case PTupleStruct(path, fields):
				printPatternPath(path) + "(" + fields.map(field -> printPattern(field, true)).join(", ") + ")";
			case POr(patterns): {
					if (patterns == null || patterns.length < 2)
						throw "Rust or-pattern requires at least two alternatives";
					var rendered = patterns.map(pattern -> printPattern(pattern, true)).join(" | ");
					parenthesizeOr ? "(" + rendered + ")" : rendered;
				}
		}
	}

	static function printClosureParameter(parameter:RustAST.RustClosureParameter):String {
		if (parameter == null)
			throw "Cannot print a null Rust closure parameter";
		// Closure `|` delimiters are ambiguous with a top-level or-pattern. Nested aliases and tuple
		// fields use the same structural precedence rule above.
		var out = printPattern(parameter.patternValue, true);
		if (parameter.ty != null)
			out += ": " + printType(parameter.ty);
		return out;
	}

	static function printIfBranch(e:RustAST.RustExpr, indent:Int):String {
		return switch (RustOriginTools.withoutExpressionOrigin(e)) {
			case EBlock(_): printExpr(e, indent);
			case _: "{ " + printExpr(e, indent) + " }";
		}
	}

	static function recordSourceMap(kind:RustSourceMapNodeKind, origin:RustOrigin, text:String):String {
		return activeSourceMapRecorder == null ? text : activeSourceMapRecorder.wrap(kind, origin, text);
	}

	static function indentString(level:Int):String {
		var out = new StringBuf();
		for (_ in 0...level)
			out.add("    ");
		return out.toString();
	}

	static function escapeStringLiteral(s:String):String {
		// Minimal escaping for Rust string literals.
		var out = new StringBuf();
		for (i in 0...s.length) {
			var ch = s.charAt(i);
			switch (ch) {
				case "\\":
					out.add("\\\\");
				case "\"":
					out.add("\\\"");
				case "\n":
					out.add("\\n");
				case "\r":
					out.add("\\r");
				case "\t":
					out.add("\\t");
				default:
					out.add(ch);
			}
		}
		return out.toString();
	}
}

private typedef RustSourceMapPrinterMark = {
	var nodeKind:RustSourceMapNodeKind;
	var origin:RustOrigin;
	var originDepth:Null<Int>;
	var startByte:Null<Int>;
	var endByte:Null<Int>;
}

/** Private sentinel recorder used only by `RustASTPrinter.printFileWithSourceMap`. */
private class RustSourceMapPrinterRecorder {
	static inline var MARKER_PREFIX:String = "\x01HXSM:";
	static inline var MARKER_SUFFIX:String = ":\x02";

	final generatedFile:String;
	final marks:Array<RustSourceMapPrinterMark>;

	public function new(generatedFile:String) {
		this.generatedFile = generatedFile;
		this.marks = [];
	}

	public function wrap(nodeKind:RustSourceMapNodeKind, origin:RustOrigin, text:String):String {
		if (text == null)
			throw "Rust source-map printer cannot record null text";
		var id = marks.length;
		marks.push({nodeKind: nodeKind, origin: origin, originDepth: null, startByte: null, endByte: null});
		return marker(id, "start") + text + marker(id, "end");
	}

	public function finish(marked:String):RustPrintedSourceFile {
		var output = new StringBuf();
		var cursor = 0;
		var byteOffset = 0;
		var active:Array<Int> = [];
		while (cursor < marked.length) {
			var markerStart = marked.indexOf(MARKER_PREFIX, cursor);
			if (markerStart < 0) {
				var tail = marked.substr(cursor);
				output.add(tail);
				byteOffset += Bytes.ofString(tail).length;
				cursor = marked.length;
				break;
			}
			var ordinary = marked.substring(cursor, markerStart);
			output.add(ordinary);
			byteOffset += Bytes.ofString(ordinary).length;
			var markerEnd = marked.indexOf(MARKER_SUFFIX, markerStart + MARKER_PREFIX.length);
			if (markerEnd < 0)
				throw "Rust source-map printer found an unterminated sentinel";
			var payload = marked.substring(markerStart + MARKER_PREFIX.length, markerEnd);
			var pieces = payload.split(":");
			if (pieces.length != 2)
				throw 'Rust source-map printer found an invalid sentinel: $payload';
			var id = Std.parseInt(pieces[0]);
			if (id == null || id < 0 || id >= marks.length)
				throw 'Rust source-map printer found an unknown sentinel id: ${pieces[0]}';
			var mark = marks[id];
			switch (pieces[1]) {
				case "start":
					if (mark.startByte != null)
						throw 'Rust source-map sentinel $id started twice';
					mark.originDepth = active.length;
					mark.startByte = byteOffset;
					active.push(id);
				case "end":
					if (mark.startByte == null || mark.endByte != null || active.length == 0 || active[active.length - 1] != id)
						throw 'Rust source-map sentinel $id ended out of order';
					active.pop();
					mark.endByte = byteOffset;
				case _:
					throw 'Rust source-map printer found an unknown sentinel action: ${pieces[1]}';
			}
			cursor = markerEnd + MARKER_SUFFIX.length;
		}

		var mappings:Array<RustPrintedSourceMapping> = [];
		for (index in 0...marks.length) {
			var mark = marks[index];
			if (mark.originDepth == null || mark.startByte == null || mark.endByte == null)
				throw 'Rust source-map sentinel $index was not balanced';
			if (mark.endByte > mark.startByte)
				mappings.push(RustPrintedSourceMapping.at(mark.nodeKind, mark.origin, mark.originDepth, mark.startByte, mark.endByte));
		}
		return RustPrintedSourceFile.of(generatedFile, output.toString(), mappings);
	}

	inline function marker(id:Int, action:String):String {
		return MARKER_PREFIX + id + ":" + action + MARKER_SUFFIX;
	}
}
