#if macro
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.RustProfile;
import reflaxe.rust.RustSourceMap;
import reflaxe.rust.RustSourceMap.RustMappedOrigin;
import reflaxe.rust.RustSourceMap.RustPrintedSourceFile;
import reflaxe.rust.RustSourceMap.RustPrintedSourceMapping;
import reflaxe.rust.RustSourceMap.RustSourceMapNodeKind;
import reflaxe.rust.RustSourceMap.RustcGeneratedSpan;
import reflaxe.rust.ast.RustAST.RustAttribute;
import reflaxe.rust.ast.RustAST.RustAttributedItem;
import reflaxe.rust.ast.RustAST.RustComment;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustGeneratedOriginReason;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustOrigin;
import reflaxe.rust.ast.RustAST.RustOriginTools;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustRawCode;
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

	static function replaceExactlyOnce(value:String, needle:String, replacement:String):String {
		var start = value.indexOf(needle);
		expect(start >= 0, 'source-map mutation target was missing: $needle in $value');
		expect(value.indexOf(needle, start + needle.length) < 0,
			'source-map mutation target was not unique: $needle');
		return value.substr(0, start) + replacement + value.substr(start + needle.length);
	}

	static function expectSourceOrigin(mapping:reflaxe.rust.RustSourceMap.RustSourceMapping, pos:Position,
			message:String):Void {
		expect(mapping != null, message + " (mapping was missing)");
		switch (mapping.origin) {
			case MappedHaxeSource(source):
				expect(source.startByte == Context.getPosInfos(pos).min, message);
			case MappedCompilerGenerated(_):
				throw message + " (resolved as compiler-generated)";
		}
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
		expect(reflaxe.rust.ast.RustPathAnalysis.statementContainsLocalSpelling(
			RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("value", false, null,
				reflaxe.rust.ast.RustAST.RustExpr.ELitInt(1)), statementPos), "value"),
			"whole-scrutinee shadow safety gate missed an origin-wrapped local declaration");
		expect(reflaxe.rust.ast.RustPathAnalysis.statementContainsLocalSpelling(
			reflaxe.rust.ast.RustAST.RustStmt.RSemi(reflaxe.rust.ast.RustAST.RustExpr.ERaw(
				RustRawCode.targetCodeInjectionAt("observe(value)", rawPos))), "value"),
			"whole-scrutinee safety gate treated opaque executable Rust as binding-free");
		expectThrows(() -> RustRawCode.targetCodeInjectionAt("invalid", null),
			"raw source factory accepted a null Haxe position");
		expectThrows(() -> RustRawCode.traitImplementationAt("invalid", null),
			"raw metadata factory accepted a null Haxe position");
		expectThrows(() -> RustRawCode.targetCodeInjectionAt(null, rawPos),
			"raw source factory accepted null printable bytes");
		expectThrows(() -> RustRawCode.traitImplementationAt(null, rawPos),
			"raw metadata factory accepted null printable bytes");
		var validRaw = RustRawCode.targetCodeInjectionAt("valid", rawPos);
		expectThrows(() -> validRaw.withCode(null), "raw-code transformation accepted null printable bytes");
		expect(RustRawCode.traitImplementationAt("valid", rawPos).authorityId() == "metadata-owned",
			"valid metadata raw fragment failed validation");
		expect(validRaw.authorityId() == "source-owned", "valid source raw fragment failed validation");
		var testAttribute = RustAttribute.bare(RustPath.relative([RustPathSegment.plain("test")]));
		expectThrows(() -> RustAttributedItem.of([testAttribute], RustOriginTools.sourceItem(
			reflaxe.rust.ast.RustAST.RustItem.RComment(RustComment.line("not a declaration")), itemPos)),
			"an origin wrapper disguised an invalid outer-attribute target");
		expectThrows(() -> RustOriginTools.generatedItem(
			reflaxe.rust.ast.RustAST.RustItem.RComment(RustComment.line("unknown reason")), cast "invented-reason"),
			"generated-origin factory accepted a value outside the closed reason vocabulary");
		expectThrows(() -> RustOriginTools.generatedItem(
			reflaxe.rust.ast.RustAST.RustItem.RComment(RustComment.line("null reason")), cast null),
			"generated-origin factory accepted a null compiler-generated reason");

		var printerEdgeFile:RustFile = {
			items: [
				RustOriginTools.generatedItem(reflaxe.rust.ast.RustAST.RustItem.RComment(
					RustComment.line("compiler-generated typed")),
					RustGeneratedOriginReason.UnsupportedFallback),
				reflaxe.rust.ast.RustAST.RustItem.RFn({
					name: "printer_edges",
					isPub: false,
					generics: reflaxe.rust.ast.RustAST.RustGenericParameters.empty(),
					args: [],
					ret: reflaxe.rust.ast.RustAST.RustType.RUnit,
					body: {
						stmts: [
							reflaxe.rust.ast.RustAST.RustStmt.RSemi(RustOriginTools.sourceExpression(
								reflaxe.rust.ast.RustAST.RustExpr.ERaw(RustRawCode.targetCodeInjectionAt("third();  ", rawPos)), expressionPos)),
							reflaxe.rust.ast.RustAST.RustStmt.RSemi(reflaxe.rust.ast.RustAST.RustExpr.ERaw(
								RustRawCode.traitImplementationAt("fourth();", rawPos)))
						],
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
		var generatedTypedStart = printerEdgePlain.indexOf("// compiler-generated typed");
		var generatedTypedHit = RustSourceMap.lookup(edgeDocument,
			RustcGeneratedSpan.at("src/printer_edges.rs", generatedTypedStart, generatedTypedStart + 2), printerEdgePlain);
		expect(generatedTypedHit != null, "valid compiler-generated typed origin did not survive encoding");
		switch (generatedTypedHit.origin) {
			case MappedCompilerGenerated(reason):
				expect(reason == RustGeneratedOriginReason.UnsupportedFallback,
					"compiler-generated typed origin changed its closed reason while encoding");
			case MappedHaxeSource(_): throw "compiler-generated typed origin resolved as Haxe source";
		}
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
		var metadataStart = printerEdgePlain.indexOf("fourth();");
		expectSourceOrigin(RustSourceMap.lookup(edgeDocument,
			RustcGeneratedSpan.at("src/printer_edges.rs", metadataStart, metadataStart + "fourth".length), printerEdgePlain),
			rawPos, "valid metadata raw factory did not survive encoding");

		var functionItem = RustOriginTools.sourceItem(reflaxe.rust.ast.RustAST.RustItem.RFn({
			name: "mapped",
			isPub: false,
			generics: reflaxe.rust.ast.RustAST.RustGenericParameters.empty(),
			args: [],
			ret: reflaxe.rust.ast.RustAST.RustType.RI32,
			body: {
				stmts: [
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("borrow_alias", false, null,
						RustOriginTools.sourceExpression(reflaxe.rust.ast.RustAST.RustExpr.ECall(RustOriginTools.sourceExpression(
							reflaxe.rust.ast.RustAST.RustExpr.EField(RustOriginTools.sourceExpression(local("owner"), itemPos),
								RustMember.plain("borrow")), expressionPos), []), rawPos)), statementPos),
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
						RustOriginTools.sourceExpression(reflaxe.rust.ast.RustAST.RustExpr.EAssign(local("staged"),
							reflaxe.rust.ast.RustAST.RustExpr.ELitInt(7)), expressionPos)),
						RustGeneratedOriginReason.LoweringScaffolding),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("block_staged", false,
						reflaxe.rust.ast.RustAST.RustType.RI32, null), statementPos),
					RustOriginTools.generatedStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						RustOriginTools.sourceExpression(reflaxe.rust.ast.RustAST.RustExpr.EBlock({
							stmts: [
								RustOriginTools.generatedStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("before", false, null,
									reflaxe.rust.ast.RustAST.RustExpr.ELitInt(1)), RustGeneratedOriginReason.LoweringScaffolding),
								RustOriginTools.generatedStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
									RustOriginTools.sourceExpression(reflaxe.rust.ast.RustAST.RustExpr.EAssign(local("block_staged"),
										reflaxe.rust.ast.RustAST.RustExpr.ELitInt(9)), expressionPos)),
									RustGeneratedOriginReason.LoweringScaffolding)
							],
							tail: null
							}), rawPos)), RustGeneratedOriginReason.LoweringScaffolding),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.ECall(local("inspect"), [
							reflaxe.rust.ast.RustAST.RustExpr.EUnary("&", local("block_staged"))
						])), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("tail_result", false, null,
						reflaxe.rust.ast.RustAST.RustExpr.EBlock({
							stmts: [reflaxe.rust.ast.RustAST.RustStmt.RLet("tail_borrow", false, null,
								RustOriginTools.sourceExpression(reflaxe.rust.ast.RustAST.RustExpr.ECall(RustOriginTools.sourceExpression(
									reflaxe.rust.ast.RustAST.RustExpr.EField(RustOriginTools.sourceExpression(
										reflaxe.rust.ast.RustAST.RustExpr.EField(local("holder"), RustMember.plain("storage")), itemPos),
										RustMember.plain("borrow")), expressionPos), []), rawPos))],
							tail: reflaxe.rust.ast.RustAST.RustExpr.ECall(local("consume"), [local("tail_borrow")])
						})), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RLet("guard", false, null,
						reflaxe.rust.ast.RustAST.RustExpr.ECall(RustOriginTools.sourceExpression(
							reflaxe.rust.ast.RustAST.RustExpr.EField(local("cell"), RustMember.plain("borrow_mut")), rawPos), [])),
						statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.ECall(local("inspect"), [
							reflaxe.rust.ast.RustAST.RustExpr.EUnary("&", local("guard"))
						])), statementPos),
					RustOriginTools.sourceStatement(reflaxe.rust.ast.RustAST.RustStmt.RSemi(
						reflaxe.rust.ast.RustAST.RustExpr.ECall(local("inspect"), [
							reflaxe.rust.ast.RustAST.RustExpr.EUnary("&", local("guard"))
						])), statementPos),
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
			RustRawCode.traitImplementationAt("first();  \n\n\nsecond(); \t", rawPos)), rawPos);
		var generatedItem = RustOriginTools.generatedItem(reflaxe.rust.ast.RustAST.RustItem.RComment(
			RustComment.line("generated source-map marker")), RustGeneratedOriginReason.GeneratedFileMarker);
		var input:RustFile = {items: [generatedItem, functionItem, rawItem]};
		var transformed = RustASTTransformer.transform(input, context());
		var plain = RustASTPrinter.printFile(transformed);
		expect(plain.indexOf("let staged: i32 = 7;") >= 0,
			"statement cleanup did not preserve a source-wrapped declaration");
		expect(plain.indexOf("let block_staged: i32 = {") >= 0,
			"statement cleanup did not collapse a source-wrapped block assignment");
		expect(plain.indexOf("let borrow_alias") == -1 && plain.indexOf("consume(owner.borrow());") >= 0,
			"borrow tightening did not preserve a source-wrapped consumer");
		expect(plain.indexOf("holder.storage.borrow()") >= 0 && plain.indexOf("let tail_borrow") == -1,
			"borrow tightening did not inline a source-wrapped block-tail alias");
		expect(plain.indexOf("let mut guard") >= 0,
			"mutation inference did not recognize an origin around a borrow_mut callee");
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
		var stagedValueStart = plain.indexOf("7;", stagedStart);
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", stagedValueStart, stagedValueStart + 1), plain), expressionPos,
			"cleanup discarded the assignment expression origin moved into a let initializer");
		var blockStagedStart = plain.indexOf("let block_staged");
		var blockValueStart = plain.indexOf("9", blockStagedStart);
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", blockValueStart, blockValueStart + 1), plain), expressionPos,
			"block-assignment collapse discarded the final assignment expression origin");
		var immediateBorrowStart = plain.indexOf("owner.borrow");
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", immediateBorrowStart, immediateBorrowStart + "owner".length), plain),
			itemPos, "immediate borrow-alias inlining discarded receiver provenance");
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", immediateBorrowStart, immediateBorrowStart + "owner.borrow".length), plain),
			expressionPos, "immediate borrow-alias inlining discarded initializer provenance");
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", immediateBorrowStart, immediateBorrowStart + "owner.borrow()".length), plain),
			rawPos, "immediate borrow-alias inlining discarded complete-call provenance");
		var tailBorrowStart = plain.indexOf("holder.storage.borrow");
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", tailBorrowStart, tailBorrowStart + "holder.storage".length), plain),
			itemPos, "block-tail borrow-alias inlining discarded receiver provenance");
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", tailBorrowStart, tailBorrowStart + "holder.storage.borrow".length), plain),
			expressionPos, "block-tail borrow-alias inlining discarded callee provenance");
		expectSourceOrigin(RustSourceMap.lookup(decoded,
			RustcGeneratedSpan.at("src/contract.rs", tailBorrowStart, tailBorrowStart + "holder.storage.borrow()".length), plain),
			rawPos, "block-tail borrow-alias inlining discarded complete-call provenance");

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

		var coordinateCode = "é\nx\n";
		var coordinatePrinted = RustPrintedSourceFile.of("src/coordinate.rs", coordinateCode, [
			RustPrintedSourceMapping.at(RustSourceMapNodeKind.Expression, RustOrigin.OriginHaxeSource(expressionPos), 0, 0, 2),
			RustPrintedSourceMapping.at(RustSourceMapNodeKind.Expression, RustOrigin.OriginHaxeSource(expressionPos), 0, 0, 4),
			RustPrintedSourceMapping.at(RustSourceMapNodeKind.Expression, RustOrigin.OriginHaxeSource(expressionPos), 0, 3, 5)
		]);
		var coordinateEncoded = RustSourceMap.encode([coordinatePrinted], Sys.getCwd());
		function expectCoordinateMutationRejected(needle:String, replacement:String, startByte:Int, endByte:Int,
				message:String):Void {
			var mutated = RustSourceMap.decode(replaceExactlyOnce(coordinateEncoded, needle, replacement));
			expect(RustSourceMap.lookup(mutated,
				RustcGeneratedSpan.at("src/coordinate.rs", startByte, endByte), coordinateCode) == null, message);
		}
		expectCoordinateMutationRejected(
			'"generated":{"endByte":2,"endColumn":3,"startLine":1,"startByte":0,"endLine":1,"startColumn":1}',
			'"generated":{"endByte":2,"endColumn":2,"startLine":1,"startByte":0,"endLine":1,"startColumn":1}',
			0, 1, "lookup accepted a UTF-8 end column that contradicts the exact generated bytes");
		expectCoordinateMutationRejected(
			'"generated":{"endByte":4,"endColumn":2,"startLine":1,"startByte":0,"endLine":2,"startColumn":1}',
			'"generated":{"endByte":4,"endColumn":2,"startLine":2,"startByte":0,"endLine":2,"startColumn":1}',
			2, 4, "lookup accepted a start line that contradicts the exact generated bytes");
		expectCoordinateMutationRejected(
			'"generated":{"endByte":4,"endColumn":2,"startLine":1,"startByte":0,"endLine":2,"startColumn":1}',
			'"generated":{"endByte":4,"endColumn":2,"startLine":1,"startByte":0,"endLine":3,"startColumn":1}',
			2, 4, "lookup accepted an end line that contradicts the exact generated bytes");
		expectCoordinateMutationRejected('"lineCount":3', '"lineCount":99', 0, 1,
			"lookup accepted a line count that contradicts the exact generated bytes");

		function assertManyChunkAggregation(chunkCount:Int):Void {
			var manyChunks:Array<RustPrintedSourceFile> = [];
			for (_ in 0...chunkCount) {
				manyChunks.push(RustPrintedSourceFile.of("src/many.rs", "x", [
					RustPrintedSourceMapping.at(RustSourceMapNodeKind.Expression,
						RustOrigin.OriginHaxeSource(expressionPos), 0, 0, 1)
				]));
			}
			var manyDocument = RustSourceMap.decode(RustSourceMap.encode(manyChunks, Sys.getCwd()));
			var manyFile = manyDocument.fileAt(0);
			var expectedManyCode = [for (_ in 0...chunkCount) "x"].join("\n\n");
			expect(manyFile.byteLength == haxe.io.Bytes.ofString(expectedManyCode).length,
				'same-file $chunkCount-chunk aggregation changed exact output byte length');
			expect(manyFile.contentHash == haxe.crypto.Sha256.make(haxe.io.Bytes.ofString(expectedManyCode)).toHex(),
				'same-file $chunkCount-chunk aggregation changed exact output content hash');
			expect(manyFile.mappingCount == chunkCount,
				'same-file $chunkCount-chunk aggregation changed mapping count or deduplication');
			expect(manyFile.mappingAt(0).generated.startByte == 0,
				'same-file $chunkCount-chunk aggregation shifted the first mapping');
			var last = manyFile.mappingAt(chunkCount - 1).generated;
			expect(last.startByte == (chunkCount - 1) * 3 && last.endByte == expectedManyCode.length,
				'same-file $chunkCount-chunk aggregation shifted the final mapping incorrectly');
		}
		assertManyChunkAggregation(1000);
		assertManyChunkAggregation(10000);
		Sys.print(encodedFirst);
	}

	/** Emits a minimal rustc-backed contract for every origin placement around `borrow_mut()`. */
	public static function printMutableGuardRegression():Void {
		var itemPos = sourcePosition("SOURCE_MAP_ITEM_ORIGIN");
		var statementPos = sourcePosition("SOURCE_MAP_STATEMENT_ORIGIN");
		var expressionPos = sourcePosition("SOURCE_MAP_EXPRESSION_ORIGIN");
		var statements:Array<reflaxe.rust.ast.RustAST.RustStmt> = [];
		function target(names:Array<String>) {
			return reflaxe.rust.ast.RustAST.RustExpr.EPath(RustPath.relative([
				for (name in names) RustPathSegment.plain(name)
			]));
		}
		var variants = ["call_origin", "callee_origin", "receiver_origin", "all_origins"];
		for (index in 0...variants.length) {
			var cellName = "cell_" + variants[index];
			var guardName = "guard_" + variants[index];
			statements.push(reflaxe.rust.ast.RustAST.RustStmt.RLet(cellName, false, null,
				reflaxe.rust.ast.RustAST.RustExpr.ECall(target(["std", "cell", "RefCell", "new"]), [
					reflaxe.rust.ast.RustAST.RustExpr.ELitInt(0)
				])));
			var receiver = index == 2 || index == 3 ? RustOriginTools.sourceExpression(local(cellName), itemPos) : local(cellName);
			var callee:reflaxe.rust.ast.RustAST.RustExpr = reflaxe.rust.ast.RustAST.RustExpr.EField(receiver,
				RustMember.plain("borrow_mut"));
			if (index == 1 || index == 3)
				callee = RustOriginTools.sourceExpression(callee, expressionPos);
			var call:reflaxe.rust.ast.RustAST.RustExpr = reflaxe.rust.ast.RustAST.RustExpr.ECall(callee, []);
			if (index == 0 || index == 3)
				call = RustOriginTools.sourceExpression(call, statementPos);
			statements.push(reflaxe.rust.ast.RustAST.RustStmt.RLet(guardName, false, null, call));
			statements.push(reflaxe.rust.ast.RustAST.RustStmt.RSemi(reflaxe.rust.ast.RustAST.RustExpr.EAssign(
				reflaxe.rust.ast.RustAST.RustExpr.EUnary("*", local(guardName)),
				reflaxe.rust.ast.RustAST.RustExpr.ELitInt(index + 1))));
			statements.push(reflaxe.rust.ast.RustAST.RustStmt.RSemi(reflaxe.rust.ast.RustAST.RustExpr.EMacroCall("assert_eq", [
				reflaxe.rust.ast.RustAST.RustExpr.EUnary("*", local(guardName)),
				reflaxe.rust.ast.RustAST.RustExpr.ELitInt(index + 1)
			])));
		}
		var file:RustFile = {
			items: [reflaxe.rust.ast.RustAST.RustItem.RFn({
				name: "main",
				isPub: false,
				generics: reflaxe.rust.ast.RustAST.RustGenericParameters.empty(),
				args: [],
				ret: reflaxe.rust.ast.RustAST.RustType.RUnit,
				body: {stmts: statements, tail: null}
			})]
		};
		Sys.print(RustASTPrinter.printFile(RustASTTransformer.transform(file, context())));
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
