import reflaxe.rust.ast.RustAST.RustConstArgument;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameter;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustImpl;
import reflaxe.rust.ast.RustAST.RustLifetime;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustTraitObject;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustASTPrinter;
import reflaxe.rust.metadata.RustMetadataSyntax;

class RustStructuralTypeDeclarationContract {
	static function named(name:String):RustType {
		return RNamed(RustPath.single(name));
	}

	static function typeArgument(type:RustType):RustGenericArgument {
		return GenericType(type);
	}

	static function main():Void {
		var lifetime = RustLifetime.named("a");
		var declarationGenerics = RustMetadataSyntax.parseGenericParameters("'a, T: Clone + Send + 'a, const N: usize");
		var valueType = RustMetadataSyntax.parseType("&'a mut [T; N]");
		var holderType = RNamed(RustPath.relative([
			RustPathSegment.angle("Holder", [
				GenericLifetime(lifetime),
				typeArgument(named("T")),
				GenericConst(RustConstArgument.path(RustPath.single("N")))
			])
		]));
		var optionT = RustMetadataSyntax.parseType("Option<T>");
		var inferredVec = RustMetadataSyntax.parseType("Vec<_>");
		var carriesGenericInfer = switch (inferredVec) {
			case RNamed(path) if (path.segmentCount == 1 && path.segmentAt(0).genericArgumentCount == 1):
				switch (path.segmentAt(0).genericArgumentAt(0)) {
					case GenericInfer: true;
					case _: false;
				}
			case _: false;
		};
		if (!carriesGenericInfer)
			throw "metadata inference placeholders must remain structural generic arguments";

		var callbackTrait = RustTraitObject.of([
			GenericTraitBound(RustPath.relative([
				RustPathSegment.parenthesized("Fn", [named("U")], named("T"))
			])),
			GenericTraitBound(RustPath.single("Send")),
			GenericTraitBound(RustPath.single("Sync")),
			GenericLifetimeBound(lifetime)
		]);
		var callbackType = RNamed(RustPath.cratePath([
			RustPathSegment.angle("HxRc", [typeArgument(RTraitObject(callbackTrait))])
		]));
		var methodGenerics = RustGenericParameters.of([
			GenericTypeParam(reflaxe.rust.ast.RustAST.RustIdentifier.named("U"), [
				GenericTraitBound(RustPath.relative([
					RustPathSegment.plain("core"),
					RustPathSegment.plain("fmt"),
					RustPathSegment.plain("Debug")
				]))
			], null)
		]);

		var items:Array<RustItem> = [
			RStruct({
				name: "Holder",
				isPub: false,
				generics: declarationGenerics,
				fields: [{name: "value", ty: valueType, isPub: false}]
			}),
			REnum({
				name: "Message",
				isPub: false,
				generics: RustMetadataSyntax.parseGenericParameters("T"),
				variants: [{name: "Value", args: [optionT]}]
			}),
			RImpl(RustImpl.inherent(declarationGenerics, holderType, [{
					name: "call",
					isPub: false,
					generics: methodGenerics,
					args: [
						{name: "_operation", ty: RBorrow(named("str"), false, null)},
						{name: "_callback", ty: callbackType}
					],
					ret: optionT,
					body: {stmts: [], tail: EPath(RustPath.single("None"))}
				}]))
		];

		Sys.print(RustASTPrinter.printFile({items: items}));
	}
}
