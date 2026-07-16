#if macro
import haxe.macro.Context;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.RustProfile;
import reflaxe.rust.ast.RustAST.RustAssociatedFunction;
import reflaxe.rust.ast.RustAST.RustAssociatedItem;
import reflaxe.rust.ast.RustAST.RustAssociatedTypeDeclaration;
import reflaxe.rust.ast.RustAST.RustAttribute;
import reflaxe.rust.ast.RustAST.RustAttributedItem;
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustFunctionParameter;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustImpl;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustModuleDeclaration;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustRawCode;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustTraitDeclaration;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustAST.RustWhereClause;
import reflaxe.rust.ast.RustAST.RustWherePredicate;
import reflaxe.rust.ast.RustASTPrinter;
import reflaxe.rust.ast.RustASTTransformer;
import reflaxe.rust.compiler.RustBuildContext;

/**
	Production-pass contract for structural trait and impl bodies.

	Why / What / How
	- Trait defaults and impl methods are nested executable roots just like functions inside modules.
	  This macro runs the real transformer and proves normalization, cleanup, mutation, clone, and
	  borrow passes rebuild those bodies without dropping declaration structure.
	- A separate no-hxrt entry point distributes runtime paths through trait/impl headers, where
	  clauses, signatures, associated values, and the admitted raw metadata body. The policy must count
	  all eight paths twice with byte-identical diagnostics.
**/
class RustStructuralTraitImplPassContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function path(names:Array<String>):RustPath {
		return RustPath.relative([for (name in names) RustPathSegment.plain(name)]);
	}

	static function named(name:String):RustType {
		return RNamed(path([name]));
	}

	static function local(name:String):RustExpr {
		return EPath(path([name]));
	}

	static function call(name:String, argument:RustExpr):RustExpr {
		return ECall(local(name), [argument]);
	}

	static function method(name:String, statements:Array<RustStmt>):RustAssociatedItem {
		return AssocFunction(RustAssociatedFunction.declaration(VPrivate, name, false, RustGenericParameters.empty(), null, [], null,
			RustWhereClause.empty(), {stmts: statements, tail: null}));
	}

	static function context(noHxrt:Bool):CompilationContext {
		var profile = noHxrt ? RustProfile.Metal : RustProfile.Portable;
		var build = new RustBuildContext("structural_trait_impl_pass_contract", profile, false, false, false, false, false, noHxrt, []);
		var result = new CompilationContext(build, [], [], [], false, false, []);
		result.setCurrentModule("structural_trait_impl_pass_contract", Context.currentPos());
		return result;
	}

	static function findFunction(item:RustItem, name:String):Null<RustAssociatedFunction> {
		return switch (item) {
			case RAttributed(value): findFunction(value.target, name);
			case RModule(declaration) if (declaration.isInline):
				var found:Null<RustAssociatedFunction> = null;
				for (child in declaration) {
					found = findFunction(child, name);
					if (found != null)
						break;
				}
				found;
			case RTrait(declaration): findAssociatedFunction(declaration.iterator(), name);
			case RImpl(declaration): findAssociatedFunction(declaration.iterator(), name);
			case _: null;
		};
	}

	static function findAssociatedFunction(items:Iterator<RustAssociatedItem>, name:String):Null<RustAssociatedFunction> {
		for (item in items) {
			switch (item) {
				case AssocFunction(method) if (method.name.name == name):
					return method;
				case _:
			}
		}
		return null;
	}

	static function findRaw(item:RustItem):Null<RustRawCode> {
		return switch (item) {
			case RAttributed(value): findRaw(value.target);
			case RModule(declaration) if (declaration.isInline):
				var found:Null<RustRawCode> = null;
				for (child in declaration) {
					found = findRaw(child);
					if (found != null)
						break;
				}
				found;
			case RImpl(declaration):
				var found:Null<RustRawCode> = null;
				for (associated in declaration) {
					switch (associated) {
						case AssocRaw(raw): found = raw;
						case _:
					}
					if (found != null)
						break;
				}
				found;
			case _: null;
		};
	}

	static function printFunction(file:RustFile, name:String):String {
		for (item in file.items) {
			var method = findFunction(item, name);
			if (method != null)
				return RustASTPrinter.printFile(file);
		}
		throw 'Missing transformed associated function `$name`';
	}

	public static function run():Void {
		var raw = RustRawCode.metadataAt("first();  \n\n\nsecond(); \t", RawTraitImplementation, Context.currentPos());
		var associated:Array<RustAssociatedItem> = [
			method("borrow_nested", [
				RLet("alias", false, null, ECall(EField(local("owner"), reflaxe.rust.ast.RustAST.RustMember.plain("borrow")), [])),
				RSemi(call("consume", local("alias")))
			]),
			method("clone_nested", [
				RSemi(call("consume", ECall(EField(ELitString("payload"), reflaxe.rust.ast.RustAST.RustMember.plain("clone")), [])))
			]),
			method("mut_nested", [
				RLet("mutated", false, null, ELitInt(0)),
				RSemi(EAssign(local("mutated"), ELitInt(1))),
				RSemi(call("consume", local("mutated")))
			]),
			method("cleanup_nested", [
				RLet("staged", false, RI32, null),
				RSemi(EAssign(local("staged"), ELitInt(7))),
				RSemi(call("consume", local("staged")))
			]),
			AssocRaw(raw)
		];
		var nested = RAttributed(RustAttributedItem.of([
			RustAttribute.pathList(path(["cfg"]), [path(["test"])])
		], RModule(RustModuleDeclaration.inlineModule(VPrivate, "outer", [
			RImpl(RustImpl.traitImplementation(RustGenericParameters.empty(), path(["Marker"]), named("Target"), RustWhereClause.empty(),
				associated))
		]))));
		var compilation = context(false);
		var transformed = RustASTTransformer.transform({items: [nested]}, compilation);
		expect(compilation.executedPasses.join(",")
			== "normalize,statement_cleanup,mut_inference,clone_elision,borrow_scope_tightening,metal_restrictions",
			"the production transformer stopped before structural trait/impl recursion");

		var borrowOutput = printFunction(transformed, "borrow_nested");
		expect(borrowOutput.indexOf("let alias") == -1 && borrowOutput.indexOf("consume(owner.borrow());") != -1,
			"borrow tightening did not reach a structural impl method");
		var cloneOutput = printFunction(transformed, "clone_nested");
		expect(cloneOutput.indexOf(".clone()") == -1,
			"clone elision did not reach a structural impl method");
		var mutOutput = printFunction(transformed, "mut_nested");
		expect(mutOutput.indexOf("let mut mutated = 0;") != -1,
			"mutation inference did not reach a structural impl method");
		var cleanupOutput = printFunction(transformed, "cleanup_nested");
		expect(cleanupOutput.indexOf("let staged: i32 = 7;") != -1,
			"statement cleanup did not reach a structural impl method");

		var normalized:Null<RustRawCode> = null;
		for (item in transformed.items) {
			normalized = findRaw(item);
			if (normalized != null)
				break;
		}
		expect(normalized != null && normalized.code == "first();\n\nsecond();",
			"normalization did not reach a raw metadata body inside a structural impl");
		expect(normalized != null && normalized.authorityId() == raw.authorityId() && normalized.reasonId() == raw.reasonId(),
			"associated-body normalization changed metadata authority");
	}

	public static function rejectNestedHxrt():Void {
		var hxrtType = name -> RNamed(path(["hxrt", name]));
		var impl = RustImpl.traitImplementation(RustGenericParameters.empty(), path(["hxrt", "Trait"]), hxrtType("Target"), RustWhereClause.of([
			RustWherePredicate.typeBounds(named("T"), [GenericTraitBound(path(["hxrt", "ImplWhere"]), TraitBoundRequired)])
		]), [
			AssocRaw(RustRawCode.metadataAt("fn raw() { hxrt::raw(); }", RawTraitImplementation, Context.currentPos()))
		]);
		var trait = RustTraitDeclaration.named(VPrivate, "Surface", RustGenericParameters.empty(), [
			GenericTraitBound(path(["hxrt", "Super"]), TraitBoundRequired)
		], RustWhereClause.of([
			RustWherePredicate.typeBounds(named("T"), [GenericTraitBound(path(["hxrt", "TraitWhere"]), TraitBoundRequired)])
		]), [
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "inspect", false, RustGenericParameters.empty(), ReceiverBorrowed(false, null), [
				RustFunctionParameter.named("value", hxrtType("Parameter"))
			], null, RustWhereClause.empty(), null)),
			AssocType(RustAssociatedTypeDeclaration.named("Output", RustGenericParameters.empty(), [], RustWhereClause.empty(), hxrtType("TypeValue")))
		]);
		RustASTTransformer.transform({items: [RImpl(impl), RTrait(trait)]}, context(true));
		throw "NoHxrtPass accepted runtime paths hidden inside structural trait and impl declarations";
	}
}
#end
