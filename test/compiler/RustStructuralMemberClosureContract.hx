import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustClosureParameter;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustTraitObject;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustASTPrinter;
import reflaxe.rust.ast.RustPathAnalysis;

class RustStructuralMemberClosureContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectThrows(action:Void->Void, message:String):Void {
		var threw = false;
		try {
			action();
		} catch (_:String) {
			threw = true;
		}
		expect(threw, message);
	}

	static function path(names:Array<String>):RustPath {
		return RustPath.relative([for (name in names) RustPathSegment.plain(name)]);
	}

	static function namedPath(names:Array<String>):RustType {
		return RNamed(path(names));
	}

	static function genericType(name:String, arguments:Array<RustGenericArgument>):RustType {
		return RNamed(RustPath.relative([RustPathSegment.angle(name, arguments)]));
	}

	static function local(name:String):RustExpr {
		return EPath(RustPath.single(name));
	}

	static function main():Void {
		var optionString = genericType("Option", [GenericType(RString)]);
		var choiceType = namedPath(["Choice"]);
		var choiceAlternatives = [
			PTupleStruct(path(["Choice", "First"]), [PBind("selected")]),
			PTupleStruct(path(["Choice", "Second"]), [PBind("selected")])
		];
		var suppliedArguments:Array<RustGenericArgument> = [GenericType(optionString)];
		var downcastMember = RustMember.generic("downcast_ref", suppliedArguments);
		suppliedArguments[0] = GenericType(RI32);
		expect(downcastMember.genericArgumentCount == 1,
			"member generic arguments must be defensively copied");

		var collectType = genericType("Vec", [GenericInfer]);
		expect(RustPathAnalysis.matchesPlainMember(RustMember.plain("clone"), "clone"),
			"plain receiver members must support exact structural matching");
		expect(!RustPathAnalysis.matchesPlainMember(RustMember.generic("clone", [GenericType(RI32)]), "clone"),
			"generic receiver members must not masquerade as plain members");
		expect(!RustPathAnalysis.matchesPlainMember(RustMember.plain("clone_extra"), "clone"),
			"member matching must reject identifier suffix collisions");

		var tupleParameter = RustClosureParameter.pattern(PTuple([
			PBind("key"),
			PAlias("whole", PTuple([PBind("value")]))
		]));
		expect(RustPathAnalysis.patternBindsName(tupleParameter.patternValue, "value"),
			"tuple and alias closure patterns must expose nested shadowing");
		expect(RustPathAnalysis.closureParametersBindName([tupleParameter], "whole"),
			"closure parameter lists must expose alias bindings");
		expect(!RustPathAnalysis.closureParametersBindName([tupleParameter], "missing"),
			"closure parameter shadowing must use exact binding identity");

		var contractFile:RustFile = {
			items: [REnum({
				name: "Choice",
				isPub: false,
				generics: RustGenericParameters.empty(),
				variants: [
					{name: "First", args: [RI32]},
					{name: "Second", args: [RI32]}
				]
			}), RFn({
				name: "member_closure_contract",
				isPub: false,
				generics: RustGenericParameters.empty(),
				args: [
					{
						name: "value",
						ty: RBorrow(RTraitObject(RustTraitObject.of([
							GenericTraitBound(path(["std", "any", "Any"]))
						])), false, null)
					},
					{name: "iter", ty: genericType("Vec", [GenericType(RI32)])}
				],
				ret: RUnit,
				body: {
					stmts: [
						RLet("_downcast", false, null, ECall(EField(local("value"), downcastMember), [])),
						RLet("_collected", false, null, ECall(EField(
							ECall(EField(local("iter"), RustMember.plain("into_iter")), []),
							RustMember.generic("collect", [GenericType(collectType)])), [])),
						RLet("typed", false, null, EClosure([
							RustClosureParameter.typedBinding("item", optionString)
						], {stmts: [], tail: local("item")}, true)),
						RLet("_tupled", false, null, EClosure([
							RustClosureParameter.typedPattern(PTuple([PBind("key"), PBind("value")]), RTuple([RI32, RI32]))
						], {stmts: [], tail: EBinary("+", local("key"), local("value"))}, false)),
						RLet("_or_pattern", false, null, EClosure([
							RustClosureParameter.typedPattern(POr(choiceAlternatives), choiceType)
						], {stmts: [], tail: local("selected")}, false)),
						RLet("_alias_or_pattern", false, null, EClosure([
							RustClosureParameter.typedPattern(PAlias("_whole", POr(choiceAlternatives)), choiceType)
						], {stmts: [], tail: local("selected")}, false)),
						RLet("_wildcard", false, null, EClosure([
							RustClosureParameter.typedPattern(PWildcard, RI32)
						], {stmts: [], tail: ELitInt(0)}, false)),
						RSemi(ECall(local("typed"), [EPath(path(["Option", "None"]))]))
					],
					tail: null
				}
			})]
		};

		var hxrtType = genericType("Envelope", [GenericType(namedPath(["hxrt", "Payload"]))]);
		var hxrtMember = RustMember.generic("decode", [GenericType(hxrtType)]);
		var memberFound = false;
		RustPathAnalysis.visitMemberTree(hxrtMember, candidate -> {
			if (RustPathAnalysis.belongsToNamespace(candidate, "hxrt"))
				memberFound = true;
		});
		expect(memberFound, "member generic traversal must expose nested runtime paths");

		var typedParameter = RustClosureParameter.typedBinding("payload", hxrtType);
		var parameterFound = false;
		RustPathAnalysis.visitClosureParameterTree(typedParameter, candidate -> {
			if (RustPathAnalysis.belongsToNamespace(candidate, "hxrt"))
				parameterFound = true;
		});
		expect(parameterFound, "closure parameter types must remain structurally traversable");

		var patternParameter = RustClosureParameter.pattern(PTuple([
			PTupleStruct(path(["hxrt", "Kind"]), [PBind("payload")])
		]));
		var patternPathFound = false;
		RustPathAnalysis.visitClosureParameterTree(patternParameter, candidate -> {
			if (RustPathAnalysis.belongsToNamespace(candidate, "hxrt"))
				patternPathFound = true;
		});
		expect(patternPathFound, "closure parameter patterns must remain structurally traversable");

		expectThrows(() -> RustMember.plain("downcast_ref::<u32>"),
			"member identifiers must reject embedded turbofish syntax");
		expectThrows(() -> RustMember.plain("module::member"),
			"member identifiers must reject embedded path syntax");
		expectThrows(() -> RustClosureParameter.binding("item: hxrt::Payload"),
			"closure bindings must reject embedded type syntax");
		expectThrows(() -> RustClosureParameter.typedBinding("_", RI32),
			"wildcards must remain patterns rather than masquerading as identifier bindings");
		expectThrows(() -> RustClosureParameter.pattern(PBind("item: hxrt::Payload")),
			"structural closure patterns must not bypass binding validation");
		expectThrows(() -> RustClosureParameter.pattern(POr([])),
			"an empty or-pattern must not silently become a zero-argument closure");

		Sys.print(RustASTPrinter.printFile(contractFile));
	}
}
