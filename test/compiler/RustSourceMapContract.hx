#if macro
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.RustProfile;
import reflaxe.rust.RustSourceMap;
import reflaxe.rust.RustSourceMap.RustMappedOrigin;
import reflaxe.rust.RustSourceMap.RustSourceMapNodeKind;
import reflaxe.rust.RustSourceMap.RustcGeneratedSpan;
import reflaxe.rust.ast.RustAST.RustAttribute;
import reflaxe.rust.ast.RustAST.RustAttributedItem;
import reflaxe.rust.ast.RustAST.RustComment;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustGeneratedOriginReason;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustOriginTools;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustRawCode;
import reflaxe.rust.ast.RustAST.RustSourceRawReason;
import reflaxe.rust.ast.RustASTPrinter;
import reflaxe.rust.ast.RustASTTransformer;
import reflaxe.rust.compiler.RustBuildContext;

/**
	Executable contract for deterministic Rust-to-Haxe source mappings.

	Why
	- A source map is dangerous if a transformer silently drops provenance or if lookup guesses from
	  a basename. Either failure can point a Rust diagnostic at innocent Haxe code.
	- Mapping bytes must not perturb the Rust printer, and serialized paths must never reveal a local
	  checkout location.

	What
	- Sends source-wrapped items, statements, and expressions through the real production pass
	  pipeline, including raw normalization and statement cleanup.
	- Serializes twice, decodes the typed artifact, and performs exact generated-file/content lookup.
	- Exercises compiler-generated reasons and fail-closed mutations for paths and content hashes.

	How
	- Source sentinels in this file provide distinct, real Haxe byte ranges.
	- The Node harness runs this macro twice and also compiles a real Haxe fixture end to end.
**/
class RustSourceMapContract {
	// SOURCE_MAP_ITEM_ORIGIN
	// SOURCE_MAP_STATEMENT_ORIGIN
	// SOURCE_MAP_EXPRESSION_ORIGIN
	// SOURCE_MAP_RAW_ORIGIN

	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectThrows(fn:() -> Void, message:String):Void {
		var threw = false;
		try {
			fn();
		} catch (_:haxe.Exception) {
			threw = true;
		}
		expect(threw, message);
	}

	static function sourcePosition(label:String):Position {
		var file = Context.resolvePath("RustSourceMapContract.hx");
		var content = sys.io.File.getContent(file);
		var start = content.indexOf(label);
		if (start < 0)
			throw 'missing source-map sentinel `$label`';
		return Context.makePosition({file: file, min: start, max: start + label.length});
	}

	static function local(name:String) {
		return reflaxe.rust.ast.RustAST.RustExpr.EPath(RustPath.relative([RustPathSegment.plain(name)]));
	}

	static function context(noHxrt:Bool = false):CompilationContext {
		var build = new RustBuildContext("rust_source_map_contract", noHxrt ? RustProfile.Metal : RustProfile.Portable, false, false, false, false,
			false, noHxrt, []);
		var result = new CompilationContext(build, [], [], [], false, false, []);
		result.setCurrentModule("RustSourceMapContract", sourcePosition("SOURCE_MAP_ITEM_ORIGIN"));
		return result;
	}

	public static function run():Void {
		var itemPos = sourcePosition("SOURCE_MAP_ITEM_ORIGIN");
		var statementPos = sourcePosition("SOURCE_MAP_STATEMENT_ORIGIN");
		var expressionPos = sourcePosition("SOURCE_MAP_EXPRESSION_ORIGIN");
		var rawPos = sourcePosition("SOURCE_MAP_RAW_ORIGIN");
		var testAttribute = RustAttribute.bare(RustPath.relative([RustPathSegment.plain("test")]));
		expectThrows(() -> RustAttributedItem.of([testAttribute], RustOriginTools.sourceItem(
			reflaxe.rust.ast.RustAST.RustItem.RComment(RustComment.line("not a declaration")), itemPos)),
			"an origin wrapper disguised an invalid outer-attribute target");
		expectThrows(() -> RustOriginTools.generatedItem(
			reflaxe.rust.ast.RustAST.RustItem.RComment(RustComment.line("unknown reason")), cast "invented-reason"),
			"generated-origin factory accepted a value outside the closed reason vocabulary");

		var printerEdgeFile:RustFile = {
			items: [
				RustOriginTools.generatedItem(reflaxe.rust.ast.RustAST.RustItem.RRaw(
					RustRawCode.compilerGenerated("", reflaxe.rust.ast.RustAST.RustCompilerRawReason.RawUnsupportedFallback)),
					RustGeneratedOriginReason.UnsupportedFallback),
				reflaxe.rust.ast.RustAST.RustItem.RFn({
					name: "printer_edges",
					isPub: false,
					generics: reflaxe.rust.ast.RustAST.RustGenericParameters.empty(),
					args: [],
					ret: reflaxe.rust.ast.RustAST.RustType.RUnit,
					body: {
						stmts: [reflaxe.rust.ast.RustAST.RustStmt.RSemi(RustOriginTools.sourceExpression(
							reflaxe.rust.ast.RustAST.RustExpr.ERaw(RustRawCode.sourceAt("third();  ",
								RustSourceRawReason.RawTargetCodeInjection, rawPos)), expressionPos))],
						tail: null
					}
				})
			]
		};
		var printerEdgePlain = RustASTPrinter.printFile(printerEdgeFile);
		var printerEdgeMapped = RustASTPrinter.printFileWithSourceMap(printerEdgeFile, "src/printer_edges.rs");
		expect(printerEdgeMapped.code == printerEdgePlain,
			"origin sentinels changed empty-item or raw-semicolon printer decisions");
		expect(printerEdgePlain.indexOf("third();;") == -1,
			"raw expression semicolon normalization regressed");
		var edgeDocument = RustSourceMap.decode(RustSourceMap.encode([printerEdgeMapped], Sys.getCwd()));
		var edgeStart = printerEdgePlain.indexOf("third();");
		var edgeHit = RustSourceMap.lookup(edgeDocument,
			RustcGeneratedSpan.at("src/printer_edges.rs", edgeStart, edgeStart + "third".length), printerEdgePlain);
		expect(edgeHit != null, "nested raw-expression origin did not resolve");
		switch (edgeHit.origin) {
			case MappedHaxeSource(source):
				expect(source.startByte == Context.getPosInfos(rawPos).min,
					"lookup did not prefer the structurally deeper raw origin when generated spans tied");
			case MappedCompilerGenerated(_): throw "raw source expression resolved as compiler-generated";
		}

		var functionItem = RustOriginTools.sourceItem(reflaxe.rust.ast.RustAST.RustItem.RFn({
			name: "mapped",
			isPub: false,
			generics: reflaxe.rust.ast.RustAST.RustGenericParameters.empty(),
			args: [],
			ret: reflaxe.rust.ast.RustAST.RustType.RI32,
			body: {
				stmts: [
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("borrow_alias", false, null,
						reflaxe.rust.ast.RustAST.RustExpr.ECall(RustOriginTools.sourceExpression(
							reflaxe.rust.ast.RustAST.RustExpr.EField(local("owner"), RustMember.plain("borrow")), expressionPos), [])), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.ECall(local("consume"), [local("borrow_alias")])), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.ECall(local("consume"), [
							reflaxe.rust.ast.RustAST.RustExpr.ECall(reflaxe.rust.ast.RustAST.RustExpr.EField(
								RustOriginTools.sourceExpression(reflaxe.rust.ast.RustAST.RustExpr.ELitString("payload"), expressionPos),
								RustMember.plain("clone")), [])
						])), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("staged", false,
						reflaxe.rust.ast.RustAST.RustType.RI32, null), statementPos),
					RustOriginTools.generatedStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.EAssign(RustOriginTools.sourceExpression(local("staged"), expressionPos),
							reflaxe.rust.ast.RustAST.RustExpr.ELitInt(7))),
						RustGeneratedOriginReason.LoweringScaffolding),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("mutated", false, null,
						reflaxe.rust.ast.RustAST.RustExpr.ELitInt(0)), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("borrowed_mut", false,
						reflaxe.rust.ast.RustAST.RustType.RI32, reflaxe.rust.ast.RustAST.RustExpr.ELitInt(1)), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.ECall(local("touch_mut"), [
							reflaxe.rust.ast.RustAST.RustExpr.EUnary("&mut ",
								RustOriginTools.sourceExpression(local("borrowed_mut"), expressionPos))
						])), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.EAssign(RustOriginTools.sourceExpression(local("mutated"), expressionPos),
							local("staged"))), statementPos)
				],
				tail: RustOriginTools.sourceExpression(local("mutated"), expressionPos)
			}
		}), itemPos);
		var rawItem = RustOriginTools.sourceItem(reflaxe.rust.ast.RustAST.RustItem.RRaw(
			RustRawCode.metadataAt("first();  \n\n\nsecond(); \t", reflaxe.rust.ast.RustAST.RustMetadataRawReason.RawTraitImplementation, rawPos)), rawPos);
		var generatedItem = RustOriginTools.generatedItem(reflaxe.rust.ast.RustAST.RustItem.RComment(
			RustComment.line("generated source-map marker")), RustGeneratedOriginReason.GeneratedFileMarker);
		var input:RustFile = {items: [generatedItem, functionItem, rawItem]};
		var transformed = RustASTTransformer.transform(input, context());
		var plain = RustASTPrinter.printFile(transformed);
		expect(plain.indexOf("let staged: i32 = 7;") >= 0,
			"statement cleanup did not preserve a source-wrapped declaration");
		expect(plain.indexOf("let borrow_alias") == -1 && plain.indexOf("consume(owner.borrow());") >= 0,
			"borrow tightening did not preserve a source-wrapped consumer");
		expect(plain.indexOf("\"payload\".clone()") == -1,
			"clone elision did not preserve a source-wrapped call");
		expect(plain.indexOf("let mut mutated = 0;") >= 0,
			"mutation inference did not preserve a source-wrapped declaration");
		expect(plain.indexOf("let mut borrowed_mut: i32 = 1;") >= 0,
			"mutation inference did not see an origin-wrapped mutable-borrow target");
		expect(plain.indexOf("first();\n\nsecond();") >= 0,
			"normalization did not preserve a source-wrapped raw item");

		var printed = RustASTPrinter.printFileWithSourceMap(transformed, "src/contract.rs");
		expect(printed.code == plain, "source-map recording changed Rust printer bytes");
		var encodedFirst = RustSourceMap.encode([printed], Sys.getCwd());
		var encodedSecond = RustSourceMap.encode([printed], Sys.getCwd());
		expect(encodedFirst == encodedSecond, "source-map encoding is not deterministic");
		var normalizedRoot = haxe.io.Path.normalize(Sys.getCwd()).split("\\").join("/");
		expect(encodedFirst.indexOf(normalizedRoot) == -1, "source map leaked the absolute project root");

		var decoded = RustSourceMap.decode(encodedFirst);
		var stagedStart = plain.indexOf("let staged");
		var stagedHit = RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", stagedStart, stagedStart + "let staged".length), plain);
		expect(stagedHit != null, "exact generated span did not resolve");
		expect(stagedHit.nodeKind == RustSourceMapNodeKind.Statement, "lookup did not select the most precise statement mapping");
		switch (stagedHit.origin) {
			case MappedHaxeSource(source):
				expect(source.startByte == Context.getPosInfos(statementPos).min,
					"cleanup changed the original Haxe statement byte range");
				expect(source.file.indexOf("RustSourceMapContract.hx") >= 0,
					"source identity no longer points at the contract file");
			case MappedCompilerGenerated(_):
				throw "source statement was mislabeled compiler-generated";
		}

		var markerStart = plain.indexOf("// generated source-map marker");
		var markerHit = RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", markerStart, markerStart + 2), plain);
		expect(markerHit != null, "compiler-generated item mapping is missing");
		switch (markerHit.origin) {
			case MappedCompilerGenerated(reason):
				expect(reason == RustGeneratedOriginReason.GeneratedFileMarker,
					"compiler-generated reason changed during printing");
			case MappedHaxeSource(_):
				throw "generated marker was mislabeled Haxe source";
		}

		expect(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("contract.rs", stagedStart, stagedStart + 1), plain) == null,
			"lookup guessed a generated file from its basename");
		expect(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", stagedStart, stagedStart + 1), plain + " ") == null,
			"lookup accepted content that no longer matches the mapped Rust file");

		var sourceFile = switch (stagedHit.origin) {
			case MappedHaxeSource(source): source.file;
			case MappedCompilerGenerated(_): "";
		};
		expectThrows(() -> RustSourceMap.decode(encodedFirst.split(sourceFile).join("/private/source/Main.hx")),
			"decoder accepted a machine-local absolute source path");
		expectThrows(() -> RustSourceMap.decode(encodedFirst.split(sourceFile).join("safe/../" + sourceFile)),
			"decoder normalized a traversing source path instead of rejecting it");
		expectThrows(() -> RustSourceMap.decode(encodedFirst.split("generated-file-marker").join("invented-reason")),
			"decoder accepted an unknown compiler-generated reason");
		Sys.print(encodedFirst);
	}

	/** Proves that policy traversal cannot hide a forbidden path below all three origin wrappers. */
	public static function rejectWrappedHxrt():Void {
		var pos = sourcePosition("SOURCE_MAP_EXPRESSION_ORIGIN");
		var hxrt = reflaxe.rust.ast.RustAST.RustExpr.EPath(RustPath.relative([
			RustPathSegment.plain("hxrt"),
			RustPathSegment.plain("exception"),
			RustPathSegment.plain("throw")
		]));
		var file:RustFile = {
			items: [RustOriginTools.sourceItem(reflaxe.rust.ast.RustAST.RustItem.RFn({
				name: "forbidden",
				isPub: false,
				generics: reflaxe.rust.ast.RustAST.RustGenericParameters.empty(),
				args: [],
				ret: reflaxe.rust.ast.RustAST.RustType.RUnit,
				body: {
					stmts: [RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						RustOriginTools.sourceExpression(reflaxe.rust.ast.RustAST.RustExpr.ECall(hxrt, []), pos)), pos)],
					tail: null
				}
			}), pos)]
		};
		RustASTTransformer.transform(file, context(true));
	}
}
#end
