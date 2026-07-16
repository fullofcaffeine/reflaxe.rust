import reflaxe.rust.ast.RustAST.RustConstArgument;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameter;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustIdentifier;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustLifetime;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustASTPrinter;

class RustStructuralExpressionPathContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function named(name:String):RustType {
		return RNamed(RustPath.single(name));
	}

	static function typeArgument(type:RustType):RustGenericArgument {
		return GenericType(type);
	}

	static function constPathArgument(name:String):RustGenericArgument {
		return GenericConst(RustConstArgument.path(RustPath.single(name)));
	}

	static function main():Void {
		var lifetime = RustLifetime.named("a");
		var typeU = named("U");
		var factoryPath = RustPath.relative([
			RustPathSegment.angle("Factory", [
				GenericLifetime(lifetime),
				typeArgument(typeU),
				constPathArgument("N")
			])
		]);
		var packetPath = RustPath.relative([
			RustPathSegment.angle("Packet", [typeArgument(typeU), constPathArgument("N")])
		]);
		var optionType = RNamed(RustPath.relative([
			RustPathSegment.angle("Option", [typeArgument(typeU)])
		]));
		var makePath = RustPath.qualified(named("T"), factoryPath, [
			RustPathSegment.angle("make", [typeArgument(typeU)])
		]);
		expect(RustPath.single("selected").plainRelativeIdentifierName() == "selected",
			"one plain relative segment must retain local-shaped identity");
		expect(packetPath.plainRelativeIdentifierName() == null,
			"generic nominal paths must not be mistaken for local reads");
		expect(makePath.plainRelativeIdentifierName() == null,
			"qualified associated paths must not be mistaken for local reads");
		var generics = RustGenericParameters.of([
			GenericLifetimeParam(RustIdentifier.named("a"), []),
			GenericTypeParam(RustIdentifier.named("U"), [], null),
			GenericConstParam(RustIdentifier.named("N"), named("usize"), null),
			GenericTypeParam(RustIdentifier.named("T"), [
				GenericTraitBound(factoryPath)
			], null)
		]);

		var items:Array<RustItem> = [
			RFn({
				name: "build",
				isPub: false,
				generics: generics,
				args: [{name: "value", ty: optionType}],
				ret: RNamed(packetPath),
				body: {
					stmts: [
						RLet("index", false, named("usize"), ECast(ELitInt(0), named("usize"))),
						RLet("selected", false, null, EMatch(EPath(RustPath.single("value")), [
							{
								pat: PTupleStruct(RustPath.relative([
									RustPathSegment.plain("Option"),
									RustPathSegment.plain("Some")
								]), [PBind("inner")]),
								expr: EPath(RustPath.single("inner"))
							},
							{
								pat: PPath(RustPath.relative([
									RustPathSegment.plain("Option"),
									RustPathSegment.plain("None")
								])),
								expr: EMacroCall("unreachable", [])
							}
						]))
					],
					tail: EStructLit(packetPath, [
						{
							name: "value",
							expr: ECall(EPath(makePath), [EPath(RustPath.single("selected"))])
						},
						{name: "index", expr: EPath(RustPath.single("index"))}
					])
				}
			})
		];

		Sys.print(RustASTPrinter.printFile({items: items}));
	}
}
