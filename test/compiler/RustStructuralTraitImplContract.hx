import reflaxe.rust.ast.RustAST.RustAssociatedConstantDeclaration;
import reflaxe.rust.ast.RustAST.RustAssociatedFunction;
import reflaxe.rust.ast.RustAST.RustAssociatedItem;
import reflaxe.rust.ast.RustAST.RustAssociatedTypeDeclaration;
import reflaxe.rust.ast.RustAST.RustFunctionParameter;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameter;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustIdentifier;
import reflaxe.rust.ast.RustAST.RustImpl;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustLifetime;
import reflaxe.rust.ast.RustAST.RustMember;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustSelfReceiver;
import reflaxe.rust.ast.RustAST.RustTraitDeclaration;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustAST.RustVisibility;
import reflaxe.rust.ast.RustAST.RustWhereClause;
import reflaxe.rust.ast.RustAST.RustWherePredicate;
import reflaxe.rust.ast.RustASTPrinter;
import reflaxe.rust.ast.RustPathAnalysis;

/**
	Executable contract for structural Rust traits, impls, associated items, and where clauses.

	Why
	- Trait and impl headers decide method dispatch, generic authority, and orphan-rule ownership. When
	  those headers are strings, passes can neither inspect the target nor prove which bounds apply.
	- Associated method signatures and `self` receivers are a second declaration grammar; hiding them
	  in raw blocks would leave the migration only cosmetically complete.

	What
	- Characterizes a generic trait, supertraits, type/lifetime where predicates, associated type and
	  const signatures, an associated method signature, and a matching trait impl with typed bodies.
	- Exercises defensive copies, shared path traversal, explicit unit versus omitted returns, and the
	  legacy inherent-function adapter used by already-typed class methods.

	How
	- Builds one warning-clean Rust library entirely from structural nodes and prints deterministic
	  bytes. The JavaScript runner repeats the build, asks rustc to compile it with warnings denied,
	  and separately proves malformed declaration shapes fail closed.
**/
class RustStructuralTraitImplContract {
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

	static function named(name:String):RustType {
		return RNamed(path([name]));
	}

	static function required(names:Array<String>):RustGenericBound {
		return GenericTraitBound(path(names), TraitBoundRequired);
	}

	static function typeArgument(type:RustType):RustGenericArgument {
		return GenericType(type);
	}

	static function main():Void {
		var lifetime = RustLifetime.named("a");
		var declarationGenerics = RustGenericParameters.of([
			GenericLifetimeParam(RustIdentifier.named("a"), []),
			GenericTypeParam(RustIdentifier.named("T"), [], null)
		]);
		var workerType = RNamed(RustPath.relative([
			RustPathSegment.angle("Worker", [typeArgument(named("T"))])
		]));
		var processorPath = RustPath.relative([
			RustPathSegment.angle("Processor", [GenericLifetime(lifetime), typeArgument(named("T"))])
		]);

		var traitPredicates = [RustWherePredicate.typeBounds(named("T"), [
			required(["Clone"]),
			GenericLifetimeBound(lifetime)
		]), RustWherePredicate.lifetimeBounds(lifetime, [RustLifetime.staticLifetime()])];
		var traitWhere = RustWhereClause.of(traitPredicates);
		traitPredicates.pop();
		expect(traitWhere.predicateCount == 2,
			"where-clause predicates must be defensively copied");

		var methodGenerics = RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("U"), [required(["core", "fmt", "Debug"])], null)
		]);
		var methodWhere = RustWhereClause.of([
			RustWherePredicate.typeBounds(named("U"), [required(["Send"])])
		]);
		var methodParameters = [
			RustFunctionParameter.named("value", named("T")),
			RustFunctionParameter.named("_other", named("U"))
		];
		var methodSignature = RustAssociatedFunction.declaration(VPrivate, "process", false, methodGenerics,
			ReceiverBorrowed(false, null), methodParameters, RNamed(RustPath.typeSelf([
				RustPathSegment.plain("Output")
			])), methodWhere, null);
		methodParameters.pop();
		expect(methodSignature.parameterCount == 2,
			"associated-function parameters must be defensively copied");

		var traitItems:Array<RustAssociatedItem> = [
			AssocType(RustAssociatedTypeDeclaration.named("Output", RustGenericParameters.empty(), [
				required(["Clone"])
			], RustWhereClause.empty(), null)),
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "LIMIT", named("usize"), null)),
			AssocFunction(methodSignature)
		];
		var processorTrait = RustTraitDeclaration.named(VPub, "Processor", declarationGenerics, [
			required(["Send"]),
			required(["Sync"])
		], traitWhere, traitItems);
		traitItems.pop();
		expect(processorTrait.itemCount == 3,
			"trait associated items must be defensively copied");

		var implWhere = RustWhereClause.of([
			RustWherePredicate.typeBounds(named("T"), [
				required(["Clone"]),
				required(["Send"]),
				required(["Sync"]),
				GenericLifetimeBound(lifetime)
			]),
			RustWherePredicate.lifetimeBounds(lifetime, [RustLifetime.staticLifetime()])
		]);
		var implItems:Array<RustAssociatedItem> = [
			AssocType(RustAssociatedTypeDeclaration.named("Output", RustGenericParameters.empty(), [], RustWhereClause.empty(), named("T"))),
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "LIMIT", named("usize"), ELitInt(4))),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "process", false, methodGenerics,
				ReceiverBorrowed(false, null), [
					RustFunctionParameter.named("value", named("T")),
					RustFunctionParameter.named("_other", named("U"))
				], RNamed(RustPath.typeSelf([RustPathSegment.plain("Output")])), methodWhere, {
					stmts: [],
					tail: EPath(path(["value"]))
				}))
		];
		var processorImpl = RustImpl.traitImplementation(declarationGenerics, processorPath, workerType, implWhere, implItems);
		implItems.pop();
		expect(processorImpl.itemCount == 3,
			"impl associated items must be defensively copied");

		var boxedSelfType = RNamed(RustPath.relative([
			RustPathSegment.angle("Box", [GenericType(RNamed(RustPath.typeSelf([])))])
		]));
		var receiverItems:Array<RustAssociatedItem> = [
			AssocConst(RustAssociatedConstantDeclaration.named(VPub, "DEFAULT_LIMIT", named("usize"), ELitInt(8))),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "take", false, RustGenericParameters.empty(), ReceiverValue(false), [],
				null, RustWhereClause.empty(), {stmts: [], tail: null})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "reset", false, RustGenericParameters.empty(), ReceiverValue(true), [],
				null, RustWhereClause.empty(), {
					stmts: [RLet("_slot", false, null, EUnary("&mut ", EField(ESelf, RustMember.plain("value"))))],
					tail: null
				})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "borrow", false, RustGenericParameters.of([
				GenericLifetimeParam(RustIdentifier.named("b"), [])
			]), ReceiverBorrowed(true, RustLifetime.named("b")), [], null, RustWhereClause.empty(), {stmts: [], tail: null})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "boxed", false, RustGenericParameters.empty(), ReceiverTyped(boxedSelfType), [],
				null, RustWhereClause.empty(), {stmts: [], tail: null}))
		];
		var receiverImpl = RustImpl.inherentItems(RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("T"), [], null)
		]), workerType, RustWhereClause.empty(), receiverItems);

		var traversed:Array<String> = [];
		RustPathAnalysis.visitTraitTree(processorTrait, candidate -> traversed.push(RustASTPrinter.printTypePath(candidate)));
		RustPathAnalysis.visitImplTree(processorImpl, candidate -> traversed.push(RustASTPrinter.printTypePath(candidate)));
		expect(traversed.indexOf("Send") != -1 && traversed.indexOf("Processor<'a, T>") != -1,
			"trait and impl paths must remain structurally traversable");

		var fileItems:Array<RustItem> = [
			RInnerAttribute(reflaxe.rust.ast.RustAST.RustAttribute.pathList(path(["allow"]), [path(["dead_code"])])),
			RStruct({
				name: "Worker",
				isPub: false,
				generics: RustGenericParameters.of([
					GenericTypeParam(RustIdentifier.named("T"), [], null)
				]),
				fields: [{name: "value", ty: named("T"), isPub: false}]
			}),
			RTrait(processorTrait),
			RImpl(processorImpl),
			RImpl(receiverImpl)
		];

		expectThrows(() -> RustWherePredicate.typeBounds(named("T"), []),
			"a type where-predicate without bounds must fail closed");
		expectThrows(() -> RustWhereClause.of([]),
			"an explicit where clause without predicates must use the empty constructor");
		expectThrows(() -> RustAssociatedFunction.declaration(VPrivate, "bad", false, RustGenericParameters.empty(), null, [
			RustFunctionParameter.named("same", RI32),
			RustFunctionParameter.named("same", RI32)
		], null, RustWhereClause.empty(), {stmts: [], tail: null}),
			"duplicate associated-function parameters must fail closed");
		expectThrows(() -> RustTraitDeclaration.named(VPub, "Bad", RustGenericParameters.empty(), [], RustWhereClause.empty(), [
			AssocFunction(RustAssociatedFunction.declaration(VPub, "visible", false, RustGenericParameters.empty(), null, [], null,
				RustWhereClause.empty(), null))
		]), "trait associated functions must reject visibility qualifiers");
		expectThrows(() -> RustImpl.traitImplementation(RustGenericParameters.empty(), path(["Marker"]), named("Target"), RustWhereClause.empty(), [
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "missing", false, RustGenericParameters.empty(), null, [], null,
				RustWhereClause.empty(), null))
		]), "trait impl associated functions must require bodies");
		expectThrows(() -> RustImpl.inherentItems(RustGenericParameters.empty(), named("Target"), RustWhereClause.empty(), [
			AssocType(RustAssociatedTypeDeclaration.named("Unstable", RustGenericParameters.empty(), [], RustWhereClause.empty(), named("T")))
		]), "inherent impls must reject trait-only associated type declarations");
		expectThrows(() -> RustTraitDeclaration.named(VPub, "BadConst", RustGenericParameters.empty(), [], RustWhereClause.empty(), [
			AssocConst(RustAssociatedConstantDeclaration.named(VPub, "VISIBLE", RI32, null))
		]), "trait associated constants must reject visibility qualifiers");
		expectThrows(() -> RustImpl.traitImplementation(RustGenericParameters.empty(), path(["Marker"]), named("Target"), RustWhereClause.empty(), [
			AssocConst(RustAssociatedConstantDeclaration.named(VPub, "VISIBLE", RI32, ELitInt(1)))
		]), "trait impl associated constants must reject visibility qualifiers");

		Sys.print(RustASTPrinter.printFile({items: fileItems}));
	}
}
