import reflaxe.rust.ast.RustAST.RustConstArgument;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameter;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustIdentifier;
import reflaxe.rust.ast.RustAST.RustLifetime;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustTraitBoundModifier;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustASTPrinter;

class RustStructuralPathContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectThrows(action:() -> Void, message:String):Void {
		var threw = false;
		try {
			action();
		} catch (_:String) {
			threw = true;
		}
		expect(threw, message);
	}

	static function namedType(name:String):RustType {
		return RNamed(RustPath.single(name));
	}

	static function main():Void {
		var typeT = namedType("T");
		var typeNPath = RustPath.single("N");
		var vecOfT = RustPath.relative([
			RustPathSegment.angle("Vec", [GenericType(typeT)])
		]);
		var optionOfVec = RustPath.relative([
			RustPathSegment.angle("Option", [GenericType(RNamed(vecOfT))])
		]);
		expect(RustASTPrinter.printTypePath(optionOfVec) == "Option<Vec<T>>", "nested type arguments must stay structural");

		var lifetimeA = RustLifetime.named("a");
		var borrowed = RBorrow(typeT, false, lifetimeA);
		expect(RustASTPrinter.printTypeSyntax(borrowed) == "&'a T", "borrow lifetimes must be typed and printer-owned");

		var arrayType = RArray(typeT, RustConstArgument.path(typeNPath));
		expect(RustASTPrinter.printTypeSyntax(arrayType) == "[T; N]", "const array lengths must stay structural");

		var bufferPath = RustPath.relative([
			RustPathSegment.angle("Buffer", [
				GenericLifetime(lifetimeA),
				GenericType(typeT),
				GenericConst(RustConstArgument.integer(32))
			])
		]);
		expect(RustASTPrinter.printTypePath(bufferPath) == "Buffer<'a, T, 32>", "lifetime/type/const arguments must print deterministically");
		var wideConstPath = RustPath.relative([
			RustPathSegment.angle("Capacity", [GenericConst(RustConstArgument.decimalInteger("18446744073709551615"))])
		]);
		expect(RustASTPrinter.printTypePath(wideConstPath) == "Capacity<18446744073709551615>",
			"const integer syntax must not be limited by Haxe Int width");

		var turbofish = RustPath.relative([
			RustPathSegment.plain("hxrt"),
			RustPathSegment.plain("array"),
			RustPathSegment.angle("Array", [GenericType(typeT), GenericConst(RustConstArgument.integer(32))]),
			RustPathSegment.plain("new")
		]);
		expect(RustASTPrinter.printExpressionPath(turbofish) == "hxrt::array::Array::<T, 32>::new",
			"expression paths must own turbofish punctuation");

		var iteratorTrait = RustPath.relative([
			RustPathSegment.plain("core"),
			RustPathSegment.plain("iter"),
			RustPathSegment.plain("Iterator")
		]);
		var qualifiedItem = RustPath.qualified(typeT, iteratorTrait, [RustPathSegment.plain("Item")]);
		expect(RustASTPrinter.printTypePath(qualifiedItem) == "<T as core::iter::Iterator>::Item",
			"qualified associated paths must be structural");
		expect(RustASTPrinter.printTypePath(RustPath.cratePath([
			RustPathSegment.plain("model"), RustPathSegment.plain("Thing")
		])) == "crate::model::Thing", "crate roots must not be ordinary identifier strings");
		expect(RustASTPrinter.printTypePath(RustPath.absolute([
			RustPathSegment.plain("alloc"), RustPathSegment.plain("vec"), RustPathSegment.plain("Vec")
		])) == "::alloc::vec::Vec", "absolute roots must own their leading separator");
		expect(RustASTPrinter.printTypePath(RustPath.selfModule([
			RustPathSegment.plain("child")
		])) == "self::child", "module-self roots must be structural");
		expect(RustASTPrinter.printTypePath(RustPath.superPath(2, [
			RustPathSegment.plain("child")
		])) == "super::super::child", "super depth must be structural");
		expect(RustASTPrinter.printTypePath(RustPath.typeSelf([
			RustPathSegment.plain("Item")
		])) == "Self::Item", "type-Self roots must be structural");
		expect(RustASTPrinter.printTypePath(RustPath.relative([
			RustPathSegment.plainIdentifier(RustIdentifier.raw("type"))
		])) == "r#type", "raw-identifier syntax must require explicit authority");
		expect(RustASTPrinter.printTypePath(RustPath.relative([
			RustPathSegment.parenthesized("Fn", [typeT], namedType("U"))
		])) == "Fn(T) -> U", "function-trait path arguments must stay structural");

		var parameters = RustGenericParameters.of([
			GenericLifetimeParam(RustIdentifier.named("a"), [RustLifetime.staticLifetime()]),
			GenericTypeParam(RustIdentifier.named("T"), [
				GenericTraitBound(RustPath.single("Clone"), TraitBoundRequired),
				GenericTraitBound(RustPath.single("Send"), TraitBoundRequired),
				GenericLifetimeBound(lifetimeA)
			], null),
			GenericConstParam(RustIdentifier.named("N"), namedType("usize"), RustConstArgument.integer(32))
		]);
		expect(RustASTPrinter.printGenericParameters(parameters) == "<'a: 'static, T: Clone + Send + 'a, const N: usize = 32>",
			"generic declaration parameters must own bounds, lifetimes, and const defaults");
		var relaxedParameters = RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("T"), [
				GenericTraitBound(RustPath.single("Sized"), TraitBoundOptional)
			], null)
		]);
		expect(RustASTPrinter.printGenericParameters(relaxedParameters) == "<T: ?Sized>",
			"optional trait bounds must use a closed modifier instead of a Boolean convention");

		expectThrows(() -> RustIdentifier.named("not::one"), "target punctuation must not enter an identifier");
		expectThrows(() -> RustIdentifier.named("type"), "Rust keywords must require explicit raw-identifier authority");
		expectThrows(() -> RustIdentifier.named("abstract"), "reserved Rust 2021 keywords must be rejected from ordinary identifiers");
		expectThrows(() -> RustLifetime.named("'a"), "lifetime factories must accept names, not rendered tokens");
		expectThrows(() -> RustLifetime.named("static"), "the static lifetime must use its closed constructor");
		expectThrows(() -> RustConstArgument.decimalInteger("12usize"), "const integer tokens must reject suffix syntax");
		expectThrows(() -> RustPath.cratePath([]), "crate roots require a structural tail segment");
		expectThrows(() -> RustPath.selfModule([]), "module-self roots require a structural tail segment");
		expectThrows(() -> RustPath.superPath(1, []), "super roots require a structural tail segment");
		expectThrows(() -> RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("T"), [], null),
			GenericLifetimeParam(RustIdentifier.named("a"), [])
		]), "lifetime declarations must precede type and const declarations");

		var rendered = [
			RustASTPrinter.printTypePath(optionOfVec),
			RustASTPrinter.printTypeSyntax(borrowed),
			RustASTPrinter.printTypeSyntax(arrayType),
			RustASTPrinter.printTypePath(bufferPath),
			RustASTPrinter.printExpressionPath(turbofish),
			RustASTPrinter.printTypePath(qualifiedItem),
			RustASTPrinter.printGenericParameters(parameters)
		].join("\n");
		Sys.println(rendered);
	}
}
