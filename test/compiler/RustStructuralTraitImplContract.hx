import reflaxe.rust.ast.RustAST.RustAssociatedConstantDeclaration;
import reflaxe.rust.ast.RustAST.RustAssociatedFunction;
import reflaxe.rust.ast.RustAST.RustAssociatedItem;
import reflaxe.rust.ast.RustAST.RustAssociatedTypeDeclaration;
import reflaxe.rust.ast.RustAST.RustConstArgument;
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
import reflaxe.rust.metadata.RustMetadataSyntax;

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
		return GenericTraitBound(path(names));
	}

	static function typeArgument(type:RustType):RustGenericArgument {
		return GenericType(type);
	}

	static function analysisPath(name:String):RustPath {
		return path(["analysis", name]);
	}

	static function analysisType(name:String):RustType {
		return RNamed(analysisPath(name));
	}

	/** Proves every declaration path slot has a distinct shared-visitor sentinel. */
	static function assertTraversalSentinels():Void {
		var declarationGenerics = RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("T"), [GenericTraitBound(analysisPath("GenericBound"))], analysisType("GenericDefault")),
			GenericConstParam(RustIdentifier.named("N"), analysisType("ConstParameterType"),
				RustConstArgument.path(analysisPath("ConstDefault")))
		]);
		var methodGenerics = RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("U"), [GenericTraitBound(analysisPath("MethodGenericBound"))],
				analysisType("MethodGenericDefault"))
		]);
		var associatedGenerics = RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("A"), [GenericTraitBound(analysisPath("AssociatedGenericBound"))],
				analysisType("AssociatedGenericDefault"))
		]);
		var trait = RustTraitDeclaration.named(VPrivate, "AnalysisTrait", declarationGenerics, [
			GenericTraitBound(analysisPath("Supertrait"))
		], RustWhereClause.of([
			RustWherePredicate.typeBounds(analysisType("WhereType"), [GenericTraitBound(analysisPath("WhereBound"))])
		]), [
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "inspect", false, methodGenerics,
				ReceiverTyped(analysisType("ReceiverAlias"), false), [RustFunctionParameter.named("value", analysisType("Parameter"))],
				analysisType("Return"), RustWhereClause.of([
					RustWherePredicate.typeBounds(analysisType("MethodWhereType"), [GenericTraitBound(analysisPath("MethodWhereBound"))])
				]), null)),
			AssocType(RustAssociatedTypeDeclaration.named("Item", associatedGenerics, [
				GenericTraitBound(analysisPath("AssociatedBound"))
			], RustWhereClause.of([
				RustWherePredicate.typeBounds(analysisType("AssociatedWhereType"), [
					GenericTraitBound(analysisPath("AssociatedWhereBound"))
				])
			]), null)),
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "VALUE", analysisType("AssociatedConstType"), null))
		]);
		var qualifiedTarget = RNamed(RustPath.qualified(analysisType("QualifiedSelf"), analysisPath("QualifiedTrait"), [
			RustPathSegment.plain("Target")
		]));
		var impl = RustImpl.traitImplementation(declarationGenerics, RustPath.relative([
			RustPathSegment.angle("ImplTrait", [GenericType(analysisType("NestedTraitArgument"))])
		]), qualifiedTarget, RustWhereClause.of([
			RustWherePredicate.typeBounds(analysisType("ImplWhereType"), [GenericTraitBound(analysisPath("ImplWhereBound"))])
		]), [
			AssocType(RustAssociatedTypeDeclaration.named("Item", RustGenericParameters.empty(), [], RustWhereClause.of([
				RustWherePredicate.typeBounds(analysisType("AssociatedImplWhereType"), [
					GenericTraitBound(analysisPath("AssociatedImplWhereBound"))
				])
			]), analysisType("AssociatedValue"))),
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "VALUE", analysisType("ImplConstType"),
				EPath(analysisPath("ImplConstValue")))),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "inspect", false, RustGenericParameters.empty(), null, [], null,
				RustWhereClause.empty(), {stmts: [], tail: null}))
		]);

		var traversed:Array<String> = [];
		RustPathAnalysis.visitTraitTree(trait, candidate -> traversed.push(RustASTPrinter.printTypePath(candidate)));
		RustPathAnalysis.visitImplTree(impl, candidate -> traversed.push(RustASTPrinter.printTypePath(candidate)));
		for (name in [
			"GenericBound", "GenericDefault", "ConstParameterType", "ConstDefault", "Supertrait", "WhereType", "WhereBound",
			"MethodGenericBound", "MethodGenericDefault", "ReceiverAlias", "Parameter", "Return", "MethodWhereType", "MethodWhereBound",
			"AssociatedGenericBound", "AssociatedGenericDefault", "AssociatedBound", "AssociatedWhereType", "AssociatedWhereBound",
			"AssociatedConstType", "NestedTraitArgument", "QualifiedSelf", "QualifiedTrait", "ImplWhereType", "ImplWhereBound",
			"AssociatedImplWhereType", "AssociatedImplWhereBound", "AssociatedValue", "ImplConstType"
		]) {
			expect(traversed.indexOf("analysis::" + name) != -1,
				'Structural declaration traversal missed analysis::$name');
		}
		expect(traversed.indexOf("analysis::ImplConstValue") == -1,
			"declaration traversal must leave associated initializer expressions to executable passes");
	}

	static function main():Void {
		var lifetime = RustLifetime.named("a");
		var copiedLifetimeBounds = [RustLifetime.staticLifetime()];
		var copiedTypeBounds = [required(["Clone"])];
		var copiedGenerics = RustGenericParameters.of([
			GenericLifetimeParam(RustIdentifier.named("owned"), copiedLifetimeBounds),
			GenericTypeParam(RustIdentifier.named("Owned"), copiedTypeBounds, null)
		]);
		copiedLifetimeBounds.pop();
		copiedTypeBounds.pop();
		expect(RustASTPrinter.printGenericParameters(copiedGenerics) == "<'owned: 'static, Owned: Clone>",
			"generic parameter payload arrays must be defensively copied");

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
		var itemLifetime = RustLifetime.named("item");
		var associatedGenerics = RustGenericParameters.of([
			GenericLifetimeParam(RustIdentifier.named("item"), [])
		]);
		var associatedWhere = RustWhereClause.of([
			RustWherePredicate.typeBounds(RNamed(RustPath.typeSelf([])), [GenericLifetimeBound(itemLifetime)])
		]);

		var traitItems:Array<RustAssociatedItem> = [
			AssocType(RustAssociatedTypeDeclaration.named("Output", RustGenericParameters.empty(), [
				required(["Clone"])
			], RustWhereClause.empty(), null)),
			AssocType(RustAssociatedTypeDeclaration.named("Lender", associatedGenerics, [], associatedWhere, null)),
			AssocType(RustAssociatedTypeDeclaration.named("Maybe", RustGenericParameters.empty(), [GenericRelaxedSized],
				RustWhereClause.empty(), null)),
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "LIMIT", named("usize"), null)),
			AssocFunction(methodSignature)
		];
		var processorTrait = RustTraitDeclaration.named(VPub, "Processor", declarationGenerics, [
			required(["Send"]),
			required(["Sync"])
		], traitWhere, traitItems);
		traitItems.pop();
		expect(processorTrait.itemCount == 5,
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
			AssocType(RustAssociatedTypeDeclaration.named("Lender", associatedGenerics, [], associatedWhere,
				RBorrow(named("T"), false, itemLifetime))),
			AssocType(RustAssociatedTypeDeclaration.named("Maybe", RustGenericParameters.empty(), [], RustWhereClause.empty(), named("str"))),
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
		expect(processorImpl.itemCount == 5,
			"impl associated items must be defensively copied");

		var boxedSelfType = RNamed(RustPath.relative([
			RustPathSegment.angle("Box", [GenericType(RNamed(RustPath.typeSelf([])))])
		]));
		var receiverItems:Array<RustAssociatedItem> = [
			AssocConst(RustAssociatedConstantDeclaration.named(VPub, "DEFAULT_LIMIT", named("usize"), ELitInt(8))),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "take", false, RustGenericParameters.empty(), ReceiverValue(false), [],
				RUnit, RustWhereClause.empty(), {stmts: [], tail: null})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "reset", false, RustGenericParameters.empty(), ReceiverValue(true), [],
				null, RustWhereClause.empty(), {
					stmts: [RLet("_slot", false, null, EUnary("&mut ", EField(ESelf, RustMember.plain("value"))))],
					tail: null
				})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "borrow", false, RustGenericParameters.of([
				GenericLifetimeParam(RustIdentifier.named("b"), [])
			]), ReceiverBorrowed(true, RustLifetime.named("b")), [], null, RustWhereClause.empty(), {stmts: [], tail: null})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "borrow_mut", false, RustGenericParameters.empty(), ReceiverBorrowed(true, null),
				[], null, RustWhereClause.empty(), {stmts: [], tail: null})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "borrow_ref", false, RustGenericParameters.of([
				GenericLifetimeParam(RustIdentifier.named("c"), [])
			]), ReceiverBorrowed(false, RustLifetime.named("c")), [], null, RustWhereClause.empty(), {stmts: [], tail: null})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "boxed", false, RustGenericParameters.empty(),
				ReceiverTyped(boxedSelfType, false), [], null, RustWhereClause.empty(), {stmts: [], tail: null})),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "boxed_mut", false, RustGenericParameters.empty(),
				ReceiverTyped(boxedSelfType, true), [], null, RustWhereClause.empty(), {
					stmts: [RLet("_boxed", false, null, EUnary("&mut ", ESelf))],
					tail: null
				}))
		];
		var receiverImpl = RustImpl.inherentItems(RustGenericParameters.of([
			GenericTypeParam(RustIdentifier.named("T"), [], null)
		]), workerType, RustWhereClause.empty(), receiverItems);

		assertTraversalSentinels();

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
		expectThrows(() -> RustTraitDeclaration.named(VPrivate, "Defaulted", RustGenericParameters.empty(), [], RustWhereClause.empty(), [
			AssocType(RustAssociatedTypeDeclaration.named("Item", RustGenericParameters.empty(), [], RustWhereClause.empty(), RI32))
		]), "stable Rust trait declarations must reject associated type defaults");
		expectThrows(() -> RustImpl.traitImplementation(RustGenericParameters.empty(), path(["Marker"]), named("Target"), RustWhereClause.empty(), [
			AssocType(RustAssociatedTypeDeclaration.named("Item", RustGenericParameters.empty(), [required(["Clone"])], RustWhereClause.empty(), RI32))
		]), "trait impl associated type definitions must reject declaration bounds");
		expectThrows(() -> RustTraitDeclaration.named(VPrivate, "Relaxed", RustGenericParameters.empty(), [GenericRelaxedSized],
			RustWhereClause.empty(), []), "trait supertraits must reject relaxed Sized bounds");
		expectThrows(() -> RustWherePredicate.typeBounds(named("String"), [GenericRelaxedSized]),
			"where predicates must reject relaxed Sized without type-parameter identity proof");
		expectThrows(() -> RustMetadataSyntax.parseGenericParameters("T: ?Clone"),
			"metadata generic bounds must reject generalized optional traits");
		expect(RustASTPrinter.printGenericParameters(RustMetadataSyntax.parseGenericParameters("T: ?Sized")) == "<T: ?Sized>",
			"metadata generic parameters must retain the admitted relaxed Sized bound");
		expectThrows(() -> RustAssociatedFunction.declaration(VPrivate, "primitive", false, RustGenericParameters.empty(),
			ReceiverTyped(RI32, false), [], null, RustWhereClause.empty(), {stmts: [], tail: null}),
			"typed self receivers must reject primitive types that cannot resolve to Self");
		expectThrows(() -> RustTraitDeclaration.named(VPrivate, "DuplicateFunctions", RustGenericParameters.empty(), [], RustWhereClause.empty(), [
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "inspect", false, RustGenericParameters.empty(), null, [], null,
				RustWhereClause.empty(), null)),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "inspect", false, RustGenericParameters.empty(), null, [], null,
				RustWhereClause.empty(), null))
		]), "trait associated functions must reject duplicate value-namespace names");
		expectThrows(() -> RustTraitDeclaration.named(VPrivate, "DuplicateTypes", RustGenericParameters.empty(), [], RustWhereClause.empty(), [
			AssocType(RustAssociatedTypeDeclaration.named("Item", RustGenericParameters.empty(), [], RustWhereClause.empty(), null)),
			AssocType(RustAssociatedTypeDeclaration.named("Item", RustGenericParameters.empty(), [], RustWhereClause.empty(), null))
		]), "trait associated types must reject duplicate type-namespace names");
		expectThrows(() -> RustTraitDeclaration.named(VPrivate, "DuplicateConstants", RustGenericParameters.empty(), [], RustWhereClause.empty(), [
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "VALUE", RI32, null)),
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "VALUE", RI32, null))
		]), "trait associated constants must reject duplicate value-namespace names");
		expectThrows(() -> RustTraitDeclaration.named(VPrivate, "ValueCollision", RustGenericParameters.empty(), [], RustWhereClause.empty(), [
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "VALUE", false, RustGenericParameters.empty(), null, [], null,
				RustWhereClause.empty(), null)),
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "VALUE", RI32, null))
		]), "associated functions and constants must share the Rust value namespace");
		expectThrows(() -> RustImpl.traitImplementation(RustGenericParameters.empty(), path(["Marker"]), named("Target"), RustWhereClause.empty(), [
			AssocConst(RustAssociatedConstantDeclaration.named(VPrivate, "VALUE", RI32, ELitInt(1))),
			AssocFunction(RustAssociatedFunction.declaration(VPrivate, "VALUE", false, RustGenericParameters.empty(), null, [], null,
				RustWhereClause.empty(), {stmts: [], tail: null}))
		]), "trait impl associated items must reject duplicate value-namespace names");
		expectThrows(() -> RustImpl.traitImplementation(RustGenericParameters.empty(), path(["Marker"]), named("Target"), RustWhereClause.empty(), [
			AssocType(RustAssociatedTypeDeclaration.named("Item", RustGenericParameters.empty(), [], RustWhereClause.empty(), RI32)),
			AssocType(RustAssociatedTypeDeclaration.named("Item", RustGenericParameters.empty(), [], RustWhereClause.empty(), RI32))
		]), "trait impl associated types must reject duplicate type-namespace names");
		expect(RustASTPrinter.printTypePath(RustMetadataSyntax.parsePath("crate::Marker<T,>")) == "crate::Marker<T>",
			"metadata trait paths must accept trailing commas after type arguments");
		expect(RustASTPrinter.printTypePath(RustMetadataSyntax.parsePath("crate::Marker<-1,>")) == "crate::Marker<-1>",
			"metadata trait paths must accept negative const arguments and trailing generic commas");
		expect(RustASTPrinter.printTypePath(RustMetadataSyntax.parsePath("Fn(i32,)")) == "Fn(i32)",
			"metadata function-trait paths must accept trailing input commas");
		expectThrows(() -> RustMetadataSyntax.parsePath("crate::Marker<{ N + 1 }>"),
			"braced const expressions must remain an explicitly unsupported closed-grammar form");

		Sys.print(RustASTPrinter.printFile({items: fileItems}));
	}
}
