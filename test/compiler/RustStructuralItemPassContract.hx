#if macro
import haxe.macro.Context;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.RustProfile;
import reflaxe.rust.ast.RustAST.RustAttribute;
import reflaxe.rust.ast.RustAST.RustAttributedItem;
import reflaxe.rust.ast.RustAST.RustCompilerRawReason;
import reflaxe.rust.ast.RustAST.RustConstantDeclaration;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustFunction;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustModuleDeclaration;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustRawCode;
import reflaxe.rust.ast.RustAST.RustStaticDeclaration;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustAST.RustTypeAliasDeclaration;
import reflaxe.rust.ast.RustAST.RustUseDeclaration;
import reflaxe.rust.ast.RustAST.RustVisibility;
import reflaxe.rust.ast.RustASTPrinter;
import reflaxe.rust.ast.RustASTTransformer;
import reflaxe.rust.compiler.RustBuildContext;

/**
	Production-pipeline contract for recursively structural Rust items.

	Why
	- Inline modules are independent item roots. A pass can handle top-level functions correctly while
	  silently skipping generated tests, compatibility modules, or future nested declarations.
	- Source-pattern checks do not prove that normalization and no-runtime policy actually reach the
	  newly typed attribute/use/module/constant/static/type-alias nodes.

	What
	- Runs the public `RustASTTransformer` over attributed functions nested in an attributed inline
	  module and observes borrow tightening, clone elision, mutation inference, statement cleanup,
	  and raw-fragment normalization.
	- Provides a separate expected-failure entry point with eight `hxrt` paths distributed across
	  outer/inner attributes, a use, const/static types and values, and a type alias.

	How
	- The JavaScript runner invokes both entry points through Haxe's macro hook. `run` must succeed
	  twice with exact pass/metric evidence; `rejectNestedHxrt` must fail twice through the real
	  `NoHxrtPass` diagnostic rather than a duplicated test-only scanner.
**/
class RustStructuralItemPassContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function path(names:Array<String>):RustPath {
		return RustPath.relative([for (name in names) RustPathSegment.plain(name)]);
	}

	static function local(name:String):RustExpr {
		return EPath(RustPath.single(name));
	}

	static function call(name:String, argument:RustExpr):RustExpr {
		return ECall(local(name), [argument]);
	}

	static function attributedFunction(name:String, statements:Array<RustStmt>):RustItem {
		return RAttributed(RustAttributedItem.of([
			RustAttribute.bare(path(["test"]))
		], RFn({
			name: name,
			isPub: false,
			generics: RustGenericParameters.empty(),
			args: [],
			ret: RUnit,
			body: {stmts: statements, tail: null}
		})));
	}

	static function context(noHxrt:Bool):CompilationContext {
		var profile = noHxrt ? RustProfile.Metal : RustProfile.Portable;
		var build = new RustBuildContext("structural_item_pass_contract", profile, false, false, false, false, false, noHxrt, []);
		var result = new CompilationContext(build, [], [], [], false, false, []);
		result.setCurrentModule("structural_item_pass_contract", Context.currentPos());
		return result;
	}

	static function findFunction(item:RustItem, name:String):Null<RustFunction> {
		return switch (item) {
			case RAttributed(value):
				findFunction(value.target, name);
			case RModule(declaration) if (declaration.isInline):
				var found:Null<RustFunction> = null;
				for (child in declaration) {
					found = findFunction(child, name);
					if (found != null)
						break;
				}
				found;
			case RFn(value) if (value.name == name):
				value;
			case _:
				null;
		};
	}

	static function findRaw(item:RustItem):Null<RustRawCode> {
		return switch (item) {
			case RAttributed(value):
				findRaw(value.target);
			case RModule(declaration) if (declaration.isInline):
				var found:Null<RustRawCode> = null;
				for (child in declaration) {
					found = findRaw(child);
					if (found != null)
						break;
				}
				found;
			case RRaw(value):
				value;
			case _:
				null;
		};
	}

	static function printFunction(file:RustFile, name:String):String {
		for (item in file.items) {
			var fn = findFunction(item, name);
			if (fn != null)
				return RustASTPrinter.printFile({items: [RFn(fn)]});
		}
		throw 'Missing transformed function `$name`';
	}

	static function hasMetric(metrics:Array<{id:String, count:Int}>, id:String):Bool {
		for (metric in metrics) {
			if (metric.id == id && metric.count > 0)
				return true;
		}
		return false;
	}

	public static function run():Void {
		var raw = RustRawCode.compilerGenerated("first();  \n\n\nsecond(); \t", RawUnsupportedFallback);
		var nestedItems:Array<RustItem> = [
			attributedFunction("borrow_nested", [
				RLet("alias", false, null, ECall(EField(local("owner"), RustMember.plain("borrow")), [])),
				RSemi(call("consume", local("alias")))
			]),
			attributedFunction("clone_nested", [
				RSemi(call("consume", ECall(EField(ELitString("payload"), RustMember.plain("clone")), [])))
			]),
			attributedFunction("mut_nested", [
				RLet("mutated", false, null, ELitInt(0)),
				RSemi(EAssign(local("mutated"), ELitInt(1))),
				RSemi(call("consume", local("mutated")))
			]),
			attributedFunction("cleanup_nested", [
				RLet("staged", false, RI32, null),
				RSemi(EAssign(local("staged"), ELitInt(7))),
				RSemi(call("consume", local("staged")))
			]),
			attributedFunction("lifecycle_nested", [
				RLet("_guard", false, null, ECall(local("acquire_guard"), []))
			]),
			RRaw(raw)
		];
		var input:RustFile = {
			items: [RAttributed(RustAttributedItem.of([
				RustAttribute.pathList(path(["cfg"]), [path(["test"])])
			], RModule(RustModuleDeclaration.inlineModule(VPrivate, "outer", nestedItems))))]
		};

		var compilation = context(false);
		var transformed = RustASTTransformer.transform(input, compilation);
		expect(compilation.executedPasses.join(",")
			== "normalize,statement_cleanup,mut_inference,clone_elision,borrow_scope_tightening,metal_restrictions",
			"the public portable transformer pass order changed or stopped before recursive item handling");

		var borrowOutput = printFunction(transformed, "borrow_nested");
		expect(borrowOutput.indexOf("let alias") == -1 && borrowOutput.indexOf("consume(owner.borrow());") != -1,
			"borrow-scope tightening did not reach an attributed function inside an inline module");
		var cloneOutput = printFunction(transformed, "clone_nested");
		expect(cloneOutput.indexOf(".clone()") == -1 && cloneOutput.indexOf('consume("payload");') != -1,
			"clone elision did not reach an attributed function inside an inline module");
		var mutOutput = printFunction(transformed, "mut_nested");
		expect(mutOutput.indexOf("let mut mutated = 0;") != -1,
			"mutation inference did not reach an attributed function inside an inline module");
		var cleanupOutput = printFunction(transformed, "cleanup_nested");
		expect(cleanupOutput.indexOf("let staged: i32 = 7;") != -1 && cleanupOutput.indexOf("staged = 7") == -1,
			"statement cleanup did not reach an attributed function inside an inline module");
		var lifecycleOutput = printFunction(transformed, "lifecycle_nested");
		expect(lifecycleOutput.indexOf("let _guard = acquire_guard();") != -1,
			"statement cleanup changed an intentional underscore binding into an immediate-drop wildcard");

		var transformedOutput = RustASTPrinter.printFile(transformed);
		expect(transformedOutput.indexOf("#[cfg(test)]\nmod outer {") != -1,
			"outer attributes detached from their recursively transformed module target");
		expect(transformedOutput.indexOf("    #[test]\n    fn borrow_nested()") != -1,
			"function attributes detached while rebuilding inline module children");
		var normalizedRaw:Null<RustRawCode> = null;
		for (item in transformed.items) {
			normalizedRaw = findRaw(item);
			if (normalizedRaw != null)
				break;
		}
		expect(normalizedRaw != null && normalizedRaw.code == "first();\n\nsecond();",
			"normalization did not recurse into an attributed inline module raw child");
		expect(normalizedRaw != null && normalizedRaw.authorityId() == raw.authorityId() && normalizedRaw.reasonId() == raw.reasonId(),
			"nested normalization changed raw authority or reason provenance");

		var metrics = compilation.optimizerAppliedSnapshot();
		expect(hasMetric(metrics, "clone_elision.applied.literal_clone"),
			"nested clone elision did not record its production optimizer metric");
		expect(hasMetric(metrics, "borrow_scope_tightening.applied.immediate_alias_inline"),
			"nested borrow tightening did not record its production optimizer metric");
	}

	public static function rejectNestedHxrt():Void {
		var hxrtType = function(name:String):RustType {
			return RNamed(path(["hxrt", name]));
		};
		var nested:RustItem = RAttributed(RustAttributedItem.of([
			RustAttribute.pathList(path(["derive"]), [path(["hxrt", "Marker"])])
		], RModule(RustModuleDeclaration.inlineModule(VPrivate, "outer", [
			RModule(RustModuleDeclaration.inlineModule(VPrivate, "inner", [
				RInnerAttribute(RustAttribute.bare(path(["hxrt", "inner"]))),
				RUse(RustUseDeclaration.exact(VPrivate, path(["hxrt", "api"]))),
				RConst(RustConstantDeclaration.named(VPrivate, "VALUE", hxrtType("ConstType"), EPath(path(["hxrt", "const_value"])))),
				RStatic(RustStaticDeclaration.named(VPrivate, "STATE", hxrtType("StaticType"), EPath(path(["hxrt", "static_value"])))),
				RTypeAlias(RustTypeAliasDeclaration.named(VPrivate, "Alias", RustGenericParameters.empty(), hxrtType("AliasType")))
			]))
		]))));
		RustASTTransformer.transform({items: [nested]}, context(true));
		throw "NoHxrtPass accepted runtime paths hidden inside structural nested items";
	}
}
#end
