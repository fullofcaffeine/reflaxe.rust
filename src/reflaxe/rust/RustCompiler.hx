package reflaxe.rust;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.ds.Either;
import haxe.io.Path;
import haxe.macro.Expr;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import sys.FileSystem;
import sys.io.File;
import reflaxe.GenericCompiler;
import reflaxe.compiler.TargetCodeInjection as ReflaxeTargetCodeInjection;
import reflaxe.data.ClassFuncArg;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import reflaxe.output.DataAndFileInfo;
import reflaxe.output.OutputPath;
import reflaxe.output.StringOrBytes;
import reflaxe.rust.ast.RustAST;
import reflaxe.rust.ast.RustAST.RustBlock;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustGenericArgument;
import reflaxe.rust.ast.RustAST.RustGenericBound;
import reflaxe.rust.ast.RustAST.RustGenericParameter;
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustIdentifier;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustLifetime;
import reflaxe.rust.ast.RustAST.RustMatchArm;
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustAST.RustPathSegment;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustCompilerRawReason;
import reflaxe.rust.ast.RustAST.RustMetadataRawReason;
import reflaxe.rust.ast.RustAST.RustRawCode;
import reflaxe.rust.ast.RustAST.RustSourceRawReason;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustStructLitField;
import reflaxe.rust.ast.RustAST.RustTraitBoundModifier;
import reflaxe.rust.ast.RustAST.RustTraitObject;
import reflaxe.rust.ast.RustAST.RustType;
import reflaxe.rust.ast.RustAST.RustVisibility;
import reflaxe.helpers.TypeHelper;
import reflaxe.rust.analyze.MetalIslandAnalyzer;
import reflaxe.rust.analyze.MetalIslandAnalyzer.MetalIslandDeclaration;
import reflaxe.rust.analyze.MetalIslandAnalyzer.MetalIslandSnapshot;
import reflaxe.rust.analyze.MetalViabilityAnalyzer;
import reflaxe.rust.analyze.MetalViabilityAnalyzer.MetalIssueClassSummary;
import reflaxe.rust.analyze.MetalViabilityAnalyzer.MetalModuleViability;
import reflaxe.rust.analyze.MetalViabilityAnalyzer.MetalViabilityBlocker;
import reflaxe.rust.analyze.MetalViabilityAnalyzer.MetalViabilitySnapshot;
import reflaxe.rust.analyze.NoHxrtEligibilityAnalyzer;
import reflaxe.rust.analyze.NoHxrtEligibilityAnalyzer.NoHxrtEligibilityResult;
import reflaxe.rust.analyze.ProfileContractAnalyzer;
import reflaxe.rust.analyze.ProfileContractAnalyzer.ProfileContractDiagnostics;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeFallbackSummary;
import reflaxe.rust.analyze.RuntimeRequirementAnalyzer.RuntimeRequirementEntry;
import reflaxe.rust.analyze.NativeSurfaceUsageAnalyzer;
import reflaxe.rust.analyze.NativeSurfaceUsageAnalyzer.TypedNativeImportHit;
import reflaxe.rust.analyze.SurfaceContractRegistry;
import reflaxe.rust.analyze.SurfaceContractRegistry.NativeRepresentationDecision;
import reflaxe.rust.analyze.SurfaceContractRegistry.SurfaceContract;
import reflaxe.rust.analyze.HxrtFeatureAnalyzer.HxrtFeatureReason;
import reflaxe.rust.analyze.InternalHelperBoundary;
import reflaxe.rust.analyze.ReflectionRegistryPlan;
import reflaxe.rust.analyze.ReflectionRegistryPlan.ReflectionRegistryPlanData;
import reflaxe.rust.analyze.BorrowRegionAnalyzer;
import reflaxe.rust.analyze.SendSyncAnalyzer;
import reflaxe.rust.analyze.TypeUsageAnalyzer;
import reflaxe.rust.macros.CargoMetaRegistry;
import reflaxe.rust.macros.RustExtraSrcRegistry;
import reflaxe.rust.metadata.RustMetadataSyntax;
import reflaxe.rust.naming.RustNaming;
import reflaxe.rust.ProfileResolver;
import reflaxe.rust.RustProfile;
import reflaxe.rust.RustDiagnostic.RustDiagnosticId;
import reflaxe.rust.compiler.RustBuildContext;
import reflaxe.rust.compiler.RustClassContext;
import reflaxe.rust.compiler.RustFuncContext;
import reflaxe.rust.emit.ProjectEmitter;
import reflaxe.rust.emit.ProjectEmitter.HxrtFeatureSelection;
import reflaxe.rust.lower.StringLowering;

using reflaxe.helpers.BaseTypeHelper;
using reflaxe.helpers.ClassFieldHelper;
using reflaxe.helpers.ModuleTypeHelper;

private typedef RustImplSpec = {
	var traitPath:String;
	var pos:haxe.macro.Expr.Position;
	@:optional var forType:String;
	@:optional var body:String;
};

private enum RustTestReturnKind {
	TestVoid;
	TestBool;
}

private enum HaxeArrayIteratorKind {
	ArrayIteratorValues;
	ArrayIteratorKeyValues;
}

private typedef RustTestSpec = {
	var classType:ClassType;
	var field:ClassField;
	var wrapperName:String;
	var serial:Bool;
	var returnKind:RustTestReturnKind;
	var pos:haxe.macro.Expr.Position;
};

private typedef ProfileContractReportSnapshot = {
	var schemaVersion:Int;
	var backendId:String;
	var contract:String;
	var familyStdPin:FamilyStdPinReportSnapshot;
	var strictBoundary:Bool;
	var strictExamples:Bool;
	var metalFallbackAllowed:Bool;
	var metalContractHardError:Bool;
	var noHxrt:Bool;
	var asyncEnabled:Bool;
	var nullableStrings:Bool;
	var portableNativeImportStrict:Bool;
	var portableNativeImportsDetected:Bool;
	var nativeImportHits:Array<String>;
	var nativeImportHitsTyped:Array<TypedNativeImportHit>;
	var consumedSurfaces:Array<SurfaceContract>;
	var nativeRepresentationPlan:Array<NativeRepresentationDecision>;
	var usedModuleCount:Int;
	var warnings:Array<String>;
	var errors:Array<String>;
};

private typedef HxrtPlanReportSnapshot = {
	var schemaVersion:Int;
	var backendId:String;
	var runtimeId:String;
	var contract:String;
	var familyStdPin:FamilyStdPinReportSnapshot;
	var mode:String;
	var noHxrt:Bool;
	var useDefaultFeatures:Bool;
	var inferenceDisabled:Bool;
	var manualFeatures:Array<String>;
	var selectedFeatures:Array<String>;
	var reasons:Array<HxrtFeatureReason>;
	var runtimeRequirements:Array<RuntimeRequirementEntry>;
	var fallbackSummary:RuntimeFallbackSummary;
	var usedModuleCount:Int;
	var hxrtDependencyLine:String;
};

private typedef OptimizerMetricSnapshot = {
	var id:String;
	var count:Int;
};

private typedef OptimizerPlanReportSnapshot = {
	var schemaVersion:Int;
	var backendId:String;
	var contract:String;
	var familyStdPin:FamilyStdPinReportSnapshot;
	var executedPasses:Array<String>;
	var applied:Array<OptimizerMetricSnapshot>;
	var skipped:Array<OptimizerMetricSnapshot>;
	var appliedTotal:Int;
	var skippedTotal:Int;
	var cloneElisions:Int;
	var loopOptimizations:Int;
	var usedModuleCount:Int;
};

private typedef FamilyStdPinReportSnapshot = {
	var found:Bool;
	var pinFile:String;
	var name:String;
	var version:String;
	var source:String;
	var migrationMode:String;
};

/**
 * RustCompiler
 *
 * Emits Rust modules/crate files for the Haxe program.
 *
 * Architecture:
 * - Typed Haxe AST -> Rust AST (Builder-ish logic lives here for now)
 * - Rust AST -> string via RustASTPrinter (RustOutputIterator)
 * - Cargo.toml emitted as an extra file at compile end
 */
class RustCompiler extends GenericCompiler<RustFile, RustFile, RustExpr, RustFile, RustFile> {
	var didEmitMain:Bool = false;
	var crateName:String = "hx_app";
	var mainBaseType:Null<BaseType> = null;
	var mainClassKey:Null<String> = null;
	var cachedMainClass:Null<ClassType> = null;
	var cachedMainClassResolved:Bool = false;
	var currentClassKey:Null<String> = null;
	var currentClassName:Null<String> = null;
	var currentClassType:Null<ClassType> = null;
	var currentClassContext:Null<RustClassContext> = null;
	// When compiling an inherited method shim (base method body on a subclass), `this` dispatch should
	// use `currentClassType`, but `super` resolution should use the class that defined the body.
	var currentMethodOwnerType:Null<ClassType> = null;
	// The method currently being compiled (used for property accessor special-casing, e.g. `default,set` setters).
	var currentMethodField:Null<ClassField> = null;
	// Per-class compilation state: when a method body uses `super`, we synthesize a "super thunk"
	// method on the current class so `super.method(...)` can call the base implementation with a
	// `&RefCell<Current>` receiver.
	var currentNeededSuperThunks:Null<Map<String, {owner:ClassType, field:ClassField}>> = null;
	var extraRustSrcDir:Null<String> = null;
	var extraRustSrcFiles:Array<{module:String, fileName:String, fullPath:String}> = [];
	var classHasSubclass:Null<Map<String, Bool>> = null;
	var frameworkStdDir:Null<String> = null;
	var frameworkClassPathDir:Null<String> = null;
	var upstreamStdDirs:Array<String> = [];
	var frameworkRuntimeDir:Null<String> = null;
	var sourceModuleByCanonicalFile:Map<String, String> = [];
	var frameworkStdSourceFiles:Map<String, Bool> = [];
	var profile:RustProfile = Portable;
	// When inlining constructor `super(...)` bodies, we need to substitute base-ctor parameter locals.
	// Map is keyed by Haxe local name and returns a Rust expression to use in place of that local.
	var inlineLocalSubstitutions:Null<Map<String, RustExpr>> = null;
	var currentMutatedLocals:Null<Map<Int, Bool>> = null;
	// Rust function parameters are immutable by default; when Haxe assigns to an argument
	// (e.g. `s = ...` inside a helper), we shadow the parameter with `let mut s = s;`.
	// This stores the Rust argument idents (already snake_cased/uniqued).
	var currentMutatedArgs:Null<Array<String>> = null;
	var currentLocalReadCounts:Null<Map<Int, Int>> = null;
	var currentLocalRemainingReads:Null<Map<Int, Int>> = null;
	// `TThis` has no `TVar.id`, so its ownership-aware last-use accounting is tracked separately
	// from named locals. This is used only for transparent cast wrappers that would otherwise hide
	// `this` from the established direct-local clone policy.
	var currentThisReadCount:Null<Int> = null;
	var currentThisRemainingReads:Null<Int> = null;
	var currentClosureCapturedReusableLocals:Null<Map<Int, Bool>> = null;
	// Local ids that must be lowered through shared-cell storage (`crate::HxRef<T>`)
	// because they are mutated and captured by nested function values.
	var currentCapturedCellLocals:Null<Map<Int, Bool>> = null;
	// Per-function conservative alias closure for `hxrt::array::Array<T>` locals.
	// Used by loop lowering to keep borrowed-iteration fast paths semantics-safe.
	var currentArrayAliasClosures:Null<Map<Int, Map<Int, Bool>>> = null;
	var currentArgNames:Null<Map<String, String>> = null;
	var currentLocalNames:Null<Map<Int, String>> = null;
	var currentLocalUsed:Null<Map<String, Bool>> = null;
	var currentEnumParamBinds:Null<Map<String, String>> = null;
	var currentFunctionReturn:Null<Type> = null;
	var currentFunctionIsAsync:Bool = false;
	var currentFunctionContext:Null<RustFuncContext> = null;
	var warnedUnresolvedMonomorphPos:Map<String, Bool> = [];
	// Rust identifier to use for Haxe `this` (`TThis`) in the current function body.
	// - constructors: `"self_"` (a local `HxRef<T>`)
	// - instance methods/super thunks: `"__hx_this"` (materialized from `&HxRefCell<T>` via `self_ref()`)
	var currentThisIdent:Null<String> = null;
	var rustNamesByClass:Map<String, {fields:Map<String, String>, methods:Map<String, String>}> = [];
	var inCodeInjectionArg:Bool = false;
	var rustTestSpecs:Array<RustTestSpec> = [];
	// All typed module usage feeds runtime planning and facade consumption. User-only usage feeds
	// portable native-boundary reports so framework std internals do not look like app imports.
	var usedModulePaths:Map<String, Bool> = [];
	var userUsedModulePaths:Map<String, Bool> = [];
	var currentCompilationContext:Null<CompilationContext> = null;
	// Optimizer metrics recorded during lowering before `CompilationContext` exists.
	var pendingOptimizerAppliedById:Map<String, Int> = [];
	var pendingOptimizerSkippedById:Map<String, Int> = [];
	var metalIslandSnapshot:MetalIslandSnapshot = {modules: [], declarations: []};
	var physicalVarFieldCache:Map<String, Bool> = [];
	var cachedReflectionRegistryPlan:Null<ReflectionRegistryPlanData> = null;
	var cachedNeedsReflectionSupport:Null<Bool> = null;

	inline function wantsPreludeAliases():Bool {
		// Always emit stable `crate::HxRc` / `crate::HxRefCell` / `crate::HxRef` aliases so:
		// - generated code stays uniform across profiles
		// - the runtime can evolve the underlying representation (e.g. thread-safe heap)
		return true;
	}

	/**
		Returns whether the compile opts into the minimal runtime path (`-D rust_no_hxrt`).

		Why
		- `rust_no_hxrt` is a profile-level contract: project emission, prelude aliases, and pass
		  policy checks must branch consistently on one typed predicate.
		- Re-parsing the define at each callsite risks drift (for example, omitting Cargo dependency
		  emission but still copying the runtime crate).

		How
		- Keep the define lookup centralized here and route no-hxrt branches through this helper.
	**/
	inline function noHxrtEnabled():Bool {
		return Context.defined("rust_no_hxrt");
	}

	inline function rcBasePath():String {
		return wantsPreludeAliases() ? "crate::HxRc" : "std::rc::Rc";
	}

	inline function dynRefBasePath():String {
		return wantsPreludeAliases() ? "crate::HxDynRef" : "hxrt::cell::HxDynRef";
	}

	/**
		Builds validated path segments from compiler-owned identifiers.

		Why
		- Type lowering already knows module and nominal-type boundaries; joining them into one string
		  would throw away exactly the information structural IR is meant to preserve.

		What
		- Converts each already-separated identifier into one `RustPathSegment` and attaches optional
		  generic arguments only to the final segment.

		How
		- Callers must pass module/type names as separate array entries. Source metadata paths go through
		  `RustMetadataSyntax` instead.
	**/
	function rustPathSegments(names:Array<String>, ?lastArguments:Array<RustGenericArgument>):Array<RustPathSegment> {
		if (names == null || names.length == 0)
			throw "Compiler-owned Rust path requires at least one segment";
		var out:Array<RustPathSegment> = [];
		for (index in 0...names.length) {
			var isLast = index == names.length - 1;
			if (isLast && lastArguments != null && lastArguments.length > 0)
				out.push(RustPathSegment.angle(names[index], lastArguments));
			else
				out.push(RustPathSegment.plain(names[index]));
		}
		return out;
	}

	function rustTypeArguments(types:Array<RustType>):Array<RustGenericArgument> {
		return types == null ? [] : [for (type in types) GenericType(type)];
	}

	function rustRelativePath(names:Array<String>, ?arguments:Array<RustGenericArgument>):RustPath {
		return RustPath.relative(rustPathSegments(names, arguments));
	}

	function rustCratePath(names:Array<String>, ?arguments:Array<RustGenericArgument>):RustPath {
		return RustPath.cratePath(rustPathSegments(names, arguments));
	}

	/**
		Attaches structural generic arguments to a metadata-owned path's final segment.

		Why
		- Extern metadata supplies the nominal path, while Haxe's typed AST supplies the applied type
		  arguments. Rendering both halves and reparsing the result would make compiler-owned types
		  depend on printer syntax again.

		What
		- Rebuilds the immutable path with the same root and prefix segments, replacing only the final
		  plain segment with an angle-argument segment.

		How
		- Metadata text is parsed once by `RustMetadataSyntax`; typed arguments remain structural from
		  `toRustType` through the printer.
	**/
	function rustPathWithFinalArguments(path:RustPath, arguments:Array<RustGenericArgument>):RustPath {
		if (path == null)
			throw "Rust path cannot be null";
		if (arguments == null || arguments.length == 0)
			return path;
		var segments = [for (segment in path) segment];
		var finalSegment = segments[segments.length - 1];
		if (finalSegment.argumentStyle != PathArgumentsNone)
			throw "Extern Rust path already owns generic arguments";
		segments[segments.length - 1] = RustPathSegment.angleIdentifier(finalSegment.identifier, arguments);
		return switch (path.root) {
			case PathRelative: RustPath.relative(segments);
			case PathAbsolute: RustPath.absolute(segments);
			case PathCrate: RustPath.cratePath(segments);
			case PathSelfModule: RustPath.selfModule(segments);
			case PathSuper(depth): RustPath.superPath(depth, segments);
			case PathTypeSelf: RustPath.typeSelf(segments);
			case PathQualified(selfType, traitPath): RustPath.qualified(selfType, traitPath, segments);
		};
	}

	function rustRelativeType(names:Array<String>, ?typeArguments:Array<RustType>):RustType {
		return RNamed(rustRelativePath(names, rustTypeArguments(typeArguments)));
	}

	function rustCrateType(names:Array<String>, ?typeArguments:Array<RustType>):RustType {
		return RNamed(rustCratePath(names, rustTypeArguments(typeArguments)));
	}

	inline function rustNamedType(name:String):RustType {
		return RNamed(RustPath.single(name));
	}

	inline function rustOptionType(inner:RustType):RustType {
		return rustRelativeType(["Option"], [inner]);
	}

	inline function rustBoxType(inner:RustType):RustType {
		return rustRelativeType(["Box"], [inner]);
	}

	inline function rustHxRefType(inner:RustType):RustType {
		return rustCrateType(["HxRef"], [inner]);
	}

	function rustRcType(inner:RustType):RustType {
		return wantsPreludeAliases() ? rustCrateType(["HxRc"], [inner]) : rustRelativeType(["std", "rc", "Rc"], [inner]);
	}

	function rustDynRefType(inner:RustType):RustType {
		return wantsPreludeAliases() ? rustCrateType(["HxDynRef"], [inner]) : rustRelativeType(["hxrt", "cell", "HxDynRef"], [inner]);
	}

	function rustRefCellType(inner:RustType):RustType {
		return wantsPreludeAliases() ? rustCrateType(["HxRefCell"], [inner]) : rustRelativeType(["std", "cell", "RefCell"], [inner]);
	}

	function rustCrateNominalType(moduleSegments:Array<String>, typeName:String, ?typeArguments:Array<RustType>):RustType {
		var names = moduleSegments.copy();
		names.push(typeName);
		return rustCrateType(names, typeArguments);
	}

	function rustPathHasNames(path:RustPath, names:Array<String>):Bool {
		if (path == null || names == null || path.segmentCount != names.length)
			return false;
		for (index in 0...names.length) {
			if (path.segmentAt(index).identifier.name != names[index])
				return false;
		}
		return true;
	}

	function rustPathIsRelative(path:RustPath, names:Array<String>):Bool {
		return path != null && path.isRelative() && rustPathHasNames(path, names);
	}

	function rustPathIsCrate(path:RustPath, names:Array<String>):Bool {
		return path != null && switch (path.root) {
			case PathCrate: rustPathHasNames(path, names);
			case _: false;
		};
	}

	function rustTypeIsRelativePath(type:RustType, names:Array<String>):Bool {
		return switch (type) {
			case RNamed(path): rustPathIsRelative(path, names);
			case _: false;
		};
	}

	function rustTypeIsCratePath(type:RustType, names:Array<String>):Bool {
		return switch (type) {
			case RNamed(path): rustPathIsCrate(path, names);
			case _: false;
		};
	}

	inline function rustTypeIsHxRef(type:RustType):Bool {
		return rustTypeIsCratePath(type, ["HxRef"]);
	}

	inline function rustTypeIsArrayCarrier(type:RustType):Bool {
		return rustTypeIsRelativePath(type, ["hxrt", "array", "Array"]);
	}

	function rustTypeIsRcCarrier(type:RustType):Bool {
		return rustTypeIsCratePath(type, ["HxRc"]) || rustTypeIsRelativePath(type, ["std", "rc", "Rc"]);
	}

	function rustTypeIsDynRefCarrier(type:RustType):Bool {
		return rustTypeIsCratePath(type, ["HxDynRef"]) || rustTypeIsRelativePath(type, ["hxrt", "cell", "HxDynRef"]);
	}

	inline function rustTypeIsNullableStringCarrier(type:RustType):Bool {
		return rustTypeIsRelativePath(type, ["hxrt", "string", "HxString"]);
	}

	inline function rustTypeIsDynamicCarrier(type:RustType):Bool {
		return rustTypeIsRelativePath(type, ["hxrt", "dynamic", dynamicBoundaryTypeName()]);
	}

	inline function rustTypeIsRcTraitObject(type:RustType):Bool {
		return rustTypeIsRcCarrier(type) && rustTypeContainsTraitObject(type);
	}

	function rustTypeSingleGenericArgument(type:RustType):Null<RustType> {
		return switch (type) {
			case RNamed(path) if (path.segmentCount > 0): {
					var segment = path.segmentAt(path.segmentCount - 1);
					if (segment.genericArgumentCount != 1) {
						null;
					} else {
						switch (segment.genericArgumentAt(0)) {
							case GenericType(inner): inner;
							case _: null;
						}
					}
				}
			case _: null;
		};
	}

	function rustTypeContainsTraitObject(type:RustType):Bool {
		return switch (type) {
			case RTraitObject(_): true;
			case RNamed(path): {
					var found = false;
					for (segment in path) {
						for (index in 0...segment.genericArgumentCount) {
							switch (segment.genericArgumentAt(index)) {
								case GenericType(inner) if (rustTypeContainsTraitObject(inner)): found = true;
								case _:
							}
						}
					}
					found;
				}
			case RBorrow(inner, _, _): rustTypeContainsTraitObject(inner);
			case RTuple(elements): {
					var found = false;
					for (element in elements)
						if (rustTypeContainsTraitObject(element)) found = true;
					found;
				}
			case RSlice(element) | RArray(element, _): rustTypeContainsTraitObject(element);
			case RUnit | RBool | RI32 | RF64 | RString: false;
		};
	}

	function rustLifetimesEqual(left:RustLifetime, right:RustLifetime):Bool {
		if (left == null || right == null || left.kind != right.kind)
			return false;
		if (left.name == null || right.name == null)
			return left.name == null && right.name == null;
		return left.name.equals(right.name);
	}

	function rustConstArgumentsEqual(left:reflaxe.rust.ast.RustAST.RustConstArgument,
		right:reflaxe.rust.ast.RustAST.RustConstArgument):Bool {
		if (left == null || right == null || left.kind != right.kind)
			return false;
		return switch (left.kind) {
			case ConstInteger: left.integerDigits == right.integerDigits;
			case ConstBoolean: left.boolValue == right.boolValue;
			case ConstPath:
				left.pathValue != null && right.pathValue != null && rustPathsEqual(left.pathValue, right.pathValue);
		};
	}

	function rustGenericArgumentsEqual(left:RustGenericArgument, right:RustGenericArgument):Bool {
		return switch [left, right] {
			case [GenericType(leftType), GenericType(rightType)]: rustTypesEqual(leftType, rightType);
			case [GenericConst(leftConst), GenericConst(rightConst)]: rustConstArgumentsEqual(leftConst, rightConst);
			case [GenericLifetime(leftLifetime), GenericLifetime(rightLifetime)]: rustLifetimesEqual(leftLifetime, rightLifetime);
			case _: false;
		};
	}

	function rustPathSegmentsEqual(left:RustPathSegment, right:RustPathSegment):Bool {
		if (left == null || right == null || !left.identifier.equals(right.identifier) || left.argumentStyle != right.argumentStyle)
			return false;
		if (left.genericArgumentCount != right.genericArgumentCount || left.inputTypeCount != right.inputTypeCount)
			return false;
		for (index in 0...left.genericArgumentCount)
			if (!rustGenericArgumentsEqual(left.genericArgumentAt(index), right.genericArgumentAt(index))) return false;
		for (index in 0...left.inputTypeCount)
			if (!rustTypesEqual(left.inputTypeAt(index), right.inputTypeAt(index))) return false;
		if (left.outputType == null || right.outputType == null)
			return left.outputType == null && right.outputType == null;
		return rustTypesEqual(left.outputType, right.outputType);
	}

	function rustPathsEqual(left:RustPath, right:RustPath):Bool {
		if (left == null || right == null || left.segmentCount != right.segmentCount)
			return false;
		var rootsEqual = switch [left.root, right.root] {
			case [PathRelative, PathRelative]
				| [PathAbsolute, PathAbsolute]
				| [PathCrate, PathCrate]
				| [PathSelfModule, PathSelfModule]
				| [PathTypeSelf, PathTypeSelf]: true;
			case [PathSuper(leftDepth), PathSuper(rightDepth)]: leftDepth == rightDepth;
			case [PathQualified(leftSelf, leftTrait), PathQualified(rightSelf, rightTrait)]:
				rustTypesEqual(leftSelf, rightSelf)
					&& ((leftTrait == null && rightTrait == null)
						|| (leftTrait != null && rightTrait != null && rustPathsEqual(leftTrait, rightTrait)));
			case _: false;
		};
		if (!rootsEqual)
			return false;
		for (index in 0...left.segmentCount)
			if (!rustPathSegmentsEqual(left.segmentAt(index), right.segmentAt(index))) return false;
		return true;
	}

	function rustGenericBoundsEqual(left:RustGenericBound, right:RustGenericBound):Bool {
		return switch [left, right] {
			case [GenericTraitBound(leftPath, leftModifier), GenericTraitBound(rightPath, rightModifier)]:
				leftModifier == rightModifier && rustPathsEqual(leftPath, rightPath);
			case [GenericLifetimeBound(leftLifetime), GenericLifetimeBound(rightLifetime)]: rustLifetimesEqual(leftLifetime, rightLifetime);
			case _: false;
		};
	}

	function rustTraitObjectsEqual(left:RustTraitObject, right:RustTraitObject):Bool {
		if (left == null || right == null || left.count != right.count)
			return false;
		for (index in 0...left.count)
			if (!rustGenericBoundsEqual(left.at(index), right.at(index))) return false;
		return true;
	}

	function rustTypesEqual(left:RustType, right:RustType):Bool {
		return switch [left, right] {
			case [RUnit, RUnit] | [RBool, RBool] | [RI32, RI32] | [RF64, RF64] | [RString, RString]: true;
			case [RNamed(leftPath), RNamed(rightPath)]: rustPathsEqual(leftPath, rightPath);
			case [RBorrow(leftInner, leftMutable, leftLifetime), RBorrow(rightInner, rightMutable, rightLifetime)]:
				leftMutable == rightMutable
					&& rustTypesEqual(leftInner, rightInner)
					&& ((leftLifetime == null && rightLifetime == null)
						|| (leftLifetime != null && rightLifetime != null && rustLifetimesEqual(leftLifetime, rightLifetime)));
			case [RTuple(leftElements), RTuple(rightElements)]:
				if (leftElements.length != rightElements.length) {
					false;
				} else {
					var equal = true;
					for (index in 0...leftElements.length)
						if (!rustTypesEqual(leftElements[index], rightElements[index])) equal = false;
					equal;
				}
			case [RSlice(leftElement), RSlice(rightElement)]: rustTypesEqual(leftElement, rightElement);
			case [RArray(leftElement, leftLength), RArray(rightElement, rightLength)]:
				rustTypesEqual(leftElement, rightElement) && rustConstArgumentsEqual(leftLength, rightLength);
			case [RTraitObject(leftObject), RTraitObject(rightObject)]: rustTraitObjectsEqual(leftObject, rightObject);
			case _: false;
		};
	}

	/**
		Records a loop optimization metric in the shared compilation context.

		Why
		- `optimizer_plan.*` artifacts are the canonical CI evidence for optimization behavior.
		- Loop-lowering decisions in this compiler file (outside transform passes) still need
		  deterministic telemetry to avoid "silent" behavior changes.

		What
		- Appends counters under the `loop_optimizations.applied.*` metric namespace.

		How
		- Uses `CompilationContext.recordOptimizerApplied(...)` when context is available.
	**/
	inline function recordLoopOptimizationApplied(metricSuffix:String, count:Int = 1):Void {
		if (metricSuffix == null || metricSuffix.length == 0 || count <= 0)
			return;
		var metricId = "loop_optimizations.applied." + metricSuffix;
		if (currentCompilationContext != null) {
			currentCompilationContext.recordOptimizerApplied(metricId, count);
		} else {
			pendingOptimizerAppliedById.set(metricId, (pendingOptimizerAppliedById.exists(metricId) ? pendingOptimizerAppliedById.get(metricId) : 0) + count);
		}
	}

	/**
		Records why a loop optimization candidate was skipped.

		Why
		- Performance convergence work needs explicit "why not optimized" breadcrumbs for review/CI.
		- Skip counters make conservative safety guards visible instead of implicit.

		What
		- Appends counters under the `loop_optimizations.skipped.*` reason namespace.

		How
		- Uses `CompilationContext.recordOptimizerSkipped(...)` when context is available.
	**/
	inline function recordLoopOptimizationSkipped(reasonSuffix:String, count:Int = 1):Void {
		if (reasonSuffix == null || reasonSuffix.length == 0 || count <= 0)
			return;
		var reasonId = "loop_optimizations.skipped." + reasonSuffix;
		if (currentCompilationContext != null) {
			currentCompilationContext.recordOptimizerSkipped(reasonId, count);
		} else {
			pendingOptimizerSkippedById.set(reasonId, (pendingOptimizerSkippedById.exists(reasonId) ? pendingOptimizerSkippedById.get(reasonId) : 0) + count);
		}
	}

	inline function refCellBasePath():String {
		return wantsPreludeAliases() ? "crate::HxRefCell" : "std::cell::RefCell";
	}

	/**
		Returns crate-level prelude aliases for shared ownership / interior mutability handles.

		Why
		- Generated code references `crate::HxRc` / `crate::HxRefCell` / `crate::HxRef` uniformly.
		  This lets runtime representation evolve without touching every lowering callsite.
		- `-D rust_no_hxrt` must compile without any `hxrt` dependency, so aliases need a std-only
		  mapping in that mode.

		How
		- Default mode maps aliases to `hxrt::cell::*`.
		- no-hxrt mode maps aliases to `std::rc::Rc` + `std::cell::RefCell` equivalents so generated
		  borrow calls (`borrow` / `borrow_mut`) remain valid for the minimal subset.
	**/
	function preludeAliasLines():Array<String> {
		if (!wantsPreludeAliases())
			return ["type HxRef<T> = hxrt::cell::HxRef<T>;"];
		if (noHxrtEnabled()) {
			return [
				"type HxRc<T> = std::rc::Rc<T>;",
				"type HxDynRef<T: ?Sized> = std::rc::Rc<T>;",
				"type HxRefCell<T> = std::cell::RefCell<T>;",
				"type HxRef<T> = std::rc::Rc<std::cell::RefCell<T>>;"
			];
		}
		return [
			"type HxRc<T> = hxrt::cell::HxRc<T>;",
			"type HxDynRef<T: ?Sized> = hxrt::cell::HxDynRef<T>;",
			"type HxRefCell<T> = hxrt::cell::HxCell<T>;",
			"type HxRef<T> = hxrt::cell::HxRef<T>;"
		];
	}

	inline function useNullableStringRepresentation():Bool {
		if (Context.defined("rust_string_non_nullable"))
			return false;
		return Context.defined("rust_string_nullable");
	}

	inline function asyncEnabled():Bool {
		return Context.defined("rust_async");
	}

	inline function rustStringTypePath():String {
		return StringLowering.rustStringTypePath(useNullableStringRepresentation());
	}

	function rustStringType():RustType {
		return useNullableStringRepresentation() ? rustRelativeType(["hxrt", "string", "HxString"]) : RString;
	}

	inline function stringLiteralExpr(value:String):RustExpr {
		return StringLowering.stringLiteralExpr(useNullableStringRepresentation(), value);
	}

	inline function stringNullExpr():RustExpr {
		return StringLowering.stringNullExpr(useNullableStringRepresentation());
	}

	inline function wrapRustStringExpr(value:RustExpr):RustExpr {
		return StringLowering.wrapRustStringExpr(useNullableStringRepresentation(), value);
	}

	inline function stringNullDefaultValue():String {
		return StringLowering.stringNullDefaultValue(useNullableStringRepresentation());
	}

	/**
		Returns whether strict non-null `String` contract checks are active for this build.

		Why
		- `metal` defaults to Rust-owned non-null `String` representation.
		- In that contract, silently lowering `null` into a string value is semantically unsafe.

		How
		- Enabled only when compiling in `metal` with nullable-string mode disabled.
	**/
	inline function enforceMetalNonNullStringContract():Bool {
		return profile == Metal && !useNullableStringRepresentation();
	}

	/**
		Errors when source code provides `null` for a non-null `String` contract.

		Why
		- Prevents conflating `null` (absence) with an in-band string value.
		- Keeps metal string semantics explicit and analyzable.

		How
		- Called at typed `null` lowering boundaries where expected type is `String`.
		- Message includes migration guidance (`Null<String>` or `-D rust_string_nullable`).
	**/
	inline function failMetalStringNull(pos:haxe.macro.Expr.Position):Void {
		if (!enforceMetalNonNullStringContract())
			return;
		#if eval
		RustDiagnostic.error(RustDiagnosticId.ProfileContractError,
			"metal non-null string contract forbids `null` for `String`. Use `Null<String>` for nullable values, or enable `-D rust_string_nullable`.",
			pos);
		#end
	}

	/**
		Returns the canonical Haxe type name for the dynamic boundary carrier.

		Why
		- Centralizes the unavoidable `"Dynamic"` literal used by macro type lookups and core-type checks.
		- Keeps policy audits narrow: one boundary literal source, many typed callsites.

		How
		- This is intentionally reused by both Haxe-type lookups and Rust dynamic-path helpers.
	**/
	inline function dynamicBoundaryTypeName():String {
		return DynamicBoundary.typeName();
	}

	/**
		Returns the canonical Rust runtime path used for Haxe's dynamic carrier type.

		Why
		- Backend lowering touches this path in many places (`Null<T>` bridging, casts, monomorph fallbacks).
		- Repeating the raw string literal across the compiler makes audits noisy and brittle.

		How
		- Keep one canonical path string here and route all dynamic-path checks/constructors through it.
	**/
	inline function rustDynamicPath():String {
		return DynamicBoundary.runtimeNamespace();
	}

	function rustDynamicType():RustType {
		return rustRelativeType(["hxrt", "dynamic", dynamicBoundaryTypeName()]);
	}

	/**
		Returns the fully-qualified Rust path to `Dynamic::null`.

		Why
		- `Dynamic::null()` is the runtime null sentinel at unavoidable dynamic boundaries.
		- Centralizing the constructor path keeps boundary handling consistent and easy to review.
	**/
	inline function rustDynamicNullPath():String {
		return rustDynamicPath() + "::null";
	}

	inline function rustDynamicNullRaw():String {
		return rustDynamicNullPath() + "()";
	}

	inline function rustDynamicNullExpr():RustExpr {
		return ECall(EPath(rustDynamicNullPath()), []);
	}

	inline function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	public function new() {
		super();
	}

	public function createCompilationContext():CompilationContext {
		var buildContext = new RustBuildContext(crateName, profile, asyncEnabled(), useNullableStringRepresentation(),
			Context.defined("reflaxe_rust_strict_examples"), Context.defined("reflaxe_rust_strict"), metalContractHardError(), noHxrtEnabled(),
			metalIslandSnapshot.modules);
		var modulePaths = snapshotUsedModulePaths();
		var selection = selectHxrtFeatureSelection(modulePaths);
		var context = new CompilationContext(buildContext, modulePaths, selection.features, selection.manualFeatures, selection.useDefaultFeatures,
			selection.disableInference, selection.reasons);
		for (metricId => count in pendingOptimizerAppliedById)
			context.recordOptimizerApplied(metricId, count);
		for (reasonId => count in pendingOptimizerSkippedById)
			context.recordOptimizerSkipped(reasonId, count);
		return context;
	}

	inline function metalContractHardError():Bool {
		if (Context.defined("rust_metal_allow_fallback"))
			return false;
		if (Context.defined("rust_metal_contract_hard_error"))
			return true;
		return profile == Metal;
	}

	inline function hasMetalIslands():Bool {
		return metalIslandSnapshot != null && metalIslandSnapshot.modules != null && metalIslandSnapshot.modules.length > 0;
	}

	function snapshotUsedModulePaths():Array<String> {
		var out = [for (path in usedModulePaths.keys()) path];
		out.sort((a, b) -> compareStrings(a, b));
		return out;
	}

	function snapshotUserUsedModulePaths():Array<String> {
		var out = [for (path in userUsedModulePaths.keys()) path];
		out.sort((a, b) -> compareStrings(a, b));
		return out;
	}

	function collectTypeUsageFromCurrentModule(?sourceFile:String):Void {
		TypeUsageAnalyzer.collectInto(getTypeUsage(), usedModulePaths);
		if (sourceFile != null && sourceFile.length > 0 && isUserProjectFile(sourceFile))
			TypeUsageAnalyzer.collectInto(getTypeUsage(), userUsedModulePaths);
	}

	function selectHxrtFeatureSelection(modulePaths:Array<String>):HxrtFeatureSelection {
		if (noHxrtEnabled()) {
			return {
				mode: "no_hxrt",
				features: [],
				manualFeatures: [],
				useDefaultFeatures: false,
				disableInference: false,
				reasons: []
			};
		}
		return ProjectEmitter.selectHxrtFeatureSelection(modulePaths, Context.defined("rust_hxrt_default_features"),
			Context.definedValue("rust_hxrt_features"), Context.defined("rust_hxrt_no_feature_infer"));
	}

	function renderHxrtDependencyLine():String {
		if (noHxrtEnabled())
			return "";
		var modulePaths = snapshotUsedModulePaths();
		return ProjectEmitter.renderHxrtDependencyLine(modulePaths, Context.defined("rust_hxrt_default_features"), Context.definedValue("rust_hxrt_features"),
			Context.defined("rust_hxrt_no_feature_infer"));
	}

	/**
		Enforces profile-level boundary contracts before project emission.

		Why
		- Profiles (portable/metal) should have observable policy boundaries.
		- Metal needs actionable diagnostics when reflection/dynamic fallback compatibility
		  switches are used.

		How
		- Evaluates module usage and relevant defines through `ProfileContractAnalyzer`.
		- Emits warnings for soft violations and an aggregated compile error for hard violations.
	**/
	function enforceProfileContracts():Void {
		var diagnostics = analyzeProfileContracts();
		var modulePosIndex = profileContractModulePosIndex();
		#if eval
		for (warning in diagnostics.warnings)
			Context.warning(warning, profileContractDiagnosticPos(warning, modulePosIndex));
		if (diagnostics.errors.length > 0) {
			var first = diagnostics.errors[0];
			var remaining = diagnostics.errors.slice(1);
			var details = remaining.length == 0 ? first : first + "\nAdditional profile violations:\n" + remaining.map(msg -> "- " + msg).join("\n");
			Context.error(details, profileContractDiagnosticPos(first, modulePosIndex));
		}
		#end
	}

	/**
		Enforces source/typed-AST no-runtime eligibility before the final generated-code guard.

		Why
		- `NoHxrtPass` is still required, but it can only say generated Rust referenced `hxrt`.
		- `rust_no_hxrt` users need semantic blockers such as `dynamic`, `reflection`,
		  `anonymous_object`, or `platform_abstraction` before lowering gets that far.

		What
		- Runs `NoHxrtEligibilityAnalyzer` only when `-D rust_no_hxrt` is active.
		- Emits one deterministic diagnostic list using the same stable reason kinds as
		  `runtime_plan.*`.
		- Keeps current behavior conservative: `rust_no_hxrt` is still metal-only, and the existing
		  `NoHxrtPass` still validates the emitted Rust AST afterwards.
	**/
	function enforceNoHxrtEligibility():Void {
		if (!noHxrtEnabled())
			return;

		var result = NoHxrtEligibilityAnalyzer.analyze(userProjectModuleTypes(), snapshotUsedModulePaths(), Context.defined("rust_string_nullable"),
			Context.defined("rust_allow_unresolved_monomorph_dynamic"), Context.defined("rust_allow_unmapped_coretype_dynamic"));
		if (!result.blocked)
			return;

		#if eval
		var details = result.requirements.filter(entry -> entry.noHxrtBlocked).map(formatNoHxrtRequirement).join("\n");
		var pos = noHxrtEligibilityDiagnosticPos(result);
		RustDiagnostic.error(RustDiagnosticId.NoHxrtEligibility, "Rust no-hxrt eligibility violation(s):\n"
			+ details
			+
			"\n`-D rust_no_hxrt` still requires the source subset to avoid Haxe runtime semantics; remove `-D rust_no_hxrt` or refactor to admitted Rust-native/no-runtime surfaces.",
			pos);
		#end
	}

	static function formatNoHxrtRequirement(entry:RuntimeRequirementEntry):String {
		var surface = entry.surfaceId == null ? "" : ", surface `" + entry.surfaceId + "`";
		return "- reasonKind `"
			+ entry.reasonKind
			+ "` from "
			+ entry.sourceKind
			+ " `"
			+ entry.sourceModule
			+ "`"
			+ surface
			+ ": "
			+ entry.message;
	}

	function noHxrtEligibilityDiagnosticPos(result:NoHxrtEligibilityResult):haxe.macro.Expr.Position {
		#if eval
		var modulePosIndex = profileContractModulePosIndex();
		if (result != null && result.requirements != null) {
			for (entry in result.requirements) {
				if (entry.noHxrtBlocked) {
					var pos = profileContractDiagnosticPos(entry.sourceModule, modulePosIndex);
					if (pos != null)
						return pos;
				}
			}
		}
		#end
		return Context.currentPos();
	}

	function userProjectModuleTypes():Array<ModuleType> {
		var out:Array<ModuleType> = [];
		for (moduleType in Context.getAllModuleTypes()) {
			var sourceFile = moduleSourceFile(moduleType);
			if (sourceFile != null && sourceFile.length > 0 && isUserProjectFile(sourceFile))
				out.push(moduleType);
		}
		return out;
	}

	function profileContractModulePosIndex():Map<String, haxe.macro.Expr.Position> {
		var out:Map<String, haxe.macro.Expr.Position> = [];

		inline function add(module:String, pos:haxe.macro.Expr.Position, sourceFile:String):Void {
			if (module == null || module.length == 0 || pos == null)
				return;
			if (sourceFile == null || sourceFile.length == 0)
				return;
			// Contract diagnostics should point to user-authored source whenever possible.
			// Non-project modules (framework std overrides, upstream std, external libs) produce
			// confusing anchors that hide the real caller site in application code.
			if (!isUserProjectFile(sourceFile))
				return;
			if (!out.exists(module))
				out.set(module, pos);
		}

		for (moduleType in Context.getAllModuleTypes()) {
			var sourceFile = moduleSourceFile(moduleType);
			add(modulePathForModuleType(moduleType), moduleType.getPos(), sourceFile);
		}
		return out;
	}

	function profileContractDiagnosticPos(message:String, modulePosIndex:Map<String, haxe.macro.Expr.Position>):haxe.macro.Expr.Position {
		#if eval
		if (message != null && modulePosIndex != null) {
			var modules = [for (module in modulePosIndex.keys()) module];
			modules.sort((a, b) -> {
				if (a.length != b.length)
					return a.length > b.length ? -1 : 1;
				return a < b ? -1 : (a > b ? 1 : 0);
			});
			for (module in modules) {
				if (message.indexOf(module) != -1) {
					var pos = modulePosIndex.get(module);
					if (pos != null)
						return pos;
				}
			}

			// Deterministic user-source fallback when diagnostics mention framework/upstream module
			// paths (for example `Reflect`, `haxe.DynamicAccess`, `rust.Option`) rather than the
			// importing project module name.
			modules.sort(compareStrings);
			for (module in modules) {
				var fallbackPos = modulePosIndex.get(module);
				if (fallbackPos != null)
					return fallbackPos;
			}
		}
		#end
		return Context.currentPos();
	}

	function analyzeProfileContracts():ProfileContractDiagnostics {
		var nativeImportHits = collectPortableNativeImportHits();
		var diagnosticNativeImportHits = mergeStringSets(nativeImportHits, collectTypedNativeImportHitPaths());
		var diagnostics = ProfileContractAnalyzer.analyze(profile, snapshotUsedModulePaths(), Context.defined("rust_metal_allow_fallback"),
			Context.defined("rust_allow_unresolved_monomorph_dynamic"), Context.defined("rust_allow_unmapped_coretype_dynamic"),
			Context.defined("rust_string_nullable"), diagnosticNativeImportHits, Context.defined("rust_portable_native_import_strict"));
		if (currentCompilationContext != null) {
			currentCompilationContext.setProfileContractDiagnostics(diagnostics);
		}
		return diagnostics;
	}

	function collectTypedNativeImportHitPaths():Array<String> {
		var hits = NativeSurfaceUsageAnalyzer.collectTypedNativeImportHits(snapshotUserUsedModulePaths());
		return [for (hit in hits) hit.modulePath];
	}

	function mergeStringSets(a:Array<String>, b:Array<String>):Array<String> {
		var seen:Map<String, Bool> = [];
		var out:Array<String> = [];
		function add(values:Array<String>):Void {
			if (values == null)
				return;
			for (value in values) {
				if (value == null || value.length == 0 || seen.exists(value))
					continue;
				seen.set(value, true);
				out.push(value);
			}
		}
		add(a);
		add(b);
		out.sort(compareStrings);
		return out;
	}

	/**
		Collects user-authored native target imports used by portable-contract diagnostics.

		Why
		- Portable policy should warn/error when application code explicitly imports target-specific
		  module surfaces (for example `import rust.*` or `import cpp.*`).
		- Backend/framework internals can legitimately reference native modules; those must not trigger
		  user-facing portability warnings.

		How
		- Scans non-framework source files discovered in `Context.getAllModuleTypes()`.
		- Parses only explicit `import` / `using` statements.
		- Returns deterministic module-path hits (sorted + unique).
	**/
	function collectPortableNativeImportHits():Array<String> {
		var out:Array<String> = [];
		var seen:Map<String, Bool> = [];
		var scannedFiles:Map<String, Bool> = [];
		for (mt in Context.getAllModuleTypes()) {
			var file = moduleSourceFile(mt);
			if (file == null || file.length == 0)
				continue;
			if (scannedFiles.exists(file))
				continue;
			scannedFiles.set(file, true);
			if (!isUserProjectFile(file))
				continue;
			if (!FileSystem.exists(file))
				continue;
			var source = File.getContent(file);
			for (modulePath in collectNativeImportsFromSource(source)) {
				if (!seen.exists(modulePath)) {
					seen.set(modulePath, true);
					out.push(modulePath);
				}
			}
		}
		out.sort(compareStrings);
		return out;
	}

	/**
		Rejects application use of framework-owned implementation helper modules.

		Why
		- Haxe package naming alone does not make compiler, `hxrt`, or boundary-alias modules inaccessible.
		- Framework helpers must remain available to compiler macros and std overrides without becoming
		  application API merely because the installed Haxelib contains their declarations.

		What
		- Rejects user-authored references to every namespace owned by `InternalHelperBoundary`.
		- Covers imports, using declarations, fully qualified types, and fully qualified value references.

		How
		- Scans only user project source after removing comments and literal bodies.
		- Uses source spelling rather than followed typed aliases: public facades such as
		  `rust.concurrent.Task<T>` deliberately resolve to private `hxrt` handles internally and must not
		  be rejected when application source names only the public facade.
		- Anchors the stable diagnostic to the user module that contains the forbidden reference.
	**/
	function enforceInternalFrameworkHelperBoundary():Void {
		var hits:Array<{modulePath:String, pos:haxe.macro.Expr.Position}> = [];
		var seenFiles:Map<String, Bool> = [];
		var seenPaths:Map<String, Bool> = [];

		for (moduleType in Context.getAllModuleTypes()) {
			var file = moduleSourceFile(moduleType);
			if (file == null || file.length == 0 || seenFiles.exists(file) || !isUserProjectFile(file) || !FileSystem.exists(file))
				continue;
			seenFiles.set(file, true);
			for (modulePath in InternalHelperBoundary.collectDirectReferences(File.getContent(file))) {
				if (seenPaths.exists(modulePath))
					continue;
				seenPaths.set(modulePath, true);
				hits.push({modulePath: modulePath, pos: moduleType.getPos()});
			}
		}

		hits.sort((a, b) -> compareStrings(a.modulePath, b.modulePath));
		#if eval
		if (hits.length > 0) {
			var first = hits[0];
			RustDiagnostic.error(RustDiagnosticId.InternalHelperImport, "application code cannot import internal framework helper `"
				+ first.modulePath
				+ "`; use the documented Haxe/std or rust.* facade instead",
				first.pos);
		}
		#end
	}

	function collectNativeImportsFromSource(source:String):Array<String> {
		var out:Array<String> = [];
		if (source == null || source.length == 0)
			return out;
		var lines = source.split("\n");
		var importPattern = ~/^\s*(import|using)\s+([A-Za-z0-9_.]+)\s*;/;
		for (line in lines) {
			if (!importPattern.match(line))
				continue;
			var modulePath = importPattern.matched(2);
			if (modulePath == null || modulePath.length == 0)
				continue;
			if (!isNativeTargetImportPath(modulePath))
				continue;
			if (!out.contains(modulePath))
				out.push(modulePath);
		}
		out.sort(compareStrings);
		return out;
	}

	inline function isNativeTargetImportPath(modulePath:String):Bool {
		return NativeSurfaceUsageAnalyzer.isNativeTargetModulePath(modulePath);
	}

	function moduleSourceFile(mt:ModuleType):String {
		var pos = switch (mt) {
			case TClassDecl(c): c.get().pos;
			case TEnumDecl(e): e.get().pos;
			case TTypeDecl(t): t.get().pos;
			case TAbstract(a): a.get().pos;
		}
		return sourceFileForPosition(pos);
	}

	function sourceFileForPosition(pos:haxe.macro.Expr.Position):String {
		var info = Context.getPosInfos(pos);
		return info != null && info.file != null ? info.file : "";
	}

	/**
		Build source-position provenance from Haxe/Reflaxe typed module metadata.

		Why
		- Several policy checks receive only a `Position`, whose public data is a source file path.
		- Typed module declarations already know their semantic Haxe module path (`ModuleType.getModule()`),
		  so the compiler should reuse that instead of deriving module identity from filesystem spellings.

		What
		- Records `canonical source file -> Haxe module path`.
		- Records the subset of source files that are framework-owned target std/support modules.

		How
		- Uses Reflaxe's `ModuleTypeHelper` extension methods to read module identity.
		- Uses filesystem roots only for ownership (`framework std root`, `framework classpath root`,
		  optional upstream std roots), not for reconstructing module names.
	**/
	function buildSourceProvenanceIndex():Void {
		sourceModuleByCanonicalFile = [];
		frameworkStdSourceFiles = [];

		for (moduleType in Context.getAllModuleTypes()) {
			var sourceFile = moduleSourceFile(moduleType);
			if (sourceFile == null || sourceFile.length == 0)
				continue;

			var full = canonicalizePosFile(sourceFile);
			var modulePath = modulePathForModuleType(moduleType);
			if (modulePath != null && modulePath.length > 0 && !sourceModuleByCanonicalFile.exists(full))
				sourceModuleByCanonicalFile.set(full, modulePath);

			if (isFrameworkStdModuleSource(full, modulePath))
				frameworkStdSourceFiles.set(full, true);
		}
	}

	function modulePathForModuleType(moduleType:ModuleType):String {
		var modulePath = moduleType.getModule();
		if (modulePath != null && modulePath.length > 0)
			return modulePath;
		return moduleType.getPath();
	}

	/**
		Enforces Send/Sync boundary diagnostics for thread/task spawn closures.

		Why
		- Rust thread boundaries require captured values to satisfy `Send + Sync` and often `'static`.
		- Emitting diagnostics at Haxe source positions is more actionable than waiting for generated
		  Rust trait-bound failures.

		What
		- Runs `SendSyncAnalyzer` across typed modules.
		- Emits warnings by default.
		- Escalates diagnostics to compile errors when `-D rust_send_sync_strict` is set.

		How
		- Analyzer returns typed warnings/errors with original Haxe positions.
		- `rust_send_sync_strict` flips analyzer output into hard errors for regression/CI use.
	**/
	function enforceSendSyncContracts():Void {
		var strict = Context.defined("rust_send_sync_strict");
		var diagnostics = SendSyncAnalyzer.analyze(Context.getAllModuleTypes(), strict);
		#if eval
		for (warning in diagnostics.warnings)
			RustDiagnostic.warning(RustDiagnosticId.SendSyncWarning, "Rust concurrency contract: " + warning.message, warning.pos);
		for (error in diagnostics.errors)
			RustDiagnostic.error(RustDiagnosticId.SendSyncError, "Rust concurrency contract violation: " + error.message, error.pos);
		#end
	}

	/**
		Enforces alias-sensitive scoped borrow-region diagnostics.

		Why
		- Scoped borrow helper macros reject direct token escapes before expansion.
		- Typed aliases (`var alias = borrowed`) can otherwise escape through returns, field/static
		  storage, or stored closures and only fail later in generated Rust.

		What
		- Runs `BorrowRegionAnalyzer` across typed modules.
		- Emits hard errors because escaping a borrow-only value violates the scoped helper contract.

		How
		- The analyzer follows typed local aliases of `rust.Ref`, `rust.MutRef`, `rust.Slice`,
		  `rust.MutSlice`, and `rust.Str`.
		- Diagnostics are anchored to the Haxe expression that returns or stores the borrow alias.
	**/
	function enforceBorrowRegionContracts():Void {
		var diagnostics = BorrowRegionAnalyzer.analyze(Context.getAllModuleTypes(), shouldReportBorrowRegionDiagnostic);
		#if eval
		for (error in diagnostics.errors)
			RustDiagnostic.error(RustDiagnosticId.BorrowRegion, "Rust borrow region violation: " + error.message, error.pos);
		#end
	}

	function shouldReportBorrowRegionDiagnostic(pos:haxe.macro.Expr.Position):Bool {
		var info = Context.getPosInfos(pos);
		if (info == null || info.file == null)
			return true;
		return isUserProjectFile(info.file);
	}

	public function generateOutputIterator():Iterator<DataAndFileInfo<StringOrBytes>> {
		return new RustOutputIterator(this);
	}

	override public function onCompileStart() {
		// Reset cached class hierarchy info per compilation.
		classHasSubclass = null;
		frameworkStdDir = null;
		frameworkClassPathDir = null;
		upstreamStdDirs = [];
		frameworkRuntimeDir = null;
		sourceModuleByCanonicalFile = [];
		frameworkStdSourceFiles = [];
		warnedUnresolvedMonomorphPos = [];
		rustTestSpecs = [];
		usedModulePaths = [];
		userUsedModulePaths = [];
		currentCompilationContext = null;
		pendingOptimizerAppliedById = [];
		pendingOptimizerSkippedById = [];
		metalIslandSnapshot = {modules: [], declarations: []};

		// Profile selection and define validation are centralized to keep all feature gates consistent.
		profile = ProfileResolver.resolve();
		#if eval
		if (Context.defined("rust_debug_string_types")) {
			Context.warning("rust_debug_string_types active", Context.currentPos());
		}
		#end

		// Collect Cargo dependencies declared via `@:rustCargo(...)` metadata.
		CargoMetaRegistry.collectFromContext();

		// Collect extra Rust sources declared via metadata (framework code can bring its own modules).
		RustExtraSrcRegistry.collectFromContext();

		// Keep the M94 wrapper-facility spike from silently becoming product metadata.
		rejectReservedNativeWrapperMetadata();

		// Collect optional metal-lane declarations (`@:rustMetal` canonical, `@:haxeMetal` alias)
		// for strict island checks in portable mode.
		metalIslandSnapshot = MetalIslandAnalyzer.collect(Context.getAllModuleTypes());

		// Allow overriding crate name with -D rust_crate=<name>
		var v = Context.definedValue("rust_crate");
		if (v != null && v.length > 0)
			crateName = v;

		// Compute this library's framework-owned source roots. Haxe exposes source ownership to
		// macros as file paths, so emission and diagnostics need path-root classification to avoid
		// treating framework internals as user project code.
		try {
			var compilerPath = Context.resolvePath("reflaxe/rust/RustCompiler.hx");
			var rustDir = Path.directory(compilerPath); // .../src/reflaxe/rust
			var reflaxeDir = Path.directory(rustDir); // .../src/reflaxe
			var srcDir = Path.directory(reflaxeDir); // .../src
			var libraryRoot = Path.directory(srcDir); // .../
			frameworkStdDir = canonicalizePath(Path.normalize(Path.join([libraryRoot, "std"])));
			frameworkClassPathDir = canonicalizePath(srcDir);
			frameworkRuntimeDir = canonicalizePath(Path.normalize(Path.join([libraryRoot, "runtime", "hxrt"])));
		} catch (e:haxe.Exception) {
			frameworkStdDir = null;
			frameworkClassPathDir = null;
			frameworkRuntimeDir = null;
		}

		// Optional: emit upstream Haxe std modules (haxe/*) as Rust when referenced.
		//
		// This is intentionally opt-in: emitting the entire upstream std surface can increase output size
		// and compile time. When enabled, we treat any classpath entry that looks like a Haxe `std/` root
		// (has `haxe/` + `sys/`) as eligible for emission.
		if (Context.defined("rust_emit_upstream_std")) {
			try {
				var cwd = normalizePath(Sys.getCwd());
				for (cp in Context.getClassPath()) {
					if (cp == null || cp.length == 0)
						continue;
					var abs = cp;
					if (!Path.isAbsolute(abs))
						abs = Path.join([cwd, abs]);
					abs = normalizePath(abs);
					if (!FileSystem.exists(abs) || !FileSystem.isDirectory(abs))
						continue;
					var haxeDir = Path.join([abs, "haxe"]);
					var sysDir = Path.join([abs, "sys"]);
					if (!FileSystem.exists(haxeDir) || !FileSystem.isDirectory(haxeDir))
						continue;
					if (!FileSystem.exists(sysDir) || !FileSystem.isDirectory(sysDir))
						continue;
					// Avoid duplicates and avoid re-adding our own framework std root.
					if (frameworkStdDir != null && normalizePath(frameworkStdDir) == abs)
						continue;
					if (upstreamStdDirs.indexOf(abs) != -1)
						continue;
					upstreamStdDirs.push(abs);
				}
			} catch (e:haxe.Exception) {
				// best-effort
				upstreamStdDirs = [];
			}
		}

		buildSourceProvenanceIndex();

		// Collect Haxe-authored Rust test wrappers (`@:rustTest`) once per compile.
		collectRustTests();

		extraRustSrcFiles = [];
		var seenExtraRustModules = new Map<String, String>();
		function addExtraRustSrc(moduleName:String, fileName:String, fullPath:String, pos:haxe.macro.Expr.Position):Void {
			if (!isValidRustIdent(moduleName) || isRustKeyword(moduleName)) {
				#if eval
				Context.error("Invalid Rust module file name for extra Rust source: " + fileName, pos);
				#end
				return;
			}
			var existing = seenExtraRustModules.get(moduleName);
			if (existing != null) {
				if (existing != fullPath) {
					#if eval
					Context.error("Duplicate Rust extra module `" + moduleName + "` from:\n- " + existing + "\n- " + fullPath, pos);
					#end
				}
				return;
			}
			seenExtraRustModules.set(moduleName, fullPath);
			extraRustSrcFiles.push({
				module: moduleName,
				fileName: fileName,
				fullPath: fullPath
			});
		}

		// Metadata-driven extra Rust sources (preferred for framework code).
		for (f in RustExtraSrcRegistry.getFiles()) {
			addExtraRustSrc(f.module, f.fileName, f.fullPath, f.pos);
		}

		// Optional: copy extra Rust source files into the output crate's `src/`.
		// Configure with `-D rust_extra_src=path/to/dir` (relative to the `haxe` working directory).
		var extra = Context.definedValue("rust_extra_src");
		if (extra != null && extra.length > 0) {
			extraRustSrcDir = resolveToAbsolutePath(extra);
			if (!FileSystem.exists(extraRustSrcDir) || !FileSystem.isDirectory(extraRustSrcDir)) {
				#if eval
				Context.error("rust_extra_src must be a directory: " + extraRustSrcDir, Context.currentPos());
				#end
				extraRustSrcDir = null;
			} else {
				for (entry in FileSystem.readDirectory(extraRustSrcDir)) {
					if (!StringTools.endsWith(entry, ".rs"))
						continue;
					if (entry == "main.rs" || entry == "lib.rs")
						continue;

					var full = Path.join([extraRustSrcDir, entry]);
					if (FileSystem.isDirectory(full))
						continue;

					var moduleName = entry.substr(0, entry.length - 3);
					addExtraRustSrc(moduleName, entry, full, Context.currentPos());
				}
			}
		}

		extraRustSrcFiles.sort((a, b) -> compareStrings(a.module, b.module));
	}

	override public function onCompileEnd() {
		enforceInternalFrameworkHelperBoundary();
		enforceNoHxrtEligibility();
		enforceProfileContracts();
		enforceBorrowRegionContracts();
		enforceSendSyncContracts();

		if (!didEmitMain) {
			// No main class emitted; don't generate Cargo.toml.
			return;
		}

		// Rust project hygiene (SCM-friendly) for the generated crate.
		// Default: emit a minimal Cargo-style .gitignore; opt out with `-D rust_no_gitignore`.
		if (!Context.defined("rust_no_gitignore")) {
			var gitignore = ["/target", "**/*.rs.bk",].join("\n") + "\n";
			setExtraFile(OutputPath.fromStr(".gitignore"), gitignore);
		}

		// Emit any extra Rust sources requested by `-D rust_extra_src=<dir>`.
		for (f in extraRustSrcFiles) {
			var content = File.getContent(f.fullPath);
			if (!StringTools.endsWith(content, "\n"))
				content += "\n";
			setExtraFile(OutputPath.fromStr("src/" + f.fileName), content);
		}

		// Emit the bundled runtime crate (hxrt) alongside the generated crate unless this compile
		// explicitly opts into the minimal no-runtime path.
		emitRuntimeCrate();

		// Allow overriding the entire Cargo.toml with `-D rust_cargo_toml=path/to/Cargo.toml`.
		var cargoTomlPath = Context.definedValue("rust_cargo_toml");
		if (cargoTomlPath != null && cargoTomlPath.length > 0) {
			var full = resolveToAbsolutePath(cargoTomlPath);
			if (!FileSystem.exists(full)) {
				#if eval
				Context.error("rust_cargo_toml file not found: " + full, Context.currentPos());
				#end
			} else {
				var content = File.getContent(full);
				content = content.split("{{crate_name}}").join(crateName);
				if (!StringTools.endsWith(content, "\n"))
					content += "\n";
				setExtraFile(OutputPath.fromStr("Cargo.toml"), content);
				return;
			}
		}

		// Optional: append extra dependency lines into `[dependencies]` via `-D rust_cargo_deps_file=path`.
		var depsExtra = "";
		var depsFile = Context.definedValue("rust_cargo_deps_file");
		if (depsFile != null && depsFile.length > 0) {
			var full = resolveToAbsolutePath(depsFile);
			if (!FileSystem.exists(full)) {
				#if eval
				Context.error("rust_cargo_deps_file not found: " + full, Context.currentPos());
				#end
			} else {
				depsExtra = File.getContent(full);
				if (depsExtra.length > 0 && !StringTools.endsWith(depsExtra, "\n"))
					depsExtra += "\n";
			}
		} else {
			var depsInline = Context.definedValue("rust_cargo_deps");
			if (depsInline != null && depsInline.length > 0)
				depsExtra = depsInline + "\n";
		}

		var depLines:Array<String> = [];
		function appendDepLine(raw:Null<String>):Void {
			if (raw == null)
				return;
			var normalized = StringTools.trim(raw);
			if (normalized.length == 0)
				return;
			depLines.push(normalized);
		}
		if (!noHxrtEnabled()) {
			appendDepLine(renderHxrtDependencyLine());
		}
		appendDepLine(CargoMetaRegistry.renderDependencyLines());
		appendDepLine(depsExtra);
		var deps = depLines.join("\n");

		var cargo = [
			"[package]",
			'name = "' + crateName + '"',
			'version = "0.0.1"',
			'edition = "2021"',
			'rust-version = "' + RustToolchainPolicy.GENERATED_CARGO_RUST_VERSION + '"',
			'resolver = "' + RustToolchainPolicy.GENERATED_CARGO_RESOLVER_VERSION + '"',
			"",
			"[dependencies]",
			deps
		].join("\n");
		if (!StringTools.endsWith(cargo, "\n"))
			cargo += "\n";
		setExtraFile(OutputPath.fromStr("Cargo.toml"), cargo);
	}

	/**
		Emits one actionable metal-fallback summary warning per compile.

		Why
		- Per-module `ERaw` warnings are noisy for large programs and hide real action items.
		- Metal users need a concise report showing severity + hotspots.

		How
		- `MetalRestrictionsPass` records per-module raw-expression counts in `CompilationContext`.
		- This method aggregates those counts and emits one warning with top fallback modules.
	**/
	function emitMetalFallbackSummary():Void {
		if (profile != Metal)
			return;
		var ctx = currentCompilationContext;
		if (ctx == null)
			return;
		if (ctx.build.metalContractHardError)
			return;
		var total = ctx.metalRawExprTotalCount();
		if (total <= 0)
			return;

		var moduleCount = ctx.metalRawExprModuleCount();
		var top = ctx.topMetalRawExprModules(5);
		var topSummary = top.map(entry -> entry.module + ":" + entry.count).join(", ");
		#if eval
		Context.warning("Metal fallback active: generated output contains "
			+ total
			+ " raw Rust expression node(s) (`ERaw`) across "
			+ moduleCount
			+ " module(s). Top fallback modules: "
			+ topSummary
			+ ". Add typed lowering for these boundaries or remove `-D rust_metal_allow_fallback` to enforce metal-clean output.",
			Context.currentPos());
		#end
	}

	/**
		Computes and optionally reports metal viability scores/blockers for the current compile.

		Why
		- Metal cleanup work needs a deterministic signal that highlights which modules still rely on
		  fallback/dynamic/reflection boundaries.
		- The snapshot is reused by milestone 22.2 report emission; computation should happen once.

		How
		- Uses `MetalViabilityAnalyzer` with typed modules + recorded `ERaw` fallback counts.
		- Stores snapshot in `CompilationContext`.
		- Emits one opt-in summary warning when `-D rust_metal_viability_warn` is set.
	**/
	function analyzeMetalViability():Void {
		if (profile != Metal && !hasMetalIslands())
			return;
		var ctx = currentCompilationContext;
		if (ctx == null)
			return;

		var analyzeAsMetalProfile = profile == Metal;
		var snapshot = MetalViabilityAnalyzer.analyze(Context.getAllModuleTypes(), ctx.metalRawExprByModuleSnapshot(), {
			allowFallback: analyzeAsMetalProfile && Context.defined("rust_metal_allow_fallback"),
			allowUnresolvedMonomorphDynamic: analyzeAsMetalProfile && Context.defined("rust_allow_unresolved_monomorph_dynamic"),
			allowUnmappedCoreTypeDynamic: analyzeAsMetalProfile && Context.defined("rust_allow_unmapped_coretype_dynamic"),
			nullableStrings: analyzeAsMetalProfile && Context.defined("rust_string_nullable")
		});
		ctx.setMetalViability(snapshot);

		if (profile != Metal)
			return;
		if (!Context.defined("rust_metal_viability_warn"))
			return;

		var topModules = snapshot.modules.slice(0, 5).map(module -> module.module + ":" + module.score).join(", ");
		if (topModules.length == 0)
			topModules = "<none>";

		var globalBlockers = snapshot.globalBlockers.slice(0, 5).map(blocker -> blocker.id).join(", ");
		if (globalBlockers.length == 0)
			globalBlockers = "<none>";

		#if eval
		Context.warning("Metal viability: overall score " + snapshot.overallScore + "/100, modules=" + snapshot.moduleCount + ", ready="
			+ snapshot.moduleReadyCount + ", blockers=" + snapshot.blockerCount + ". Top modules: " + topModules + ". Global blockers: " + globalBlockers + ".",
			Context.currentPos());
		#end
	}

	/**
		Enforces strict `@:rustMetal` island contracts in portable profile.

		Why
		- Islands are an incremental migration path: users can lock specific modules to metal-clean
		  contracts without switching the entire project profile.
		- Violations must hard-error at the declaration site to keep island boundaries explicit.

		What
		- For each module declared via `@:rustMetal` (or `@:haxeMetal` alias), checks viability blockers.
		- Emits one compile error per violating island module with blocker categories/ids.

		How
		- Reuses `MetalViabilityAnalyzer` output from `analyzeMetalViability()`.
		- Maps island declarations to modules and reports at the first declaration position.
	**/
	function enforceMetalIslandContracts():Void {
		if (profile == Metal)
			return;
		if (!hasMetalIslands())
			return;

		var ctx = currentCompilationContext;
		if (ctx == null)
			return;
		var snapshot = ctx.getMetalViability();
		if (snapshot == null)
			return;

		var modulesByName:Map<String, MetalModuleViability> = [];
		for (module in snapshot.modules)
			modulesByName.set(module.module, module);

		var declarationsByModule:Map<String, Array<MetalIslandDeclaration>> = [];
		for (declaration in metalIslandSnapshot.declarations) {
			if (!declarationsByModule.exists(declaration.module))
				declarationsByModule.set(declaration.module, []);
			declarationsByModule.get(declaration.module).push(declaration);
		}

		#if eval
		for (module in metalIslandSnapshot.modules) {
			var moduleData = modulesByName.get(module);
			var declarations = declarationsByModule.exists(module) ? declarationsByModule.get(module) : [];
			var pos = declarations.length > 0 ? declarations[0].pos : Context.currentPos();
			var declarationSummary = declarations.length == 0 ? "`@:rustMetal`" : declarations.map(entry -> "`" + entry.source + "`").join(", ");

			if (moduleData == null) {
				RustDiagnostic.error(RustDiagnosticId.ProfileContractError, "Metal island violation in module `"
					+ module
					+ "` declared by "
					+ declarationSummary
					+ ": viability analyzer could not resolve this module. Keep `@:rustMetal` on emitted class/enum/typedef/abstract modules.",
					pos);
				continue;
			}

			if (moduleData.blockers.length == 0)
				continue;

			var blockers = moduleData.blockers.map(blocker -> blocker.category + "/" + blocker.id + "(x" + blocker.occurrences + ",w" + blocker.weight + ")")
				.join("; ");
			RustDiagnostic.error(RustDiagnosticId.ProfileContractError, "Metal island violation in module `"
				+ module
				+ "` declared by "
				+ declarationSummary
				+ ": "
				+ blockers
				+ ". Remove dynamic/reflection/raw fallback boundaries before marking this module as `@:rustMetal`.",
				pos);
		}
		#end
	}

	/**
		Emits deterministic metal viability report artifacts.

		Why
		- Milestone 22.2 requires stable report artifacts (`metal_report.json` + `metal_report.md`)
		  so CI/tools can diff viability progress without parsing compiler warnings.
		- The report must come from one typed snapshot source to avoid drift between warning text,
		  docs, and machine-readable output.

		What
		- Writes two files in the generated crate root:
		  - `metal_report.json` (machine-readable, deterministic order),
		  - `metal_report.md` (human-readable summary with actionable blockers).
		- Emission is opt-in via `-D rust_metal_viability_report` to keep default output minimal.

		How
		- Reuses `CompilationContext.getMetalViability()` snapshot created by `analyzeMetalViability()`.
		- Uses explicit typed serializers (no `Dynamic`/`Reflect`) to keep ordering stable and policy-safe.
	**/
	function emitMetalViabilityReports(outDir:String):Void {
		if (profile != Metal)
			return;
		if (!Context.defined("rust_metal_viability_report"))
			return;

		var ctx = currentCompilationContext;
		if (ctx == null)
			return;
		var snapshot = ctx.getMetalViability();
		if (snapshot == null)
			return;

		var jsonReportPath = Path.join([outDir, "metal_report.json"]);
		var markdownReportPath = Path.join([outDir, "metal_report.md"]);
		File.saveContent(jsonReportPath, renderMetalViabilityJson(snapshot));
		File.saveContent(markdownReportPath, renderMetalViabilityMarkdown(snapshot));
	}

	/**
		Emits deterministic contract-report artifacts.

		Why
		- Family-level policy checks need machine-readable artifacts; stderr-only diagnostics are hard
		  to diff and audit in CI across compilers.
		- The report must reflect the same typed diagnostics enforced during compilation.

		What
		- Writes `contract_report.json` and `contract_report.md` in the generated crate root.
		- Emission is opt-in via `-D rust_contract_report`.
		- Schema v6 includes the family-stdlib pin plus typed surface contracts (`consumedSurfaces`) and selected Rust
		  representation decisions (`nativeRepresentationPlan`) so portable facade lowering is
		  explicit evidence instead of hidden namespace inference.

		How
		- Reuses cached `ProfileContractDiagnostics` stored in `CompilationContext` by
		  `enforceProfileContracts()`.
		- Falls back to one typed analyzer run if no cached snapshot is present.
	**/
	function emitProfileContractReports(outDir:String):Void {
		if (!Context.defined("rust_contract_report"))
			return;

		var snapshot = buildProfileContractReportSnapshot();
		var jsonReportPath = Path.join([outDir, "contract_report.json"]);
		var markdownReportPath = Path.join([outDir, "contract_report.md"]);
		File.saveContent(jsonReportPath, renderProfileContractJson(snapshot));
		File.saveContent(markdownReportPath, renderProfileContractMarkdown(snapshot));
	}

	static inline var FAMILY_STD_PIN_REL_PATH = "family/family_std_pin.json";

	/**
		Builds a deterministic snapshot of the local `family_std_pin.json` state for report artifacts.

		Why
		- Reflaxe std adoption work depends on a pinned family contract snapshot.
		- CI reports should record which family pin metadata was visible during compilation.

		How
		- Searches upward from the current working directory for `family/family_std_pin.json`.
		- Parses only the minimal typed fields used by reports (`name`, `version`, `source`,
		  `migration_window.mode`).
		- On missing/invalid files, emits a deterministic `found=false` payload rather than
		  failing compilation.
	**/
	function buildFamilyStdPinReportSnapshot():FamilyStdPinReportSnapshot {
		var result:FamilyStdPinReportSnapshot = {
			found: false,
			pinFile: FAMILY_STD_PIN_REL_PATH,
			name: "",
			version: "",
			source: "",
			migrationMode: ""
		};

		var pinPath = locateFamilyStdPinPath();
		if (pinPath == null || !FileSystem.exists(pinPath))
			return result;

		try {
			var raw = File.getContent(pinPath);
			var parsed:Dynamic = haxe.Json.parse(raw);
			var root:haxe.DynamicAccess<Dynamic> = cast parsed;
			result.found = true;
			result.name = readDynamicStringField(root, "name");
			result.version = readDynamicStringField(root, "version");
			result.source = readDynamicStringField(root, "source");
			var migrationRaw = root.get("migration_window");
			if (migrationRaw != null) {
				var migration:haxe.DynamicAccess<Dynamic> = cast migrationRaw;
				result.migrationMode = readDynamicStringField(migration, "mode");
			}
		} catch (_:Dynamic) {
			// Keep reports deterministic and non-fatal when pin metadata is unavailable or malformed.
			return result;
		}

		return result;
	}

	static function readDynamicStringField(obj:haxe.DynamicAccess<Dynamic>, key:String):String {
		if (obj == null)
			return "";
		var value = obj.get(key);
		if (value == null)
			return "";
		return Std.string(value);
	}

	static function locateFamilyStdPinPath():Null<String> {
		var current = Path.normalize(Sys.getCwd());
		var guard = 0;
		while (guard < 20) {
			var candidate = Path.normalize(Path.join([current, FAMILY_STD_PIN_REL_PATH]));
			if (FileSystem.exists(candidate))
				return candidate;
			var parent = Path.normalize(Path.directory(current));
			if (parent == current)
				break;
			current = parent;
			guard++;
		}
		return null;
	}

	static function appendFamilyStdPinJson(lines:Array<String>, pin:FamilyStdPinReportSnapshot, indentLevel:Int, trailingComma:Bool):Void {
		var comma = trailingComma ? "," : "";
		lines.push(indent(indentLevel) + '"familyStdPin": {');
		lines.push(indent(indentLevel + 1) + '"found": ' + boolString(pin.found) + ",");
		lines.push(indent(indentLevel + 1) + '"pinFile": "' + jsonEscape(pin.pinFile) + '",');
		lines.push(indent(indentLevel + 1) + '"name": "' + jsonEscape(pin.name) + '",');
		lines.push(indent(indentLevel + 1) + '"version": "' + jsonEscape(pin.version) + '",');
		lines.push(indent(indentLevel + 1) + '"source": "' + jsonEscape(pin.source) + '",');
		lines.push(indent(indentLevel + 1) + '"migrationMode": "' + jsonEscape(pin.migrationMode) + '"');
		lines.push(indent(indentLevel) + "}" + comma);
	}

	static function appendFamilyStdPinMarkdown(lines:Array<String>, pin:FamilyStdPinReportSnapshot):Void {
		lines.push("- family std pin found: `" + boolLabel(pin.found) + "`");
		lines.push("- family std pin file: `" + pin.pinFile + "`");
		lines.push("- family std pin name: `" + (pin.name.length == 0 ? "<unset>" : pin.name) + "`");
		lines.push("- family std pin version: `" + (pin.version.length == 0 ? "<unset>" : pin.version) + "`");
		lines.push("- family std pin source: `" + (pin.source.length == 0 ? "<unset>" : pin.source) + "`");
		lines.push("- family std migration mode: `" + (pin.migrationMode.length == 0 ? "<unset>" : pin.migrationMode) + "`");
	}

	function buildProfileContractReportSnapshot():ProfileContractReportSnapshot {
		var diagnostics = currentCompilationContext != null ? currentCompilationContext.getProfileContractDiagnostics() : null;
		if (diagnostics == null)
			diagnostics = analyzeProfileContracts();
		var modulePaths = snapshotUsedModulePaths();
		var familyPin = buildFamilyStdPinReportSnapshot();

		var warnings = diagnostics.warnings.copy();
		warnings.sort(compareStrings);
		var errors = diagnostics.errors.copy();
		errors.sort(compareStrings);
		var nativeImportHits = collectPortableNativeImportHits();
		nativeImportHits.sort(compareStrings);
		var nativeImportHitsTyped = NativeSurfaceUsageAnalyzer.collectTypedNativeImportHits(snapshotUserUsedModulePaths());
		var consumedSurfaces = SurfaceContractRegistry.collectConsumed(modulePaths);
		var nativeRepresentationPlan = SurfaceContractRegistry.buildNativeRepresentationPlan(consumedSurfaces);

		return {
			schemaVersion: 6,
			backendId: "reflaxe.rust",
			contract: profile == Metal ? "metal" : "portable",
			familyStdPin: familyPin,
			strictBoundary: Context.defined("reflaxe_rust_strict"),
			strictExamples: Context.defined("reflaxe_rust_strict_examples"),
			metalFallbackAllowed: profile == Metal && Context.defined("rust_metal_allow_fallback"),
			metalContractHardError: metalContractHardError(),
			noHxrt: noHxrtEnabled(),
			asyncEnabled: asyncEnabled(),
			nullableStrings: useNullableStringRepresentation(),
			portableNativeImportStrict: Context.defined("rust_portable_native_import_strict"),
			portableNativeImportsDetected: nativeImportHits.length > 0 || nativeImportHitsTyped.length > 0,
			nativeImportHits: nativeImportHits,
			nativeImportHitsTyped: nativeImportHitsTyped,
			consumedSurfaces: consumedSurfaces,
			nativeRepresentationPlan: nativeRepresentationPlan,
			usedModuleCount: modulePaths.length,
			warnings: warnings,
			errors: errors
		};
	}

	static function renderProfileContractJson(snapshot:ProfileContractReportSnapshot):String {
		var lines:Array<String> = [];
		lines.push("{");
		lines.push('\t"schemaVersion": ' + snapshot.schemaVersion + ",");
		lines.push('\t"backendId": "' + jsonEscape(snapshot.backendId) + '",');
		lines.push('\t"contract": "' + jsonEscape(snapshot.contract) + '",');
		appendFamilyStdPinJson(lines, snapshot.familyStdPin, 1, true);
		lines.push('\t"strictBoundary": ' + boolString(snapshot.strictBoundary) + ",");
		lines.push('\t"strictExamples": ' + boolString(snapshot.strictExamples) + ",");
		lines.push('\t"metalFallbackAllowed": ' + boolString(snapshot.metalFallbackAllowed) + ",");
		lines.push('\t"metalContractHardError": ' + boolString(snapshot.metalContractHardError) + ",");
		lines.push('\t"noHxrt": ' + boolString(snapshot.noHxrt) + ",");
		lines.push('\t"asyncEnabled": ' + boolString(snapshot.asyncEnabled) + ",");
		lines.push('\t"nullableStrings": ' + boolString(snapshot.nullableStrings) + ",");
		lines.push('\t"portableNativeImportStrict": ' + boolString(snapshot.portableNativeImportStrict) + ",");
		lines.push('\t"portableNativeImportsDetected": ' + boolString(snapshot.portableNativeImportsDetected) + ",");
		lines.push('\t"nativeImportHits": [');
		appendJsonStringArray(lines, snapshot.nativeImportHits, 2);
		lines.push("\t],");
		lines.push('\t"nativeImportHitsTyped": [');
		appendTypedNativeImportHitsJson(lines, snapshot.nativeImportHitsTyped, 2);
		lines.push("\t],");
		lines.push('\t"consumedSurfaces": [');
		appendSurfaceContractsJson(lines, snapshot.consumedSurfaces, 2);
		lines.push("\t],");
		lines.push('\t"nativeRepresentationPlan": [');
		appendNativeRepresentationPlanJson(lines, snapshot.nativeRepresentationPlan, 2);
		lines.push("\t],");
		lines.push('\t"usedModuleCount": ' + snapshot.usedModuleCount + ",");
		lines.push('\t"warnings": [');
		appendJsonStringArray(lines, snapshot.warnings, 2);
		lines.push("\t],");
		lines.push('\t"errors": [');
		appendJsonStringArray(lines, snapshot.errors, 2);
		lines.push("\t]");
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function renderProfileContractMarkdown(snapshot:ProfileContractReportSnapshot):String {
		var lines:Array<String> = [];
		lines.push("# Contract Report");
		lines.push("");
		lines.push("- schema version: `" + snapshot.schemaVersion + "`");
		lines.push("- backend id: `" + snapshot.backendId + "`");
		lines.push("- contract: `" + snapshot.contract + "`");
		appendFamilyStdPinMarkdown(lines, snapshot.familyStdPin);
		lines.push("- strict boundary: `" + boolLabel(snapshot.strictBoundary) + "`");
		lines.push("- strict examples: `" + boolLabel(snapshot.strictExamples) + "`");
		lines.push("- metal fallback allowed: `" + boolLabel(snapshot.metalFallbackAllowed) + "`");
		lines.push("- metal contract hard error: `" + boolLabel(snapshot.metalContractHardError) + "`");
		lines.push("- no hxrt: `" + boolLabel(snapshot.noHxrt) + "`");
		lines.push("- async enabled: `" + boolLabel(snapshot.asyncEnabled) + "`");
		lines.push("- nullable strings: `" + boolLabel(snapshot.nullableStrings) + "`");
		lines.push("- portable native import strict: `" + boolLabel(snapshot.portableNativeImportStrict) + "`");
		lines.push("- portable native imports detected: `" + boolLabel(snapshot.portableNativeImportsDetected) + "`");
		lines.push("- used module count: `" + snapshot.usedModuleCount + "`");
		lines.push("");
		lines.push("## Native Import Hits");
		if (snapshot.nativeImportHits.length == 0) {
			lines.push("- none");
		} else {
			for (hit in snapshot.nativeImportHits)
				lines.push("- " + hit);
		}
		lines.push("");
		lines.push("## Typed Native Import Hits");
		if (snapshot.nativeImportHitsTyped.length == 0) {
			lines.push("- none");
		} else {
			for (hit in snapshot.nativeImportHitsTyped) {
				lines.push("- `"
					+ hit.modulePath
					+ "` (`"
					+ hit.surfaceKind
					+ "`, family: `"
					+ hit.nativeFamily
					+ "`, source: `"
					+ hit.sourceKind
					+ "`)");
			}
		}
		lines.push("");
		lines.push("## Consumed Surfaces");
		if (snapshot.consumedSurfaces.length == 0) {
			lines.push("- none");
		} else {
			for (surface in snapshot.consumedSurfaces) {
				lines.push("- `" + surface.surfaceId + "` (`" + surface.sourceContract + "` -> `" + surface.rustRepresentation + "`, no-hxrt eligible: `"
					+ boolLabel(surface.noHxrtEligible) + "`)");
			}
		}
		lines.push("");
		lines.push("## Native Representation Plan");
		if (snapshot.nativeRepresentationPlan.length == 0) {
			lines.push("- none");
		} else {
			for (decision in snapshot.nativeRepresentationPlan) {
				lines.push("- `" + decision.surfaceId + "` -> `" + decision.selectedRepresentation + "` (`" + decision.reason + "`)");
			}
		}
		lines.push("");
		lines.push("## Warnings");
		if (snapshot.warnings.length == 0) {
			lines.push("- none");
		} else {
			for (warning in snapshot.warnings)
				lines.push("- " + warning);
		}
		lines.push("");
		lines.push("## Errors");
		if (snapshot.errors.length == 0) {
			lines.push("- none");
		} else {
			for (error in snapshot.errors)
				lines.push("- " + error);
		}
		lines.push("");
		return lines.join("\n");
	}

	/**
		Emits deterministic runtime-plan report artifacts for `hxrt` feature selection.

		Why
		- Selective runtime slicing is policy-critical for family alignment and performance work.
		- CI/debug workflows need a stable artifact showing effective mode and selected feature set.

		What
		- Writes `runtime_plan.json` and `runtime_plan.md` in the generated crate root.
		- Emission is opt-in via `-D rust_runtime_plan_report`.
		- Schema v4 separates Cargo feature provenance (`reasons`) from semantic runtime
		  requirements (`runtimeRequirements` and `fallbackSummary`).

		How
		- Reuses the active `CompilationContext` feature snapshot when available.
		- Encodes effective mode (`no_hxrt`, `default_features`, `selective`) and toggle state.
	**/
	function emitHxrtPlanReports(outDir:String):Void {
		if (!Context.defined("rust_runtime_plan_report"))
			return;

		var snapshot = buildHxrtPlanReportSnapshot();
		var jsonReportPath = Path.join([outDir, "runtime_plan.json"]);
		var markdownReportPath = Path.join([outDir, "runtime_plan.md"]);
		File.saveContent(jsonReportPath, renderHxrtPlanJson(snapshot));
		File.saveContent(markdownReportPath, renderHxrtPlanMarkdown(snapshot));
	}

	function buildHxrtPlanReportSnapshot():HxrtPlanReportSnapshot {
		var modulePaths = snapshotUsedModulePaths();
		var noHxrt = noHxrtEnabled();
		var familyPin = buildFamilyStdPinReportSnapshot();
		var selection = currentCompilationContext != null ? {
			mode: noHxrt ? "no_hxrt" : (currentCompilationContext.hxrtUseDefaultFeatures ? "default_features" : "selective"),
			features: currentCompilationContext.inferredHxrtFeatures.copy(),
			manualFeatures: currentCompilationContext.manualHxrtFeatures.copy(),
			useDefaultFeatures: currentCompilationContext.hxrtUseDefaultFeatures,
			disableInference: currentCompilationContext.hxrtInferenceDisabled,
			reasons: currentCompilationContext.hxrtFeatureReasons.copy()
		} : selectHxrtFeatureSelection(modulePaths);

		var manualFeatures = selection.manualFeatures.copy();
		manualFeatures.sort(compareStrings);
		var selectedFeatures = selection.features.copy();
		selectedFeatures.sort(compareStrings);
		var reasons = selection.reasons.copy();
		reasons.sort((a, b) -> {
			var featureOrder = compareStrings(a.feature, b.feature);
			if (featureOrder != 0)
				return featureOrder;
			var kindOrder = compareStrings(a.sourceKind, b.sourceKind);
			if (kindOrder != 0)
				return kindOrder;
			return compareStrings(a.source, b.source);
		});

		var useDefaultFeatures = !noHxrt && selection.useDefaultFeatures;
		var mode = if (noHxrt) {
			"no_hxrt";
		} else if (useDefaultFeatures) {
			"default_features";
		} else {
			"selective";
		}
		var runtimeRequirements = RuntimeRequirementAnalyzer.collect(modulePaths, noHxrt, Context.defined("rust_string_nullable"),
			Context.defined("rust_allow_unresolved_monomorph_dynamic"), Context.defined("rust_allow_unmapped_coretype_dynamic"));
		var fallbackSummary = RuntimeRequirementAnalyzer.summarize(runtimeRequirements);

		return {
			schemaVersion: 4,
			backendId: "reflaxe.rust",
			runtimeId: "hxrt",
			contract: profile == Metal ? "metal" : "portable",
			familyStdPin: familyPin,
			mode: mode,
			noHxrt: noHxrt,
			useDefaultFeatures: useDefaultFeatures,
			inferenceDisabled: !noHxrt && selection.disableInference,
			manualFeatures: manualFeatures,
			selectedFeatures: selectedFeatures,
			reasons: reasons,
			runtimeRequirements: runtimeRequirements,
			fallbackSummary: fallbackSummary,
			usedModuleCount: modulePaths.length,
			hxrtDependencyLine: noHxrt ? "" : renderHxrtDependencyLine()
		};
	}

	static function renderHxrtPlanJson(snapshot:HxrtPlanReportSnapshot):String {
		var lines:Array<String> = [];
		lines.push("{");
		lines.push('\t"schemaVersion": ' + snapshot.schemaVersion + ",");
		lines.push('\t"backendId": "' + jsonEscape(snapshot.backendId) + '",');
		lines.push('\t"runtimeId": "' + jsonEscape(snapshot.runtimeId) + '",');
		lines.push('\t"contract": "' + jsonEscape(snapshot.contract) + '",');
		appendFamilyStdPinJson(lines, snapshot.familyStdPin, 1, true);
		lines.push('\t"mode": "' + jsonEscape(snapshot.mode) + '",');
		lines.push('\t"noHxrt": ' + boolString(snapshot.noHxrt) + ",");
		lines.push('\t"useDefaultFeatures": ' + boolString(snapshot.useDefaultFeatures) + ",");
		lines.push('\t"inferenceDisabled": ' + boolString(snapshot.inferenceDisabled) + ",");
		lines.push('\t"manualFeatures": [');
		appendJsonStringArray(lines, snapshot.manualFeatures, 2);
		lines.push("\t],");
		lines.push('\t"selectedFeatures": [');
		appendJsonStringArray(lines, snapshot.selectedFeatures, 2);
		lines.push("\t],");
		lines.push('\t"reasons": [');
		appendJsonHxrtReasons(lines, snapshot.reasons, 2);
		lines.push("\t],");
		lines.push('\t"runtimeRequirements": [');
		appendJsonRuntimeRequirements(lines, snapshot.runtimeRequirements, 2);
		lines.push("\t],");
		appendRuntimeFallbackSummaryJson(lines, snapshot.fallbackSummary, 1, true);
		lines.push('\t"usedModuleCount": ' + snapshot.usedModuleCount + ",");
		lines.push('\t"hxrtDependencyLine": "' + jsonEscape(snapshot.hxrtDependencyLine) + '"');
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function renderHxrtPlanMarkdown(snapshot:HxrtPlanReportSnapshot):String {
		var lines:Array<String> = [];
		lines.push("# Runtime Plan");
		lines.push("");
		lines.push("- schema version: `" + snapshot.schemaVersion + "`");
		lines.push("- backend id: `" + snapshot.backendId + "`");
		lines.push("- runtime id: `" + snapshot.runtimeId + "`");
		lines.push("- contract: `" + snapshot.contract + "`");
		appendFamilyStdPinMarkdown(lines, snapshot.familyStdPin);
		lines.push("- mode: `" + snapshot.mode + "`");
		lines.push("- no hxrt: `" + boolLabel(snapshot.noHxrt) + "`");
		lines.push("- default features: `" + boolLabel(snapshot.useDefaultFeatures) + "`");
		lines.push("- inference disabled: `" + boolLabel(snapshot.inferenceDisabled) + "`");
		lines.push("- used module count: `" + snapshot.usedModuleCount + "`");
		lines.push("");
		lines.push("## Manual features");
		if (snapshot.manualFeatures.length == 0) {
			lines.push("- none");
		} else {
			for (feature in snapshot.manualFeatures)
				lines.push("- `" + feature + "`");
		}
		lines.push("");
		lines.push("## Selected features");
		if (snapshot.selectedFeatures.length == 0) {
			lines.push("- none");
		} else {
			for (feature in snapshot.selectedFeatures)
				lines.push("- `" + feature + "`");
		}
		lines.push("");
		lines.push("## Feature reasons");
		if (snapshot.reasons.length == 0) {
			lines.push("- none");
		} else {
			for (reason in snapshot.reasons)
				lines.push("- `" + reason.feature + "` <= `" + reason.sourceKind + "`: `" + reason.source + "`");
		}
		lines.push("");
		lines.push("## Runtime requirements");
		if (snapshot.runtimeRequirements.length == 0) {
			lines.push("- none");
		} else {
			for (requirement in snapshot.runtimeRequirements) {
				var source = requirement.sourceModule.length == 0 ? requirement.sourceKind : requirement.sourceKind + ": " + requirement.sourceModule;
				lines.push("- `" + requirement.reasonKind + "` <= `" + source + "` (requires hxrt: `" + boolLabel(requirement.requiresHxrt)
					+ "`, blocks no-hxrt: `" + boolLabel(requirement.noHxrtBlocked) + "`) - " + requirement.message);
			}
		}
		lines.push("");
		lines.push("## Fallback summary");
		lines.push("- requires hxrt: `" + boolLabel(snapshot.fallbackSummary.requiresHxrt) + "`");
		lines.push("- blocked by no-hxrt: `" + boolLabel(snapshot.fallbackSummary.blockedByNoHxrt) + "`");
		if (snapshot.fallbackSummary.reasonKinds.length == 0) {
			lines.push("- reason kinds: none");
		} else {
			lines.push("- reason kinds: `" + snapshot.fallbackSummary.reasonKinds.join("`, `") + "`");
		}
		lines.push("");
		lines.push("## Dependency line");
		if (snapshot.hxrtDependencyLine.length == 0) {
			lines.push("- none (`rust_no_hxrt` mode)");
		} else {
			lines.push("```toml");
			lines.push(snapshot.hxrtDependencyLine);
			lines.push("```");
		}
		lines.push("");
		return lines.join("\n");
	}

	/**
		Emits deterministic optimizer-plan report artifacts.

		Why
		- Performance convergence work needs reproducible visibility into which optimization rewrites
		  ran and why candidates were skipped.
		- CI should diff typed artifacts, not parse warnings from stderr.

		What
		- Writes `optimizer_plan.json` and `optimizer_plan.md` in the generated crate root.
		- Emission is opt-in via `-D rust_optimizer_plan_report`.

		How
		- Reuses `CompilationContext` pass execution order + optimizer telemetry counters recorded
		  by AST passes (`CloneElisionPass`, `BorrowScopeTighteningPass`, etc).
	**/
	function emitOptimizerPlanReports(outDir:String):Void {
		if (!Context.defined("rust_optimizer_plan_report"))
			return;

		var snapshot = buildOptimizerPlanReportSnapshot();
		var jsonReportPath = Path.join([outDir, "optimizer_plan.json"]);
		var markdownReportPath = Path.join([outDir, "optimizer_plan.md"]);
		File.saveContent(jsonReportPath, renderOptimizerPlanJson(snapshot));
		File.saveContent(markdownReportPath, renderOptimizerPlanMarkdown(snapshot));
	}

	function buildOptimizerPlanReportSnapshot():OptimizerPlanReportSnapshot {
		var modulePaths = snapshotUsedModulePaths();
		var familyPin = buildFamilyStdPinReportSnapshot();
		var executedPasses:Array<String> = [];
		var applied:Array<OptimizerMetricSnapshot> = [];
		var skipped:Array<OptimizerMetricSnapshot> = [];

		if (currentCompilationContext != null) {
			executedPasses = currentCompilationContext.executedPasses.copy();
			applied = currentCompilationContext.optimizerAppliedSnapshot();
			skipped = currentCompilationContext.optimizerSkippedSnapshot();
		}

		return {
			schemaVersion: 2,
			backendId: "reflaxe.rust",
			contract: profile == Metal ? "metal" : "portable",
			familyStdPin: familyPin,
			executedPasses: executedPasses,
			applied: applied,
			skipped: skipped,
			appliedTotal: sumOptimizerMetrics(applied),
			skippedTotal: sumOptimizerMetrics(skipped),
			cloneElisions: sumOptimizerMetricsByPrefix(applied, "clone_elision.applied."),
			loopOptimizations: sumOptimizerMetricsByPrefix(applied, "loop_optimizations.applied."),
			usedModuleCount: modulePaths.length
		};
	}

	static function sumOptimizerMetrics(metrics:Array<OptimizerMetricSnapshot>):Int {
		var total = 0;
		for (metric in metrics)
			total += metric.count;
		return total;
	}

	static function sumOptimizerMetricsByPrefix(metrics:Array<OptimizerMetricSnapshot>, prefix:String):Int {
		var total = 0;
		for (metric in metrics) {
			if (StringTools.startsWith(metric.id, prefix))
				total += metric.count;
		}
		return total;
	}

	static function renderOptimizerPlanJson(snapshot:OptimizerPlanReportSnapshot):String {
		var lines:Array<String> = [];
		lines.push("{");
		lines.push('\t"schemaVersion": ' + snapshot.schemaVersion + ",");
		lines.push('\t"backendId": "' + jsonEscape(snapshot.backendId) + '",');
		lines.push('\t"contract": "' + jsonEscape(snapshot.contract) + '",');
		appendFamilyStdPinJson(lines, snapshot.familyStdPin, 1, true);
		lines.push('\t"executedPasses": [');
		appendJsonStringArray(lines, snapshot.executedPasses, 2);
		lines.push("\t],");
		lines.push('\t"applied": [');
		appendJsonOptimizerMetrics(lines, snapshot.applied, 2);
		lines.push("\t],");
		lines.push('\t"skipped": [');
		appendJsonOptimizerMetrics(lines, snapshot.skipped, 2);
		lines.push("\t],");
		lines.push('\t"appliedTotal": ' + snapshot.appliedTotal + ",");
		lines.push('\t"skippedTotal": ' + snapshot.skippedTotal + ",");
		lines.push('\t"cloneElisions": ' + snapshot.cloneElisions + ",");
		lines.push('\t"loopOptimizations": ' + snapshot.loopOptimizations + ",");
		lines.push('\t"usedModuleCount": ' + snapshot.usedModuleCount);
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function appendJsonOptimizerMetrics(lines:Array<String>, metrics:Array<OptimizerMetricSnapshot>, indentLevel:Int):Void {
		for (index in 0...metrics.length) {
			var metric = metrics[index];
			var comma = index == metrics.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"id": "' + jsonEscape(metric.id) + '",');
			lines.push(indent(indentLevel + 1) + '"count": ' + metric.count);
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function renderOptimizerPlanMarkdown(snapshot:OptimizerPlanReportSnapshot):String {
		var lines:Array<String> = [];
		lines.push("# Optimizer Plan");
		lines.push("");
		lines.push("- schema version: `" + snapshot.schemaVersion + "`");
		lines.push("- backend id: `" + snapshot.backendId + "`");
		lines.push("- contract: `" + snapshot.contract + "`");
		appendFamilyStdPinMarkdown(lines, snapshot.familyStdPin);
		lines.push("- used module count: `" + snapshot.usedModuleCount + "`");
		lines.push("- applied total: `" + snapshot.appliedTotal + "`");
		lines.push("- skipped total: `" + snapshot.skippedTotal + "`");
		lines.push("- clone elisions: `" + snapshot.cloneElisions + "`");
		lines.push("- loop optimizations: `" + snapshot.loopOptimizations + "`");
		lines.push("");
		lines.push("## Executed passes");
		if (snapshot.executedPasses.length == 0) {
			lines.push("- none");
		} else {
			for (passName in snapshot.executedPasses)
				lines.push("- `" + passName + "`");
		}
		lines.push("");
		lines.push("## Applied optimizations");
		if (snapshot.applied.length == 0) {
			lines.push("- none");
		} else {
			for (metric in snapshot.applied)
				lines.push("- `" + metric.id + "`: `" + metric.count + "`");
		}
		lines.push("");
		lines.push("## Skipped optimizations");
		if (snapshot.skipped.length == 0) {
			lines.push("- none");
		} else {
			for (metric in snapshot.skipped)
				lines.push("- `" + metric.id + "`: `" + metric.count + "`");
		}
		lines.push("");
		return lines.join("\n");
	}

	static function renderMetalViabilityJson(snapshot:MetalViabilitySnapshot):String {
		var lines:Array<String> = [];
		lines.push("{");
		lines.push('\t"schemaVersion": 1,');
		lines.push('\t"profile": "metal",');
		lines.push('\t"overallScore": ' + snapshot.overallScore + ",");
		lines.push('\t"moduleCount": ' + snapshot.moduleCount + ",");
		lines.push('\t"moduleReadyCount": ' + snapshot.moduleReadyCount + ",");
		lines.push('\t"blockerCount": ' + snapshot.blockerCount + ",");
		lines.push('\t"globalBlockers": [');
		appendJsonBlockers(lines, snapshot.globalBlockers, 2);
		lines.push("\t],");
		lines.push('\t"issueClasses": [');
		appendJsonIssueClasses(lines, snapshot.issueClasses, 2);
		lines.push("\t],");
		lines.push('\t"modules": [');
		appendJsonModules(lines, snapshot.modules, 2);
		lines.push("\t]");
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	static function appendJsonModules(lines:Array<String>, modules:Array<MetalModuleViability>, indentLevel:Int):Void {
		for (index in 0...modules.length) {
			var module = modules[index];
			var comma = index == modules.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"module": "' + jsonEscape(module.module) + '",');
			lines.push(indent(indentLevel + 1) + '"score": ' + module.score + ",");
			lines.push(indent(indentLevel + 1) + '"metalReady": ' + (module.metalReady ? "true" : "false") + ",");
			lines.push(indent(indentLevel + 1) + '"blockers": [');
			appendJsonBlockers(lines, module.blockers, indentLevel + 2);
			lines.push(indent(indentLevel + 1) + "]");
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function appendJsonBlockers(lines:Array<String>, blockers:Array<MetalViabilityBlocker>, indentLevel:Int):Void {
		for (index in 0...blockers.length) {
			var blocker = blockers[index];
			var comma = index == blockers.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"id": "' + jsonEscape(blocker.id) + '",');
			lines.push(indent(indentLevel + 1) + '"category": "' + jsonEscape(blocker.category) + '",');
			lines.push(indent(indentLevel + 1) + '"summary": "' + jsonEscape(blocker.summary) + '",');
			lines.push(indent(indentLevel + 1) + '"fix": "' + jsonEscape(blocker.fix) + '",');
			lines.push(indent(indentLevel + 1) + '"occurrences": ' + blocker.occurrences + ",");
			lines.push(indent(indentLevel + 1) + '"weight": ' + blocker.weight);
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function appendJsonIssueClasses(lines:Array<String>, issueClasses:Array<MetalIssueClassSummary>, indentLevel:Int):Void {
		for (index in 0...issueClasses.length) {
			var issueClass = issueClasses[index];
			var comma = index == issueClasses.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"id": "' + jsonEscape(issueClass.id) + '",');
			lines.push(indent(indentLevel + 1) + '"title": "' + jsonEscape(issueClass.title) + '",');
			lines.push(indent(indentLevel + 1) + '"recommendedAction": "' + jsonEscape(issueClass.recommendedAction) + '",');
			lines.push(indent(indentLevel + 1) + '"blockerCount": ' + issueClass.blockerCount + ",");
			lines.push(indent(indentLevel + 1) + '"occurrenceCount": ' + issueClass.occurrenceCount + ",");
			lines.push(indent(indentLevel + 1) + '"moduleCount": ' + issueClass.moduleCount + ",");
			lines.push(indent(indentLevel + 1) + '"totalWeight": ' + issueClass.totalWeight + ",");
			lines.push(indent(indentLevel + 1)
				+ '"modules": ['
				+ issueClass.modules.map(module -> '"' + jsonEscape(module) + '"').join(", ")
				+ "],");
			lines.push(indent(indentLevel + 1)
				+ '"blockerIds": ['
				+ issueClass.blockerIds.map(id -> '"' + jsonEscape(id) + '"').join(", ")
				+ "]");
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function renderMetalViabilityMarkdown(snapshot:MetalViabilitySnapshot):String {
		var lines:Array<String> = [];
		lines.push("# Metal Viability Report");
		lines.push("");
		lines.push("- profile: `metal`");
		lines.push("- overall score: `" + snapshot.overallScore + "/100`");
		lines.push("- modules: `" + snapshot.moduleCount + "`");
		lines.push("- metal-ready modules: `" + snapshot.moduleReadyCount + "`");
		lines.push("- blocker count: `" + snapshot.blockerCount + "`");
		lines.push("");
		lines.push("## Global blockers");
		if (snapshot.globalBlockers.length == 0) {
			lines.push("- none");
		} else {
			for (blocker in snapshot.globalBlockers)
				lines.push(renderMarkdownBlocker(blocker));
		}
		lines.push("");
		lines.push("## Issue classes");
		if (snapshot.issueClasses.length == 0) {
			lines.push("- none");
		} else {
			for (issueClass in snapshot.issueClasses) {
				lines.push("- `" + issueClass.id + "` (" + issueClass.title + ") blockers=`" + issueClass.blockerCount + "` occurrences=`"
					+ issueClass.occurrenceCount + "` modules=`" + issueClass.moduleCount + "` weight=`" + issueClass.totalWeight + "` action: "
					+ issueClass.recommendedAction);
				lines.push("-   blockers: " + issueClass.blockerIds.map(id -> "`" + id + "`").join(", "));
				lines.push("-   modules: " + issueClass.modules.map(module -> "`" + module + "`").join(", "));
			}
		}
		lines.push("");
		lines.push("## Modules");
		if (snapshot.modules.length == 0) {
			lines.push("- none");
			lines.push("");
		} else {
			for (module in snapshot.modules) {
				lines.push("### `" + module.module + "`");
				lines.push("- score: `" + module.score + "/100`");
				lines.push("- metal-ready: `" + (module.metalReady ? "yes" : "no") + "`");
				if (module.blockers.length == 0) {
					lines.push("- blockers: none");
				} else {
					lines.push("- blockers:");
					for (blocker in module.blockers)
						lines.push(renderMarkdownBlocker(blocker));
				}
				lines.push("");
			}
		}
		return lines.join("\n");
	}

	static inline function renderMarkdownBlocker(blocker:MetalViabilityBlocker):String {
		return "- `" + blocker.category + "/" + blocker.id + "` occurrences=`" + blocker.occurrences + "` weight=`" + blocker.weight + "`: "
			+ blocker.summary + " Fix: " + blocker.fix;
	}

	static function appendJsonStringArray(lines:Array<String>, values:Array<String>, indentLevel:Int):Void {
		for (index in 0...values.length) {
			var comma = index == values.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + '"' + jsonEscape(values[index]) + '"' + comma);
		}
	}

	static function appendTypedNativeImportHitsJson(lines:Array<String>, hits:Array<TypedNativeImportHit>, indentLevel:Int):Void {
		for (index in 0...hits.length) {
			var hit = hits[index];
			var comma = index == hits.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"modulePath": "' + jsonEscape(hit.modulePath) + '",');
			lines.push(indent(indentLevel + 1) + '"nativeFamily": "' + jsonEscape(hit.nativeFamily) + '",');
			lines.push(indent(indentLevel + 1) + '"surfaceKind": "' + jsonEscape(hit.surfaceKind) + '",');
			lines.push(indent(indentLevel + 1) + '"sourceKind": "' + jsonEscape(hit.sourceKind) + '"');
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function appendJsonHxrtReasons(lines:Array<String>, reasons:Array<HxrtFeatureReason>, indentLevel:Int):Void {
		for (index in 0...reasons.length) {
			var reason = reasons[index];
			var comma = index == reasons.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"feature": "' + jsonEscape(reason.feature) + '",');
			lines.push(indent(indentLevel + 1) + '"sourceKind": "' + jsonEscape(reason.sourceKind) + '",');
			lines.push(indent(indentLevel + 1) + '"source": "' + jsonEscape(reason.source) + '"');
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function appendJsonRuntimeRequirements(lines:Array<String>, requirements:Array<RuntimeRequirementEntry>, indentLevel:Int):Void {
		for (index in 0...requirements.length) {
			var requirement = requirements[index];
			var comma = index == requirements.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"reasonKind": "' + jsonEscape(requirement.reasonKind) + '",');
			lines.push(indent(indentLevel + 1) + '"sourceKind": "' + jsonEscape(requirement.sourceKind) + '",');
			lines.push(indent(indentLevel + 1) + '"sourceModule": "' + jsonEscape(requirement.sourceModule) + '",');
			lines.push(indent(indentLevel + 1) + '"sourceSpan": "' + jsonEscape(requirement.sourceSpan) + '",');
			lines.push(indent(indentLevel + 1) + '"surfaceId": ' + jsonNullableString(requirement.surfaceId) + ",");
			lines.push(indent(indentLevel + 1) + '"requiresHxrt": ' + boolString(requirement.requiresHxrt) + ",");
			lines.push(indent(indentLevel + 1) + '"noHxrtBlocked": ' + boolString(requirement.noHxrtBlocked) + ",");
			lines.push(indent(indentLevel + 1) + '"message": "' + jsonEscape(requirement.message) + '"');
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function appendRuntimeFallbackSummaryJson(lines:Array<String>, summary:RuntimeFallbackSummary, indentLevel:Int, trailingComma:Bool):Void {
		var comma = trailingComma ? "," : "";
		lines.push(indent(indentLevel) + '"fallbackSummary": {');
		lines.push(indent(indentLevel + 1) + '"requiresHxrt": ' + boolString(summary.requiresHxrt) + ",");
		lines.push(indent(indentLevel + 1) + '"blockedByNoHxrt": ' + boolString(summary.blockedByNoHxrt) + ",");
		lines.push(indent(indentLevel + 1) + '"reasonKinds": [');
		appendJsonStringArray(lines, summary.reasonKinds, indentLevel + 2);
		lines.push(indent(indentLevel + 1) + "]");
		lines.push(indent(indentLevel) + "}" + comma);
	}

	static function appendSurfaceContractsJson(lines:Array<String>, surfaces:Array<SurfaceContract>, indentLevel:Int):Void {
		for (index in 0...surfaces.length) {
			var surface = surfaces[index];
			var comma = index == surfaces.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"surfaceId": "' + jsonEscape(surface.surfaceId) + '",');
			lines.push(indent(indentLevel + 1) + '"modulePath": "' + jsonEscape(surface.modulePath) + '",');
			lines.push(indent(indentLevel + 1) + '"sourceContract": "' + jsonEscape(surface.sourceContract) + '",');
			lines.push(indent(indentLevel + 1) + '"facadeVersion": ' + surface.facadeVersion + ",");
			lines.push(indent(indentLevel + 1) + '"portableSemantics": "' + jsonEscape(surface.portableSemantics) + '",');
			lines.push(indent(indentLevel + 1) + '"rustRepresentation": "' + jsonEscape(surface.rustRepresentation) + '",');
			lines.push(indent(indentLevel + 1) + '"backendSpecializationAllowed": ' + boolString(surface.backendSpecializationAllowed) + ",");
			lines.push(indent(indentLevel + 1) + '"requiresRustImport": ' + boolString(surface.requiresRustImport) + ",");
			lines.push(indent(indentLevel + 1) + '"noHxrtEligible": ' + boolString(surface.noHxrtEligible) + ",");
			lines.push(indent(indentLevel + 1) + '"fallbackPolicy": "' + jsonEscape(surface.fallbackPolicy) + '"');
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static function appendNativeRepresentationPlanJson(lines:Array<String>, decisions:Array<NativeRepresentationDecision>, indentLevel:Int):Void {
		for (index in 0...decisions.length) {
			var decision = decisions[index];
			var comma = index == decisions.length - 1 ? "" : ",";
			lines.push(indent(indentLevel) + "{");
			lines.push(indent(indentLevel + 1) + '"surfaceId": "' + jsonEscape(decision.surfaceId) + '",');
			lines.push(indent(indentLevel + 1) + '"selectedRepresentation": "' + jsonEscape(decision.selectedRepresentation) + '",');
			lines.push(indent(indentLevel + 1) + '"reason": "' + jsonEscape(decision.reason) + '"');
			lines.push(indent(indentLevel) + "}" + comma);
		}
	}

	static inline function boolString(value:Bool):String {
		return value ? "true" : "false";
	}

	static inline function boolLabel(value:Bool):String {
		return value ? "yes" : "no";
	}

	static function jsonEscape(value:String):String {
		if (value == null)
			return "";
		var buf = new StringBuf();
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			switch (code) {
				case 8:
					buf.add("\\b");
				case 9:
					buf.add("\\t");
				case 10:
					buf.add("\\n");
				case 12:
					buf.add("\\f");
				case 13:
					buf.add("\\r");
				case 34:
					buf.add("\\\"");
				case 92:
					buf.add("\\\\");
				default:
					if (code < 32) {
						buf.add("\\u");
						buf.add(StringTools.hex(code, 4).toLowerCase());
					} else {
						buf.addChar(code);
					}
			}
		}
		return buf.toString();
	}

	static function jsonNullableString(value:Null<String>):String {
		return value == null ? "null" : '"' + jsonEscape(value) + '"';
	}

	static inline function indent(level:Int):String {
		var buf = new StringBuf();
		for (_ in 0...level)
			buf.add("\t");
		return buf.toString();
	}

	function emitRuntimeCrate():Void {
		if (noHxrtEnabled())
			return;
		if (frameworkRuntimeDir == null)
			return;

		var root = normalizePath(frameworkRuntimeDir);
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root))
			return;

		function walk(relDir:String):Void {
			var dirPath = relDir == "" ? root : normalizePath(Path.join([root, relDir]));
			for (entry in FileSystem.readDirectory(dirPath)) {
				// Keep generated output lean: the bundled runtime is a dependency, not a dev workspace.
				// Exclude build artifacts and dev-only folders (tests/benches/examples).
				if (entry == "target" || entry == "Cargo.lock" || entry == "tests" || entry == "benches" || entry == "examples")
					continue;
				var full = normalizePath(Path.join([dirPath, entry]));
				var rel = relDir == "" ? entry : normalizePath(Path.join([relDir, entry]));
				if (FileSystem.isDirectory(full)) {
					walk(rel);
				} else {
					var content = File.getContent(full);
					if (!StringTools.endsWith(content, "\n"))
						content += "\n";
					setExtraFile(OutputPath.fromStr("hxrt/" + rel), content);
				}
			}
		}

		walk("");
	}

	public function compileClassImpl(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Null<RustFile> {
		collectTypeUsageFromCurrentModule(sourceFileForPosition(classType.pos));
		enforceNoHxrtEligibility();

		var isMain = isMainClass(classType);
		if (!shouldEmitClass(classType, isMain))
			return null;

		// Ensure this lands at <rust_output>/src/main.rs for main, or the configured generated
		// module layout for non-main classes.
		if (isMain) {
			setOutputFileDir("src");
			setOutputFileName("main");
			didEmitMain = true;
			mainBaseType = classType;
			mainClassKey = classKey(classType);
		} else {
			setOutputFileDir(rustOutputDirForClass(classType));
			setOutputFileName(rustModuleFileStemForClass(classType));
		}

		var classKeyValue = classKey(classType);
		currentClassKey = classKeyValue;
		currentClassName = classType.name;
		currentClassType = classType;
		currentClassContext = new RustClassContext(classKeyValue, rustModuleNameForClass(classType), rustTypeNameForClass(classType));
		currentNeededSuperThunks = [];
		var rustSelfType = rustTypeNameForClass(classType);
		var classGenericDecls = rustGenericDeclsForClass(classType);
		var rustSelfTypeInst = rustClassTypeInst(classType);

		// Inheritance: methods are not physically inherited in Rust, so we synthesize instance methods
		// on subclasses for any base methods that have bodies but are not overridden.
		//
		// This ensures:
		// - concrete calls on a subclass type can resolve inherited methods (`Sub::method(...)`)
		// - base trait impls for subclasses can delegate to real methods (no `todo!()` stubs)
		var inheritedInstanceMethods:Array<{owner:ClassType, f:ClassFuncData}> = collectInheritedInstanceMethodShims(classType, funcFields);
		var effectiveFuncFields:Array<ClassFuncData> = funcFields.concat([for (x in inheritedInstanceMethods) x.f]);
		var inheritedOwnerById:Map<String, ClassType> = [];
		for (x in inheritedInstanceMethods)
			inheritedOwnerById.set(x.f.id, x.owner);

		var items:Array<RustItem> = [];
		items.push(RRaw(RustRawCode.compilerGenerated("// Generated by reflaxe.rust", RawGeneratedFileMarker)));

		function emitStaticStorageItems():Void {
			// --------------------------------------------------------------------
			// Static variable backing store (crate-local)
			//
			// Haxe `static var` values are mutable globals. Rust has no mutable module-level
			// variables without synchronization, so we model each static var as:
			//
			// - `static ONCE: OnceLock<HxCell<T>>`
			// - `__hx_static_cell_*()` to init (once) and return the cell
			// - `__hx_static_get_*()` / `__hx_static_set_*()` helpers for reads/writes
			//
			// This keeps initialization lazy and thread-safe (important for `sys.thread.*`).
			// Literal read-only static finals may be inlined at read sites; mutable/static-var fields
			// still use this storage path.
			// --------------------------------------------------------------------
			var emittedStaticStorage:Map<String, Bool> = [];
			function staticStorageKey(cf:ClassField):String {
				return cf.getHaxeName();
			}
			function emitStaticStorage(cf:ClassField, initExpr:Null<TypedExpr>):Void {
				var key = staticStorageKey(cf);
				if (emittedStaticStorage.exists(key))
					return;
				emittedStaticStorage.set(key, true);

				var rustName = rustMethodName(classType, cf);
				var tyStr = rustTypeToString(toRustType(cf.type, cf.pos));

				var initStr = if (initExpr != null) {
					var compiled = withFunctionContext(initExpr, [], cf.type, () -> {
						var ex = compileExpr(initExpr);
						coerceExprToExpected(ex, initExpr, cf.type);
					});
					reflaxe.rust.ast.RustASTPrinter.printExprForInjection(compiled);
				} else {
					defaultValueForType(cf.type, cf.pos);
				};

				var storage = "__HX_STATIC_" + rustName.toUpperCase();
				var cellFn = rustStaticVarHelperName("__hx_static_cell", rustName);
				var getFn = rustStaticVarHelperName("__hx_static_get", rustName);
				var setFn = rustStaticVarHelperName("__hx_static_set", rustName);

				var lines:Array<String> = [];
				lines.push("static " + storage + ": std::sync::OnceLock<hxrt::cell::HxCell<" + tyStr + ">> = std::sync::OnceLock::new();");
				lines.push("fn " + cellFn + "() -> &'static hxrt::cell::HxCell<" + tyStr + "> {");
				lines.push("\t" + storage + ".get_or_init(|| hxrt::cell::HxCell::new(" + initStr + "))");
				lines.push("}");
				lines.push("pub(crate) fn " + getFn + "() -> " + tyStr + " {");
				lines.push("\t" + cellFn + "().borrow().clone()");
				lines.push("}");
				lines.push("pub(crate) fn " + setFn + "(value: " + tyStr + ") {");
				lines.push("\t*" + cellFn + "().borrow_mut() = value;");
				lines.push("}");

				items.push(RRaw(RustRawCode.compilerAt(lines.join("\n"), RawStaticStorage, cf.pos)));
			}

			if (varFields != null) {
				for (varData in varFields) {
					if (!varData.isStatic)
						continue;

					var cf = varData.field;
					if (staticReadOnlyConstantExpr(cf) != null)
						continue;

					var initExpr:Null<TypedExpr> = null;
					try
						initExpr = cf.expr()
					catch (_:haxe.Exception) {}
					if (initExpr == null) {
						var untypedDefault = varData.getDefaultUntypedExpr();
						if (untypedDefault != null) {
							try
								initExpr = Context.typeExpr(untypedDefault)
							catch (_:haxe.Exception) {}
						}
					}
					emitStaticStorage(cf, initExpr);
				}
			}
		}

		if (isMain) {
			var headerLines:Array<String> = [];

			var modLines:Array<String> = [];
			var seenMods = new Map<String, Bool>();
			function addMod(name:String) {
				if (seenMods.exists(name))
					return;
				seenMods.set(name, true);
				modLines.push("mod " + name + ";");
			}
			var nestedTree = new RustModuleDeclTree();
			var aliasLines:Array<String> = [];
			var seenAliases = new Map<String, Bool>();
			function addGeneratedModule(flatName:String, segments:Array<String>) {
				if (!nestedModuleOutputEnabled()) {
					addMod(flatName);
					return;
				}
				addRustModuleDeclPath(nestedTree, segments);
				var nestedPath = segments.join("::");
				if (segments.length > 1 && flatName != nestedPath && !seenAliases.exists(flatName)) {
					seenAliases.set(flatName, true);
					aliasLines.push("pub mod " + flatName + " { pub use crate::" + nestedPath + "::*; }");
				}
			}

			// Extra modules (hand-written Rust sources)
			for (f in extraRustSrcFiles)
				addMod(f.module);

			// User classes
			var otherUserClasses = getUserClassesForModules();
			var lintLines:Array<String> = [];
			if (Context.defined("rust_deny_warnings")) {
				lintLines.push("#![deny(warnings)]");
			}
			lintLines.push("#![allow(dead_code)]");
			// `type_alias_bounds` is triggered by `type HxDynRef<T: ?Sized> = ...`, but that bound is
			// required to allow `dyn Trait` (unsized) usage in generated code. Silence the warning
			// so `-D rust_deny_warnings` snapshots remain green.
			lintLines.push("#![allow(type_alias_bounds)]");

			var preludeLines:Array<String> = preludeAliasLines();

			headerLines = headerLines.concat(lintLines.concat([""].concat(preludeLines).concat([""])));

			for (cls in otherUserClasses) {
				var modName = rustModuleNameForClass(cls);
				addGeneratedModule(modName, rustModuleSegmentsForClass(cls));
			}

			// User enums
			var otherUserEnums = getUserEnumsForModules();
			for (en in otherUserEnums) {
				var modName = rustModuleNameForEnum(en);
				addGeneratedModule(modName, rustModuleSegmentsForEnum(en));
			}

			modLines.sort((a, b) -> compareStrings(a, b));
			if (nestedModuleOutputEnabled()) {
				modLines = modLines.concat(renderRustModuleDeclTree(nestedTree, ""));
				aliasLines.sort((a, b) -> compareStrings(a, b));
				modLines = modLines.concat(aliasLines);
			}

			headerLines = headerLines.concat(modLines);
			headerLines.push("");
			headerLines.push(emitSubtypeTypeIdRegistryFn());
			if (headerLines.length > 0)
				items.push(RRaw(RustRawCode.compilerAt(headerLines.join("\n"), RawCrateHeader, classType.pos)));
			if (needsReflectionSupport()) {
				for (registryItem in emitReflectionRegistryFns())
					items.push(registryItem);
			}
		} else if (classType.isInterface) {
			var childModuleDecls = rustNestedChildModuleDeclLinesForSegments(rustModuleSegmentsForClass(classType));
			if (childModuleDecls.length > 0)
				items.push(RRaw(RustRawCode.compilerAt(childModuleDecls.join("\n"), RawNestedModuleDeclarations, classType.pos)));

			// Interfaces compile to Rust traits (no struct allocation).
			items.push(RRaw(RustRawCode.compilerAt("// Haxe interface -> Rust trait", RawInterfaceTraitDeclaration, classType.pos)));

			var traitLines:Array<String> = [];
			var traitGenerics = classGenericDecls;
			var traitGenericSuffix = reflaxe.rust.ast.RustASTPrinter.printGenericParameters(traitGenerics);
			traitLines.push("pub trait " + rustSelfType + traitGenericSuffix + ": Send + Sync {");
			for (f in funcFields) {
				if (f.isStatic)
					continue;
				if (f.expr != null)
					continue;

				var args:Array<String> = [];
				args.push("&self");
				var usedArgNames:Map<String, Bool> = [];
				for (a in f.args) {
					var baseName = a.getName();
					if (baseName == null || baseName.length == 0)
						baseName = "a";
					var argName = RustNaming.stableUnique(RustNaming.snakeIdent(baseName), usedArgNames);
					args.push(argName + ": " + rustTypeToString(toRustType(a.type, f.field.pos)));
				}

				var ret = rustTypeToString(rustReturnTypeForField(f.field, f.ret, f.field.pos));
				var sig = "\tfn " + rustMethodName(classType, f.field) + "(" + args.join(", ") + ") -> " + ret + ";";
				traitLines.push(sig);
			}
			traitLines.push("\tfn __hx_type_id(&self) -> u32;");
			traitLines.push("}");
			items.push(RRaw(RustRawCode.compilerAt(traitLines.join("\n"), RawInterfaceTraitDeclaration, classType.pos)));
		} else {
			var childModuleDecls = rustNestedChildModuleDeclLinesForSegments(rustModuleSegmentsForClass(classType));
			if (childModuleDecls.length > 0)
				items.push(RRaw(RustRawCode.compilerAt(childModuleDecls.join("\n"), RawNestedModuleDeclarations, classType.pos)));

			// If this class has a base class, bring base traits into scope. This matters when we inline
			// constructor `super(...)` bodies: base-typed method calls can compile to trait methods that
			// need the trait to be in scope for method-call syntax on concrete receivers.
			function baseCtorCallsThisMethods(base:ClassType):Bool {
				if (base == null)
					return false;
				if (base.constructor == null)
					return false;
				var ctorField = base.constructor.get();
				if (ctorField == null)
					return false;
				var ex = ctorField.expr();
				if (ex == null)
					return false;
				var body = switch (ex.expr) {
					case TFunction(fn): fn.expr;
					case _: ex;
				};

				var found = false;
				function scan(e:TypedExpr):Void {
					if (found)
						return;
					switch (e.expr) {
						case TCall(callExpr, _):
							switch (unwrapMetaParen(callExpr).expr) {
								case TField(obj, FInstance(_, _, _)):
									if (isThisExpr(obj)) {
										found = true;
									}
								case _:
							}
						case _:
					}
				}

				scan(body);
				TypedExprTools.iter(body, scan);
				return found;
			}

			var seenBaseUses:Map<String, Bool> = [];
			var base = classType.superClass != null ? classType.superClass.t.get() : null;
			while (base != null) {
				if (shouldEmitClass(base, false)) {
					var baseMod = rustModulePathForClass(base);
					var baseTrait = rustTypeNameForClass(base) + "Trait";
					var key = baseMod + "::" + baseTrait;
					if (!seenBaseUses.exists(key) && baseCtorCallsThisMethods(base)) {
						seenBaseUses.set(key, true);
						items.push(RRaw(RustRawCode.compilerAt("use crate::" + baseMod + "::" + baseTrait + ";", RawBaseTraitImport, classType.pos)));
					}
				}
				base = base.superClass != null ? base.superClass.t.get() : null;
			}

			emitStaticStorageItems();

			// Stable RTTI id for this class (portable-mode baseline).
			items.push(RRaw(RustRawCode.compilerAt("pub const __HX_TYPE_ID: u32 = " + typeIdLiteralForClass(classType) + ";", RawTypeIdConstant,
				classType.pos)));

			var derives = rustDerivesFromMeta(classType.meta);
			var canDeriveDebug = true;
			for (spec in getAllInstanceVarFieldSpecsForStruct(classType)) {
				var cf = spec.field;
				var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
				if (shouldOptionWrapStructFieldType(fieldType)) {
					canDeriveDebug = false;
					break;
				}
				// Trait objects (`dyn ...`) do not implement `Debug` by default, so auto-deriving `Debug`
				// for any struct that contains them would fail to compile.
				if (rustTypeContainsTraitObject(toRustType(fieldType, cf.pos))) {
					canDeriveDebug = false;
					break;
				}
			}
			if (canDeriveDebug) {
				for (spec in getAllInstanceDynamicMethodFieldSpecsForStorage(classType)) {
					var cf = spec.field;
					var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
					if (rustTypeContainsTraitObject(toRustType(fieldType, cf.pos))) {
						canDeriveDebug = false;
						break;
					}
				}
			}
			if (canDeriveDebug) {
				derives = mergeUniqueStrings(["Debug"], derives);
			}
			if (derives.length > 0)
				items.push(RRaw(RustRawCode.compilerAt("#[derive(" + derives.join(", ") + ")]", RawDeriveAttribute, classType.pos)));

			var structFields:Array<reflaxe.rust.ast.RustAST.RustStructField> = [];
			for (spec in getAllInstanceVarFieldSpecsForStruct(classType)) {
				var cf = spec.field;
				var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
				var ty = toRustType(fieldType, cf.pos);
				if (shouldOptionWrapStructFieldType(fieldType)) {
					ty = rustOptionType(ty);
				}
				structFields.push({
					name: rustFieldName(classType, cf),
					ty: ty,
					isPub: cf.isPublic
				});
			}
			for (spec in getAllInstanceDynamicMethodFieldSpecsForStorage(classType)) {
				var cf = spec.field;
				var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
				structFields.push({
					name: rustDynamicMethodFieldName(classType, cf),
					ty: toRustType(fieldType, cf.pos),
					isPub: false,
					vis: RustVisibility.VPubCrate
				});
			}
			if (classNeedsPhantomForUnusedTypeParams(classType)) {
				var phantomTypes = [for (parameter in classType.params) rustNamedType(parameter.name)];
				var phantomPayload = phantomTypes.length == 1 ? phantomTypes[0] : RTuple(phantomTypes);
				structFields.push({
					name: "__hx_phantom",
					ty: rustRelativeType(["std", "marker", "PhantomData"], [phantomPayload]),
					isPub: false
				});
			}

			items.push(RStruct({
				name: rustSelfType,
				isPub: true,
				generics: classGenericDecls,
				fields: structFields
			}));

			var implFunctions:Array<reflaxe.rust.ast.RustAST.RustFunction> = [];

			// Constructor (`new`)
			var ctor = findConstructor(funcFields);
			if (ctor != null) {
				implFunctions.push(compileConstructor(classType, varFields, ctor));
			}

			// Instance methods
			for (f in effectiveFuncFields) {
				if (f.isStatic)
					continue;
				if (f.field.getHaxeName() == "new")
					continue;
				if (f.expr == null)
					continue;
				// Inherited shims need `super` resolution based on the class that defined the body.
				var owner = inheritedOwnerById.exists(f.id) ? inheritedOwnerById.get(f.id) : classType;
				if (isDynamicMethodField(f.field)) {
					implFunctions.push(compileDynamicInstanceMethodDefault(classType, f, owner));
					implFunctions.push(compileDynamicInstanceMethodWrapper(classType, f));
				} else {
					implFunctions.push(compileInstanceMethod(classType, f, owner));
				}
			}

			// Static methods (associated functions on the type).
			for (f in effectiveFuncFields) {
				if (!f.isStatic)
					continue;
				if (f.expr == null)
					continue;
				if (f.field.getHaxeName() == "main")
					continue;
				implFunctions.push(compileStaticMethod(classType, f));
			}

			// Emit any needed "super thunks" (discovered while compiling instance method bodies).
			//
			// A super thunk is a method on `classType` that contains the base method body, but is typed
			// as `fn(&RefCell<classType>, ...)`, so `super.method(...)` can call the base implementation
			// without attempting to pass `&RefCell<Sub>` to `Base::method(&RefCell<Base>)`.
			if (currentNeededSuperThunks != null) {
				var emitted:Map<String, Bool> = [];
				var progress = true;
				while (progress) {
					progress = false;
					var keys:Array<String> = [];
					for (k in currentNeededSuperThunks.keys())
						keys.push(k);
					keys.sort((a, b) -> compareStrings(a, b));
					for (k in keys) {
						if (emitted.exists(k))
							continue;
						var spec = currentNeededSuperThunks.get(k);
						if (spec == null)
							continue;
						implFunctions.push(compileSuperThunk(classType, spec.owner, spec.field));
						emitted.set(k, true);
						progress = true;
					}
				}
			}

			items.push(RImpl({
				generics: classGenericDecls,
				forType: rustClassTypeInstType(classType),
				functions: implFunctions
			}));

			// Extra Rust trait impls declared via `@:rustImpl(...)` metadata.
			var rustImpls = rustImplsFromMeta(classType.meta);
			for (spec in rustImpls) {
				items.push(RRaw(RustRawCode.metadataAt(renderRustImplBlock(spec, classGenericDecls, rustClassTypeInstType(classType)), RawTraitImplementation,
					spec.pos)));
			}

			// Base-class polymorphism: if this class has subclasses, emit a trait for it.
			if (classHasSubclasses(classType)) {
				items.push(RRaw(RustRawCode.compilerAt(emitClassTrait(classType, effectiveFuncFields), RawClassTraitDeclaration, classType.pos)));
				items.push(RRaw(RustRawCode.compilerAt(emitClassTraitImplForSelf(classType, effectiveFuncFields), RawClassTraitImplementation, classType.pos)));
			}

			// If this class has polymorphic base classes, implement their traits for this type.
			var base = classType.superClass != null ? classType.superClass.t.get() : null;
			while (base != null) {
				if (classHasSubclasses(base)) {
					items.push(RRaw(RustRawCode.compilerAt(emitBaseTraitImplForSubclass(base, classType, effectiveFuncFields), RawBaseTraitImplementation,
						classType.pos)));
				}
				base = base.superClass != null ? base.superClass.t.get() : null;
			}

			// Implement direct, superclass-inherited, and interface-parent Haxe interfaces as Rust traits
			// on this class's own physical `HxCell<Class>` type.
			var ifaceImplTargets = resolvedImplementedInterfaceTargets(classType);
			for (ifaceTarget in ifaceImplTargets) {
				var ifaceType = ifaceTarget.ifaceType;
				if (!shouldEmitClass(ifaceType, false))
					continue;

				var ifaceMod = rustModulePathForClass(ifaceType);
				var traitPath = "crate::" + ifaceMod + "::" + rustTypeNameForClass(ifaceType);
				var ifaceTypeParams = ifaceTarget.params != null ? ifaceTarget.params : [];
				var ifaceTypeArgs = ifaceTypeParams.length > 0 ? ("<"
					+ [for (p in ifaceTypeParams) rustTypeToString(toRustType(p, classType.pos))].join(", ") + ">") : "";
				var implGenerics = reflaxe.rust.ast.RustASTPrinter.printGenericParameters(classGenericDecls);
				var implGenericNames = rustGenericNamesFromDecls(classGenericDecls);
				var implTurbofish = implGenericNames.length > 0 ? ("::<" + implGenericNames.join(", ") + ">") : "";

				var implLines:Array<String> = [];
				implLines.push("impl" + implGenerics + " " + traitPath + ifaceTypeArgs + " for " + refCellBasePath() + "<" + rustSelfTypeInst + "> {");
				// Build a lookup of class methods by name/arity so we can implement the interface
				// using the interface's signature (Rust traits require exact signature matches).
				var classByKey:Map<String, ClassFuncData> = [];
				for (f in effectiveFuncFields) {
					if (f.isStatic)
						continue;
					if (f.field.getHaxeName() == "new")
						continue;
					if (f.expr == null)
						continue;
					var argc = f.args != null ? f.args.length : 0;
					classByKey.set(f.field.getHaxeName() + "/" + argc, f);
				}

				for (ifaceField in ifaceType.fields.get()) {
					// Only methods participate in interface traits.
					switch (ifaceField.kind) {
						case FMethod(_):
						case _:
							continue;
					}

					var ifaceSig = followType(ifaceField.type);
					var ifaceMethodParams:Array<{name:String, t:Type, opt:Bool}> = [];
					var ifaceRet:Type = ifaceField.type;
					switch (ifaceSig) {
						case TFun(params, ret):
							ifaceMethodParams = params;
							ifaceRet = ret;
						case _:
					}

					// Apply the interface type arguments from `implements IFace<...>` to the raw interface
					// method signature (so `K`/`V` type parameters become concrete types like `i32` / `T`).
					function applyIfaceParams(t:Type):Type {
						if (ifaceTypeParams.length == 0)
							return t;
						if (ifaceType.params == null || ifaceType.params.length == 0)
							return t;
						return TypeTools.applyTypeParameters(t, ifaceType.params, ifaceTypeParams);
					}

					var key = ifaceField.getHaxeName() + "/" + ifaceMethodParams.length;
					if (!classByKey.exists(key))
						continue;
					var f = classByKey.get(key);

					var sigArgs:Array<String> = ["&self"];
					var callArgs:Array<String> = ["self"];
					var usedArgNames:Map<String, Bool> = [];
					for (i in 0...ifaceMethodParams.length) {
						var p = ifaceMethodParams[i];
						var baseName = p.name != null && p.name.length > 0 ? p.name : ("a" + i);
						var argName = RustNaming.stableUnique(RustNaming.snakeIdent(baseName), usedArgNames);
						var pt = applyIfaceParams(p.t);
						sigArgs.push(argName + ": " + rustTypeToString(toRustType(pt, ifaceField.pos)));
						callArgs.push(argName);
					}

					// IMPORTANT: use the interface return type, not the class method's return type.
					// Haxe allows covariant returns; Rust trait impls do not.
					var expectedRet = applyIfaceParams(ifaceRet);
					var ret = rustTypeToString(rustReturnTypeForField(ifaceField, expectedRet, ifaceField.pos));
					var ifaceRustName = rustMethodName(ifaceType, ifaceField);
					var implRustName = rustMethodName(classType, f.field);
					var call = rustSelfType + implTurbofish + "::" + implRustName + "(" + callArgs.join(", ") + ")";
					implLines.push("\tfn " + ifaceRustName + "(" + sigArgs.join(", ") + ") -> " + ret + " {");
					var needsTraitUpcast = (isInterfaceType(expectedRet) || isPolymorphicClassType(expectedRet))
						&& isHxRefValueType(f.ret)
						&& !isPolymorphicClassType(f.ret);
					if (needsTraitUpcast) {
						implLines.push("\t\tlet __tmp = " + call + ";");
						implLines.push("\t\tlet __up: " + ret + " = match __tmp.as_arc_opt() {");
						implLines.push("\t\t\tSome(__rc) => __rc.clone(),");
						implLines.push("\t\t\tNone => hxrt::exception::throw(hxrt::dynamic::from(String::from(\"Null Access\"))),");
						implLines.push("\t\t};");
						implLines.push("\t\t__up");
					} else {
						implLines.push("\t\t" + call);
					}
					implLines.push("\t}");
				}
				implLines.push("\tfn __hx_type_id(&self) -> u32 {");
				implLines.push("\t\tcrate::" + rustModulePathForClass(classType) + "::__HX_TYPE_ID");
				implLines.push("\t}");
				implLines.push("}");
				items.push(RRaw(RustRawCode.compilerAt(implLines.join("\n"), RawInterfaceTraitImplementation, classType.pos)));
			}
		}

		if (isMain) {
			emitStaticStorageItems();

			// Emit any additional static functions so user code can call them from `main`.
			for (f in funcFields) {
				if (!f.isStatic)
					continue;
				if (f.expr == null)
					continue;

				var haxeName = f.field.getHaxeName();
				if (haxeName == "main")
					continue;

				var compiled = compileStaticFunctionShape(f);

				items.push(RFn({
					name: rustMethodName(classType, f.field),
					isPub: false,
					generics: compiled.generics,
					args: compiled.args,
					ret: compiled.ret,
					body: compiled.body
				}));
			}

			var mainFunc = findStaticMain(funcFields);
			if (mainFunc != null && hasAsyncFunctionMeta(mainFunc.field.meta)) {
				ensureAsyncAllowed(mainFunc.field.pos);
				#if eval
				RustDiagnostic.error(RustDiagnosticId.AsyncMainSync,
					"`main` must stay synchronous for the Rust async contract. Move async work into a helper returning `rust.async.Future<T>` and call `rust.async.Async.blockOn(...)` from sync `main`.",
					mainFunc.field.pos);
				#end
			}
			// Rust `fn main()` is always unit-returning; compile as void to avoid accidental tail expressions.
			var body:RustBlock = (mainFunc != null && mainFunc.expr != null) ? compileVoidBodyWithContext(mainFunc.expr, []) : defaultMainBody();

			items.push(RFn({
				name: "main",
				isPub: false,
				generics: RustGenericParameters.empty(),
				args: [],
				ret: RUnit,
				body: body
			}));

			var rustTests = renderRustTestModule();
			if (rustTests != null && rustTests.length > 0) {
				items.push(RRaw(RustRawCode.compilerGenerated(rustTests, RawGeneratedTestModule)));
			}
		}

		currentClassKey = null;
		currentClassName = null;
		currentClassType = null;
		currentClassContext = null;
		currentMethodOwnerType = null;
		currentNeededSuperThunks = null;
		return {items: items};
	}

	public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<RustFile> {
		collectTypeUsageFromCurrentModule(sourceFileForPosition(enumType.pos));
		enforceNoHxrtEligibility();

		if (!shouldEmitEnum(enumType))
			return null;

		setOutputFileDir(rustOutputDirForEnum(enumType));
		setOutputFileName(rustModuleFileStemForEnum(enumType));

		var items:Array<RustItem> = [];
		items.push(RRaw(RustRawCode.compilerGenerated("// Generated by reflaxe.rust", RawGeneratedFileMarker)));
		var childModuleDecls = rustNestedChildModuleDeclLinesForSegments(rustModuleSegmentsForEnum(enumType));
		if (childModuleDecls.length > 0)
			items.push(RRaw(RustRawCode.compilerAt(childModuleDecls.join("\n"), RawNestedModuleDeclarations, enumType.pos)));
		items.push(RRaw(RustRawCode.compilerAt("pub const __HX_TYPE_ID: u32 = " + typeIdLiteralForEnum(enumType) + ";", RawTypeIdConstant,
			enumType.pos)));

		var variants:Array<reflaxe.rust.ast.RustAST.RustEnumVariant> = [];
		var enumGenerics = rustGenericParametersForEnum(enumType);
		var enumTypeName = rustTypeNameForEnum(enumType);
		var enumArguments = rustGenericArgumentsFromDecls(enumGenerics);
		var enumTypeInstType:RustType = RNamed(rustRelativePath([enumTypeName], enumArguments));
		var enumTypePathInstType:RustType = RNamed(rustCratePath(rustModuleSegmentsForEnum(enumType).concat([enumTypeName]), enumArguments));
		var enumTypeInst = rustTypeToString(enumTypeInstType);

		function boxRecursiveEnumArg(rt:reflaxe.rust.ast.RustAST.RustType):reflaxe.rust.ast.RustAST.RustType {
			if (rustTypesEqual(rt, enumTypeInstType) || rustTypesEqual(rt, enumTypePathInstType))
				return rustBoxType(enumTypeInstType);
			var optionInner = rustTypeSingleGenericArgument(rt);
			if (rustTypeIsRelativePath(rt, ["Option"])
				&& optionInner != null
				&& (rustTypesEqual(optionInner, enumTypeInstType) || rustTypesEqual(optionInner, enumTypePathInstType)))
				return rustOptionType(rustBoxType(enumTypeInstType));
			return rt;
		}

		for (opt in options) {
			var argTypes:Array<reflaxe.rust.ast.RustAST.RustType> = [];
			for (a in opt.args) {
				var rt = toRustType(a.type, opt.field.pos);
				argTypes.push(boxRecursiveEnumArg(rt));
			}
			variants.push({name: opt.name, args: argTypes});
		}

		var derives = mergeUniqueStrings(["Clone", "Debug", "PartialEq"], rustDerivesFromMeta(enumType.meta));
		items.push(REnum({
			name: enumTypeName,
			isPub: true,
			generics: enumGenerics,
			derives: derives,
			variants: variants
		}));

		var rustImpls = rustImplsFromMeta(enumType.meta);
		for (spec in rustImpls) {
			items.push(RRaw(RustRawCode.metadataAt(renderRustImplBlock(spec, enumGenerics, enumTypeInstType), RawTraitImplementation, spec.pos)));
		}

		return {items: items};
	}

	override public function compileTypedefImpl(typedefType:DefType):Null<RustFile> {
		collectTypeUsageFromCurrentModule(sourceFileForPosition(typedefType.pos));
		enforceNoHxrtEligibility();
		return null;
	}

	override public function compileAbstractImpl(abstractType:AbstractType):Null<RustFile> {
		collectTypeUsageFromCurrentModule(sourceFileForPosition(abstractType.pos));
		enforceNoHxrtEligibility();
		return null;
	}

	public function compileExpressionImpl(expr:TypedExpr, topLevel:Bool):Null<RustExpr> {
		return compileExpr(expr);
	}

	function isMainClass(classType:ClassType):Bool {
		var mainCls = resolveMainClass();
		return mainCls != null
			&& (mainCls.module == classType.module
				&& mainCls.name == classType.name
				&& mainCls.pack.join(".") == classType.pack.join("."));
	}

	function resolveMainClass():Null<ClassType> {
		if (cachedMainClassResolved)
			return cachedMainClass;
		cachedMainClassResolved = true;

		// Prefer the "direct main call" path when available.
		var m = getMainModule();
		switch (m) {
			case TClassDecl(clsRef):
				cachedMainClass = clsRef.get();
				return cachedMainClass;
			case _:
		}

		// Some stdlib features (notably `sys.thread` / `haxe.EntryPoint`) can rewrite the "main expr"
		// into a wrapper call. `BaseCompiler.getMainModule()` only handles direct `MyClass.main()`.
		// Fall back to searching the typed `getMainExpr()` for a static `main` reference.
		var mainExpr = getMainExpr();
		if (mainExpr == null)
			return null;

		var found:Null<ClassType> = null;
		function visit(e:TypedExpr):Void {
			if (found != null)
				return;
			switch (e.expr) {
				case TField(_, fa):
					switch (fa) {
						case FStatic(clsRef, cfRef):
							if (cfRef.get().name == "main") found = clsRef.get();
						case _:
					}
				case _:
			}
			TypedExprTools.iter(e, visit);
		}
		visit(mainExpr);
		cachedMainClass = found;
		return cachedMainClass;
	}

	function findStaticMain(funcFields:Array<ClassFuncData>):Null<ClassFuncData> {
		for (f in funcFields) {
			if (!f.isStatic)
				continue;
			if (f.field.getHaxeName() != "main")
				continue;
			return f;
		}
		return null;
	}

	function defaultMainBody():RustBlock {
		return {
			stmts: [RSemi(EMacroCall("println", [ELitString("hi")]))],
			tail: null
		};
	}

	function shouldEmitClass(classType:ClassType, isMain:Bool):Bool {
		if (isMain)
			return true;
		if (classType.isExtern)
			return false;
		// Never emit compile-time-only std packages.
		// These can appear in the typer context due to macros/tools even for runtime builds.
		if (classType.pack.length >= 2 && classType.pack[0] == "haxe") {
			var p1 = classType.pack[1];
			if (p1 == "macro" || p1 == "display")
				return false;
		}
		// Framework-only helpers: `Lambda` is used heavily at compile-time (including by Haxe's own macro
		// stdlib via `using Lambda`), but we treat it as an inline/macro-time helper and avoid emitting a
		// Rust module for it.
		if (classType.pack.length == 0 && classType.name == "Lambda")
			return false;
		// Core API classes: we compile these via intrinsics/special-cases rather than emitting upstream
		// implementations (which are target-specific and often rely on platform defines).
		if (classType.pack.length == 0 && (classType.name == "Std" || classType.name == "Type" || classType.name == "Reflect"))
			return false;
		// Same idea as `Lambda`: this is an inline-only helper surface.
		if (classType.pack.length == 0 && classType.name == "ArrayTools")
			return false;
		var frameworkStd = isFrameworkStdClass(classType);
		if (noHxrtEnabled() && frameworkStd)
			return false;
		return isUserProjectFile(sourceFileForPosition(classType.pos)) || frameworkStd;
	}

	function shouldEmitEnum(enumType:EnumType):Bool {
		if (enumType.isExtern)
			return false;
		if (isBuiltinEnum(enumType))
			return false;
		if (enumType.pack.length >= 2 && enumType.pack[0] == "haxe") {
			var p1 = enumType.pack[1];
			if (p1 == "macro" || p1 == "display")
				return false;
		}
		var frameworkStd = isFrameworkStdEnum(enumType);
		if (noHxrtEnabled() && frameworkStd)
			return false;
		return isUserProjectFile(sourceFileForPosition(enumType.pos)) || frameworkStd;
	}

	function isUserProjectFile(file:String):Bool {
		if (file == null || file.length == 0)
			return false;
		var cwd = normalizePath(Sys.getCwd());
		var full = resolvePosFileToAbsolute(file, cwd);
		return StringTools.startsWith(full, ensureTrailingSlash(cwd)) && !isFrameworkOwnedFile(full);
	}

	function isFrameworkStdFile(file:String):Bool {
		var full = canonicalizePosFile(file);

		if (frameworkStdSourceFiles.exists(full))
			return true;

		var modulePath = sourceModuleByCanonicalFile.get(full);
		if (modulePath != null && isFrameworkStdModuleSource(full, modulePath))
			return true;

		if (isUnderUpstreamStdRoot(full))
			return true;

		return false;
	}

	function isFrameworkStdClass(classType:ClassType):Bool {
		return isFrameworkStdDeclaration(modulePathForClass(classType), classType.pos);
	}

	function isFrameworkStdEnum(enumType:EnumType):Bool {
		return isFrameworkStdDeclaration(modulePathForEnum(enumType), enumType.pos);
	}

	function isFrameworkStdDeclaration(modulePath:String, pos:haxe.macro.Expr.Position):Bool {
		var sourceFile = sourceFileForPosition(pos);
		if (sourceFile == null || sourceFile.length == 0)
			return false;
		var full = canonicalizePosFile(sourceFile);
		if (isFrameworkStdModuleSource(full, modulePath))
			return true;
		return isUnderUpstreamStdRoot(full);
	}

	/**
		Returns whether an absolute path belongs to framework-owned source in this backend checkout.

		Why
		- When compiling examples/tests from the repository root, framework code also lives under
		  the current working directory.
		- Policy checks that are supposed to report user-authored behavior (for example portable
		  native imports) must not treat backend internals under `src/`, `std/`, or `runtime/hxrt/`
		  as application code.

		How
		- Checks the explicit framework std root for source-checkout std/support modules.
		- Separately checks the framework classpath root for compiler/framework implementation files
		  and `runtime/hxrt/` for bundled runtime sources.
	**/
	function isFrameworkOwnedFile(full:String):Bool {
		if (isUnderFrameworkStdSourceRoot(full))
			return true;

		if (frameworkClassPathDir != null) {
			var classPathRoot = ensureTrailingSlash(normalizePath(frameworkClassPathDir));
			if (StringTools.startsWith(full, classPathRoot))
				return true;
		}

		if (frameworkRuntimeDir != null) {
			var runtimeRoot = ensureTrailingSlash(normalizePath(frameworkRuntimeDir));
			if (StringTools.startsWith(full, runtimeRoot))
				return true;
		}

		return false;
	}

	/**
		Returns whether an absolute file path is inside this library's source std/support root.

		Why
		- Source checkouts keep framework std/support Haxe files under `std/`.
		- This is a root ownership check only; semantic std identity comes from typed module metadata
		  recorded by `buildSourceProvenanceIndex()`.

		How
		- Canonicalize both sides before prefix matching so symlink aliases do not split ownership.
	**/
	function isUnderFrameworkStdSourceRoot(full:String):Bool {
		if (frameworkStdDir != null) {
			var stdRoot = ensureTrailingSlash(normalizePath(frameworkStdDir));
			if (StringTools.startsWith(full, stdRoot))
				return true;
		}
		return false;
	}

	/**
		Returns true when a typed module source belongs to this library's target std/support surface.

		Why
		- Installed packages place compiler code and generated std overrides under the same framework
		  classpath root, so root ownership alone cannot distinguish `reflaxe.rust.*` implementation
		  modules from target std/support modules.
		- Haxe/Reflaxe typed module metadata already carries the semantic module path, which is stable
		  across source and installed layouts.

		How
		- Source checkout std/support files are accepted by explicit `std/` root ownership.
		- Framework classpath files are accepted only when their typed module path is a target
		  std/support module (`haxe.*`, `sys.*`, `rust.*`, `hxrt.*`, or known top-level std modules).
	**/
	function isFrameworkStdModuleSource(full:String, modulePath:String):Bool {
		if (isUnderFrameworkStdSourceRoot(full))
			return true;

		if (modulePath == null || modulePath.length == 0)
			return false;

		if (frameworkClassPathDir != null) {
			var classPathRoot = ensureTrailingSlash(normalizePath(frameworkClassPathDir));
			if (StringTools.startsWith(full, classPathRoot))
				return isFrameworkStdModulePath(modulePath);
		}

		return false;
	}

	function isFrameworkStdModulePath(modulePath:String):Bool {
		if (modulePath == null || modulePath.length == 0)
			return false;
		if (modulePath == "haxe" || StringTools.startsWith(modulePath, "haxe."))
			return true;
		if (modulePath == "sys" || StringTools.startsWith(modulePath, "sys."))
			return true;
		if (modulePath == "rust" || StringTools.startsWith(modulePath, "rust."))
			return true;
		if (modulePath == "hxrt" || StringTools.startsWith(modulePath, "hxrt."))
			return true;
		return switch (modulePath) {
			case "Date" | "Lambda" | "StringBuf" | "StringTools" | "Sys" | "SysTypes" | "ArrayTools": true;
			case _: false;
		}
	}

	function isUnderUpstreamStdRoot(full:String):Bool {
		if (upstreamStdDirs.length == 0)
			return false;
		for (d in upstreamStdDirs) {
			var r = ensureTrailingSlash(normalizePath(d));
			if (StringTools.startsWith(full, r))
				return true;
		}
		return false;
	}

	function modulePathForClass(classType:ClassType):String {
		return classType.module != null && classType.module.length > 0 ? classType.module : dotPathFromPack(classType.pack, classType.name);
	}

	function modulePathForEnum(enumType:EnumType):String {
		return enumType.module != null && enumType.module.length > 0 ? enumType.module : dotPathFromPack(enumType.pack, enumType.name);
	}

	function dotPathFromPack(pack:Array<String>, name:String):String {
		return pack == null || pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	/**
		Returns whether warning noise for unresolved monomorphs should be emitted at this position.

		Policy
		- Keep warnings enabled for user/project code (high-signal actionable issues).
		- Suppress them for framework/upstream stdlib internals by default, where the fallback to
		  `Dynamic` is an intentional compatibility bridge and warning spam obscures CI logs.
		- Allow forcing std warnings back on with `-D rust_warn_unresolved_monomorph_std`.
	**/
	function shouldWarnUnresolvedMonomorph(pos:haxe.macro.Expr.Position):Bool {
		if (Context.defined("rust_warn_unresolved_monomorph_std"))
			return true;
		var info = Context.getPosInfos(pos);
		if (info == null)
			return true;
		return !isFrameworkStdFile(info.file);
	}

	/**
		Returns whether unresolved monomorph -> runtime dynamic fallback is permitted at this position.

		Policy
		- User/project code should not silently degrade to runtime-dynamic typing; fail fast so type
		  annotations or explicit casts can fix the root cause.
		- Framework/upstream std internals may still use this compatibility fallback to preserve
		  existing behavior.
		- Emergency escape hatch: `-D rust_allow_unresolved_monomorph_dynamic`.
	**/
	function shouldAllowUnresolvedMonomorphDynamicFallback(pos:haxe.macro.Expr.Position):Bool {
		if (Context.defined("rust_allow_unresolved_monomorph_dynamic"))
			return true;
		var info = Context.getPosInfos(pos);
		if (info == null)
			return false;
		return isFrameworkStdFile(info.file);
	}

	/**
		Returns whether unmapped `@:coreType` -> runtime dynamic fallback should emit a warning.

		Policy
		- Keep warnings enabled for user/project code.
		- Suppress stdlib/framework warning noise by default (compatibility fallback can be expected there).
		- Allow forcing std warnings back on with `-D rust_warn_unmapped_coretype_std`.
	**/
	function shouldWarnUnmappedCoreType(pos:haxe.macro.Expr.Position):Bool {
		if (Context.defined("rust_warn_unmapped_coretype_std"))
			return true;
		var info = Context.getPosInfos(pos);
		if (info == null)
			return true;
		return !isFrameworkStdFile(info.file);
	}

	/**
		Returns whether unmapped `@:coreType` -> runtime dynamic fallback is permitted at this position.

		Policy
		- User/project code should fail fast so backend authors add explicit typed mappings.
		- Framework/upstream std internals may still use this fallback for compatibility.
		- Emergency escape hatch: `-D rust_allow_unmapped_coretype_dynamic`.
	**/
	function shouldAllowUnmappedCoreTypeDynamicFallback(pos:haxe.macro.Expr.Position):Bool {
		if (Context.defined("rust_allow_unmapped_coretype_dynamic"))
			return true;
		var info = Context.getPosInfos(pos);
		if (info == null)
			return false;
		return isFrameworkStdFile(info.file);
	}

	/**
		Normalize and resolve a `pos.file` path from the Haxe typer.

		Gotcha
		- `Context.getPosInfos(...).file` is not guaranteed to be an absolute path.
		- Some stdlib modules can appear as relative paths like `haxe/IMap.hx`.
		- If we naively join relative paths onto the current working directory, we can accidentally
		  misclassify upstream stdlib files as "user project" files, causing huge unintended emission.

		Strategy
		- If the path is absolute, keep it.
		- Else, try `Context.resolvePath(file)` (classpath-based) to get the real absolute location.
		- If resolution fails, fall back to `cwd + file` so local relative files still work.
		- Canonicalize existing paths (`FileSystem.fullPath`) so symlink aliases (for example
		  `/var/...` vs `/private/var/...`) don't break framework-stdlib prefix checks.
	**/
	function canonicalizePosFile(file:String):String {
		if (file == null || file.length == 0)
			return "";
		var cwd = normalizePath(Sys.getCwd());
		return resolvePosFileToAbsolute(file, cwd);
	}

	function resolvePosFileToAbsolute(file:String, cwd:String):String {
		var full = file;
		if (!Path.isAbsolute(full)) {
			// `Context.resolvePath` is classpath-based and is the best way to map stdlib-ish relative
			// paths (e.g. `haxe/IMap.hx`) to their true absolute location.
			//
			// However, for local project files Haxe may already give us a relative `pos.file` like
			// `Foo.hx`, and `resolvePath` can return that same relative string on some setups.
			//
			// Only fall back to `cwd + file` if the joined path actually exists, otherwise we'd risk
			// misclassifying upstream stdlib files as user code.
			var resolved:Null<String> = null;
			try {
				resolved = Context.resolvePath(full);
			} catch (e:haxe.Exception) {}
			if (resolved != null)
				full = resolved;
			if (!Path.isAbsolute(full)) {
				var candidate = Path.join([cwd, full]);
				if (FileSystem.exists(candidate)) {
					full = candidate;
				}
			}
		}
		return canonicalizePath(full);
	}

	function ensureTrailingSlash(path:String):String {
		return StringTools.endsWith(path, "/") ? path : (path + "/");
	}

	function normalizePath(path:String):String {
		return Path.normalize(path).split("\\").join("/");
	}

	function canonicalizePath(path:String):String {
		var p = path;
		try {
			if (FileSystem.exists(p))
				p = FileSystem.fullPath(p);
		} catch (e:haxe.Exception) {}
		return normalizePath(p);
	}

	function classKey(classType:ClassType):String {
		return classType.pack.join(".") + "." + classType.name;
	}

	/**
		Resolves an ancestor's type parameters in the concrete type context of a descendant.

		Why
		- Haxe stores a base member's declared type on the base `ClassField`; `Base<T>.value` therefore
		  remains `T` even while emitting `StringChild extends Base<String>`.
		- Rust emits a physical child struct and synthesized inherited methods, so leaking that unbound
		  base parameter produces invalid Rust instead of inheriting Haxe's specialization implicitly.

		What
		- Returns the ancestor arguments as seen from `descendant`, composing every generic superclass
		  edge (for example `Leaf extends Mid<String>`, `Mid<U> extends Base<Array<U>>` becomes
		  `Base<Array<String>>`).
		- Returns `null` when `ancestor` is not actually in the descendant's superclass chain.

		How
		- Each `superClass.params` array is expressed in the current class's parameter vocabulary.
		- Apply the already-resolved current arguments before advancing to the next superclass edge.
	**/
	function resolvedAncestorTypeArgs(descendant:ClassType, ancestor:ClassType):Null<Array<Type>> {
		if (descendant == null || ancestor == null || classKey(descendant) == classKey(ancestor))
			return null;

		var current:Null<ClassType> = descendant;
		var currentArgs:Null<Array<Type>> = null;
		while (current != null && current.superClass != null) {
			var superType = current.superClass.t.get();
			if (superType == null)
				return null;

			var edgeArgs = current.superClass.params != null ? current.superClass.params.copy() : [];
			if (currentArgs != null && current.params != null && current.params.length > 0 && current.params.length == currentArgs.length) {
				edgeArgs = [for (arg in edgeArgs) TypeTools.applyTypeParameters(arg, current.params, currentArgs)];
			}

			if (classKey(superType) == classKey(ancestor))
				return edgeArgs;

			current = superType;
			currentArgs = edgeArgs;
		}
		return null;
	}

	/**
		Specializes a type declared by an ancestor for a concrete descendant emission context.

		Why / What / How
		- This is the single typed substitution boundary used by physical inherited fields, synthesized
		  methods, constructor chains, and trait implementations.
		- Types owned by the descendant stay unchanged. Ancestor-owned types use
		  `TypeTools.applyTypeParameters`, preserving Haxe's typed representation until ordinary Rust
		  type lowering runs.
		- No string rewriting or runtime type carrier participates in specialization.
	**/
	function specializeAncestorType(descendant:ClassType, owner:ClassType, t:Type):Type {
		if (descendant == null || owner == null || t == null || classKey(descendant) == classKey(owner))
			return t;
		var resolved = resolvedAncestorTypeArgs(descendant, owner);
		if (resolved == null || owner.params == null || owner.params.length == 0 || owner.params.length != resolved.length)
			return t;
		return TypeTools.applyTypeParameters(t, owner.params, resolved);
	}

	/**
		Applies the active inherited-method specialization to a typed AST type.

		Why / What / How
		- Inherited method bodies are compiled from their original base AST while `currentClassType`
		  names the concrete descendant receiving the synthesized Rust method.
		- When both contexts are active, delegate to `specializeAncestorType`; ordinary methods and
		  non-inheritance lowering return the input unchanged.
		- `toRustType` and copy analysis use this boundary so every nested type decision sees the same
		  concrete ancestor substitution.
	**/
	function specializeCurrentMethodType(t:Type):Type {
		if (currentClassType == null || currentMethodOwnerType == null)
			return t;
		return specializeAncestorType(currentClassType, currentMethodOwnerType, t);
	}

	/**
		Resolves every implemented interface in a descendant's concrete type context.

		Why
		- Haxe records `interfaces` on the class that declares the `implements` edge; a subclass does not
		  repeat interfaces inherited from its superclass.
		- Rust gives each emitted subclass its own physical `HxCell<Subclass>` type, so the subclass needs
		  its own trait impl even when Haxe inherited `ValueSource<String>` from `Base<String>`.

		What
		- Returns direct interfaces, superclass-inherited interfaces, and their parent interfaces.
		- Every returned type argument is expressed in the descendant's type-parameter vocabulary.

		How
		- Walks the superclass chain and specializes each declaring class's interface arguments through
		  `specializeAncestorType`.
		- Recursively composes interface-parent arguments with `TypeTools.applyTypeParameters`.
		- Deduplicates by interface identity because Haxe does not admit conflicting repeated generic
		  interface instantiations for one class hierarchy.
	**/
	function resolvedImplementedInterfaceTargets(descendant:ClassType):Array<{ifaceType:ClassType, params:Array<Type>}> {
		var out:Array<{ifaceType:ClassType, params:Array<Type>}> = [];
		var seen:Map<String, Bool> = [];

		function collectInterface(ifaceType:ClassType, resolvedParams:Array<Type>):Void {
			if (ifaceType == null)
				return;
			var key = classKey(ifaceType);
			if (seen.exists(key))
				return;
			seen.set(key, true);
			out.push({ifaceType: ifaceType, params: resolvedParams != null ? resolvedParams : []});

			for (parent in ifaceType.interfaces) {
				var parentType = parent.t.get();
				if (parentType == null)
					continue;
				var parentParams = parent.params != null ? parent.params.copy() : [];
				if (parentParams.length > 0 && ifaceType.params != null && ifaceType.params.length > 0 && resolvedParams != null
					&& resolvedParams.length == ifaceType.params.length) {
					parentParams = [
						for (p in parentParams)
							TypeTools.applyTypeParameters(p, ifaceType.params, resolvedParams)
					];
				}
				collectInterface(parentType, parentParams);
			}
		}

		var owner:Null<ClassType> = descendant;
		while (owner != null) {
			for (iface in owner.interfaces) {
				var ifaceType = iface.t.get();
				if (ifaceType == null)
					continue;
				var resolvedParams = iface.params != null ? [
					for (p in iface.params)
						specializeAncestorType(descendant, owner, p)
				] : [];
				collectInterface(ifaceType, resolvedParams);
			}
			owner = owner.superClass != null ? owner.superClass.t.get() : null;
		}

		return out;
	}

	function rustModuleNameForClass(classType:ClassType):String {
		var base = (classType.pack.length > 0 ? (classType.pack.join("_") + "_") : "") + classType.name;
		return RustNaming.snakeIdent(base);
	}

	function rustModuleNameForEnum(enumType:EnumType):String {
		var base = (enumType.pack.length > 0 ? (enumType.pack.join("_") + "_") : "") + enumType.name;
		return RustNaming.snakeIdent(base);
	}

	/**
		Returns the Rust module path used in generated references for a Haxe class.

		Why
		- `rustModuleNameForClass` is a flat compatibility name (`foo_bar_Baz` -> `foo_bar_baz`)
		  used for legacy filenames, alias modules, and generated identifiers that cannot contain
		  `::`.
		- In `-D rust_nested_modules` output, semantic references should follow the physical nested
		  module tree (`crate::foo::bar::baz::Baz`) so emitted Rust reads like the generated layout.

		What
		- Non-nested output keeps the historical flat module path.
		- Nested output returns package-shaped Rust module segments joined with `::`.

		How
		- Use this helper for `crate::<module>::Type` references, method paths, trait paths, and type
		  signatures.
		- Keep using `rustModuleNameForClass` for file/alias names or any generated Rust identifier.
	**/
	function rustModulePathForClass(classType:ClassType):String {
		return nestedModuleOutputEnabled() ? rustModuleSegmentsForClass(classType).join("::") : rustModuleNameForClass(classType);
	}

	/**
		Returns the Rust module path used in generated references for a Haxe enum.

		Why / What / How
		- Mirrors `rustModulePathForClass` for enum modules so recursive enum types, variant paths,
		  and ordinary enum type references use canonical nested paths when `rust_nested_modules`
		  is enabled, while flat compatibility names remain available for aliases and filenames.
	**/
	function rustModulePathForEnum(enumType:EnumType):String {
		return nestedModuleOutputEnabled() ? rustModuleSegmentsForEnum(enumType).join("::") : rustModuleNameForEnum(enumType);
	}

	inline function nestedModuleOutputEnabled():Bool {
		return Context.defined("rust_nested_modules");
	}

	/**
		Returns the generated Rust module path segments for a Haxe package/type.

		Why
		- The historical output used one flat module per Haxe type (`foo.Bar` ->
		  `foo_bar.rs`). That keeps path rewriting simple but produces generated crates that are hard
		  to review against idiomatic Rust projects.
		- `-D rust_nested_modules` is the migration bridge: files are emitted under package-shaped
		  directories. Generated references use `rustModulePathFor*` canonical nested paths, while
		  root alias modules still preserve `crate::<flat_module>::...` compatibility for handwritten
		  extra Rust modules or raw snippets that were authored against the old shape.

		How
		- Package segments and type filenames are snake-cased independently so Rust keywords and Haxe
		  casing are handled at each module boundary.
	**/
	function rustModuleSegmentsForBase(pack:Array<String>, name:String):Array<String> {
		if (!nestedModuleOutputEnabled())
			return [
				(pack.length > 0 ? RustNaming.snakeIdent(pack.join("_") + "_" + name) : RustNaming.snakeIdent(name))
			];
		var segments = [for (p in pack) RustNaming.snakeIdent(p)];
		segments.push(RustNaming.snakeIdent(name));
		return segments;
	}

	inline function rustModuleSegmentsForClass(classType:ClassType):Array<String> {
		return rustModuleSegmentsForBase(classType.pack, classType.name);
	}

	inline function rustModuleSegmentsForEnum(enumType:EnumType):Array<String> {
		return rustModuleSegmentsForBase(enumType.pack, enumType.name);
	}

	function rustOutputDirForSegments(segments:Array<String>):String {
		if (!nestedModuleOutputEnabled() || segments.length <= 1)
			return "src";
		return "src/" + segments.slice(0, segments.length - 1).join("/");
	}

	inline function rustOutputDirForClass(classType:ClassType):String {
		return rustOutputDirForSegments(rustModuleSegmentsForClass(classType));
	}

	inline function rustOutputDirForEnum(enumType:EnumType):String {
		return rustOutputDirForSegments(rustModuleSegmentsForEnum(enumType));
	}

	inline function rustModuleFileStemForClass(classType:ClassType):String {
		var segments = rustModuleSegmentsForClass(classType);
		return segments[segments.length - 1];
	}

	inline function rustModuleFileStemForEnum(enumType:EnumType):String {
		var segments = rustModuleSegmentsForEnum(enumType);
		return segments[segments.length - 1];
	}

	function addRustModuleDeclPath(tree:RustModuleDeclTree, segments:Array<String>):Void {
		var node = tree;
		for (segment in segments) {
			var child = node.children.get(segment);
			if (child == null) {
				child = new RustModuleDeclTree();
				node.children.set(segment, child);
			}
			node = child;
		}
		node.hasFile = true;
	}

	function renderRustModuleDeclTree(tree:RustModuleDeclTree, indent:String):Array<String> {
		var keys = [for (k in tree.children.keys()) k];
		keys.sort((a, b) -> compareStrings(a, b));
		var lines:Array<String> = [];
		for (key in keys) {
			var child = tree.children.get(key);
			if (child == null)
				continue;
			var childKeys = [for (_ in child.children.keys()) _];
			if (child.hasFile || childKeys.length == 0) {
				lines.push(indent + "pub mod " + key + ";");
			} else {
				lines.push(indent + "pub mod " + key + " {");
				lines = lines.concat(renderRustModuleDeclTree(child, indent + "    "));
				lines.push(indent + "}");
			}
		}
		return lines;
	}

	function rustNestedChildModuleDeclLinesForSegments(parentSegments:Array<String>):Array<String> {
		if (!nestedModuleOutputEnabled())
			return [];
		var tree = new RustModuleDeclTree();
		for (segments in rustAllGeneratedModuleSegments()) {
			if (!isStrictModuleDescendant(parentSegments, segments))
				continue;
			addRustModuleDeclPath(tree, segments.slice(parentSegments.length));
		}
		return renderRustModuleDeclTree(tree, "");
	}

	function rustAllGeneratedModuleSegments():Array<Array<String>> {
		var result:Array<Array<String>> = [];
		for (cls in getUserClassesForModules())
			result.push(rustModuleSegmentsForClass(cls));
		for (en in getUserEnumsForModules())
			result.push(rustModuleSegmentsForEnum(en));
		return result;
	}

	function isStrictModuleDescendant(parentSegments:Array<String>, childSegments:Array<String>):Bool {
		if (childSegments.length <= parentSegments.length)
			return false;
		for (i in 0...parentSegments.length) {
			if (parentSegments[i] != childSegments[i])
				return false;
		}
		return true;
	}

	function rustTypeNameForClass(classType:ClassType):String {
		return RustNaming.typeIdent(classType.name);
	}

	function rustTypeNameForEnum(enumType:EnumType):String {
		return RustNaming.typeIdent(enumType.name);
	}

	function rustGenericParametersForEnum(enumType:EnumType):RustGenericParameters {
		if (enumType.params == null || enumType.params.length == 0)
			return RustGenericParameters.empty();
		return RustGenericParameters.of([
			for (parameter in enumType.params)
				GenericTypeParam(RustIdentifier.named(parameter.name), [], null)
		]);
	}

	function isValidRustIdent(name:String):Bool {
		return RustNaming.isValidIdent(name);
	}

	function isRustKeyword(name:String):Bool {
		return RustNaming.isKeyword(name);
	}

	function rustMemberBaseIdent(haxeName:String):String {
		return RustNaming.snakeIdent(haxeName);
	}

	function ensureRustNamesForClass(classType:ClassType):Void {
		var key = classKey(classType);
		if (rustNamesByClass.exists(key))
			return;

		var fieldUsed:Map<String, Bool> = [];
		var methodUsed:Map<String, Bool> = [];
		var fieldMap:Map<String, String> = [];
		var methodMap:Map<String, String> = [];

		// Instance fields that become struct fields.
		var fieldNames:Array<String> = [];
		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			fieldNames.push(cf.getHaxeName());
		}
		for (name in fieldNames) {
			var base = rustMemberBaseIdent(name);
			fieldMap.set(name, RustNaming.stableUnique(base, fieldUsed));
		}

		// Methods (instance base->derived + static).
		//
		// Important: base method names must be reserved first so overrides keep the same Rust name,
		// and derived-only names disambiguate against inherited names.
		var chain:Array<ClassType> = [];
		var cur:Null<ClassType> = classType;
		while (cur != null) {
			chain.unshift(cur);
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}

		for (cls in chain) {
			var clsMethodNames:Array<String> = [];
			for (cf in cls.fields.get()) {
				switch (cf.kind) {
					case FMethod(_):
						clsMethodNames.push(cf.getHaxeName());
					case _:
				}
			}
			clsMethodNames.sort((a, b) -> compareStrings(a, b));
			for (name in clsMethodNames) {
				if (methodMap.exists(name))
					continue;
				var base = rustMemberBaseIdent(name);
				methodMap.set(name, RustNaming.stableUnique(base, methodUsed));
			}
		}

		var staticMethodNames:Array<String> = [];
		for (cf in classType.statics.get()) {
			switch (cf.kind) {
				case FMethod(_):
					staticMethodNames.push(cf.getHaxeName());
				case FVar(_, _):
					// Static vars share the same identifier namespace as associated functions in Rust
					// once we lower them to helper accessors. Reserve their names here so we can pick
					// a stable, collision-free Rust identifier.
					staticMethodNames.push(cf.getHaxeName());
				case _:
			}
		}
		staticMethodNames.sort((a, b) -> compareStrings(a, b));
		for (name in staticMethodNames) {
			if (methodMap.exists(name))
				continue;
			var base = rustMemberBaseIdent(name);
			methodMap.set(name, RustNaming.stableUnique(base, methodUsed));
		}

		rustNamesByClass.set(key, {fields: fieldMap, methods: methodMap});
	}

	function rustFieldName(classType:ClassType, cf:ClassField):String {
		ensureRustNamesForClass(classType);
		var entry = rustNamesByClass.get(classKey(classType));
		var name = cf.getHaxeName();
		return entry != null && entry.fields.exists(name) ? entry.fields.get(name) : rustMemberBaseIdent(name);
	}

	function rustMethodName(classType:ClassType, cf:ClassField):String {
		ensureRustNamesForClass(classType);
		var entry = rustNamesByClass.get(classKey(classType));
		var name = cf.getHaxeName();
		return entry != null && entry.methods.exists(name) ? entry.methods.get(name) : rustMemberBaseIdent(name);
	}

	function rustStaticVarHelperName(prefix:String, rustName:String):String {
		// Avoid double underscores when `rustName` begins with `_` (common for private fields like `_x`).
		// Rust's `non_snake_case` lint flags names like `__hx_static_get__x`; prefer `__hx_static_get_x`.
		return StringTools.startsWith(rustName, "_") ? (prefix + rustName) : (prefix + "_" + rustName);
	}

	/**
		Returns the callable Rust path for a generated static-field helper.

		Why
		- Non-main Haxe classes emit into `src/<module>.rs`, so helpers live at
		  `crate::<module>::__hx_static_get_*`.
		- The main Haxe class emits directly into `src/main.rs`; there is no `crate::main` module.

		What
		- Returns `crate::<helper>` for the main class and `crate::<module>::<helper>` otherwise.

		How
		- Static field read/write lowering uses this for both getters and setters so root-main and
		  non-main modules share one path rule.
	**/
	function staticVarHelperPath(owner:ClassType, helperName:String):String {
		if (mainClassKey != null && classKey(owner) == mainClassKey)
			return "crate::" + helperName;
		return "crate::" + rustModulePathForClass(owner) + "::" + helperName;
	}

	/**
		Return a safe inline initializer for a read-only static literal.

		Why
		- Haxe lowers `static final LABEL = "x"` to a read-only static field.
		- Reflaxe's curated static-var storage list may not include that field, so calling a generated
		  helper can produce an invalid path or an undefined helper.

		What
		- Accepts only literal constants through harmless metadata/parenthesis/cast wrappers.
		- Rejects arrays, objects, constructors, calls, and other values whose identity or effects should
		  be preserved by generated static storage.

		How
		- Static field read lowering inlines the returned expression.
		- Non-literal finals remain a future storage-admission problem rather than being silently
		  converted into fresh values at every read.
	**/
	function staticReadOnlyConstantExpr(cf:ClassField):Null<TypedExpr> {
		if (cf == null)
			return null;
		switch (cf.kind) {
			case FVar(_, AccNever):
			case _:
				return null;
		}

		var init:Null<TypedExpr> = null;
		try
			init = cf.expr()
		catch (_:haxe.Exception) {}
		if (init == null)
			return null;

		function unwrapConst(e:TypedExpr):Null<TypedExpr> {
			var u = unwrapMetaParen(e);
			return switch (u.expr) {
				case TConst(_):
					u;
				case TCast(inner, _):
					unwrapConst(inner);
				case _:
					null;
			}
		}

		return unwrapConst(init);
	}

	function metaNameEquals(actual:String, expected:String):Bool {
		return actual == expected || actual == (":" + expected);
	}

	function metaHasAny(meta:haxe.macro.Type.MetaAccess, names:Array<String>):Bool {
		if (meta == null || names == null || names.length == 0)
			return false;
		for (entry in meta.get()) {
			for (name in names) {
				if (metaNameEquals(entry.name, name))
					return true;
			}
		}
		return false;
	}

	/**
		Rejects `@:rustNativeWrapper` until the native-wrapper generator has a stable contract.

		Why
		- M94 defines the proposed wrapper facility shape, but accepting metadata silently would
		  make users think the generator exists and could create misleading facade evidence.
		- Native facade helpers are part of the Rust authority boundary, so unsupported wrapper
		  declarations must fail early at the metadata site instead of degrading to ignored metadata.

		What
		- Reserves `@:rustNativeWrapper(...)` across classes, enums, typedefs, and abstracts.
		- Emits an actionable diagnostic that points users back to `@:rustExtraSrc` plus the
		  native facade manifest until a future bead lands an audited generator.

		How
		- Walks typed module metadata from `Context.getAllModuleTypes()`.
		- Uses the same metadata-name normalization as other Rust metadata readers.
		- Does not parse the proposed object shape here; parsing belongs to the future generator
		  once the accepted subset and emitted Rust contract are implemented together.
	**/
	function rejectReservedNativeWrapperMetadata():Void {
		for (moduleType in Context.getAllModuleTypes()) {
			switch (moduleType) {
				case TClassDecl(clsRef):
					rejectReservedNativeWrapperMeta(clsRef.get().meta);
				case TEnumDecl(enRef):
					rejectReservedNativeWrapperMeta(enRef.get().meta);
				case TTypeDecl(tdRef):
					rejectReservedNativeWrapperMeta(tdRef.get().meta);
				case TAbstract(abRef):
					rejectReservedNativeWrapperMeta(abRef.get().meta);
			}
		}
	}

	function rejectReservedNativeWrapperMeta(meta:haxe.macro.Type.MetaAccess):Void {
		if (meta == null)
			return;
		for (entry in meta.get()) {
			if (!metaNameEquals(entry.name, "rustNativeWrapper"))
				continue;
			Context.error("`@:rustNativeWrapper` is reserved for the native wrapper facility spike and is not enabled as product metadata. "
				+ "Use `@:rustExtraSrc` plus a native facade manifest entry for now; see docs/native-wrapper-facility-spike.md.", entry.pos);
		}
	}

	function hasRustTestMeta(meta:haxe.macro.Type.MetaAccess):Bool {
		return metaHasAny(meta, ["rustTest"]);
	}

	/**
		Collects Haxe-authored Rust test declarations (`@:rustTest`) from typed modules.

		Why
		- We want application tests to stay in typed Haxe while still integrating with `cargo test`.
		- Keeping the collection centralized lets us validate constraints once and emit deterministic
		  wrappers in the main crate module.

		What
		- Accepts `@:rustTest` on `public static` methods with zero params and return type `Void` or `Bool`.
		- Supports optional metadata parameter:
		  - string: custom Rust wrapper name
		  - object: `{ name: String, serial: Bool }`

		How
		- Walks `Context.getAllModuleTypes()`.
		- Validates each candidate at compile-time and records a typed `RustTestSpec`.
		- Wrapper names are snake-cased and de-duplicated deterministically via `RustNaming.stableUnique`.
	**/
	function collectRustTests():Void {
		var pending:Array<{
			classType:ClassType,
			field:ClassField,
			wrapperBase:String,
			serial:Bool,
			returnKind:RustTestReturnKind,
			pos:haxe.macro.Expr.Position
		}> = [];

		function readConstString(e:Expr):Null<String> {
			return switch (unwrapMetaExpr(e).expr) {
				case EConst(CString(s, _)): s;
				case _: null;
			};
		}

		function readConstBool(e:Expr):Null<Bool> {
			return switch (unwrapMetaExpr(e).expr) {
				case EConst(CIdent("true")): true;
				case EConst(CIdent("false")): false;
				case _: null;
			};
		}

		function readRustTestConfig(cf:ClassField):Null<{nameOverride:Null<String>, serial:Bool}> {
			if (cf.meta == null || !hasRustTestMeta(cf.meta))
				return null;

			var cfg = {nameOverride: null, serial: true};
			var seen = 0;
			for (entry in cf.meta.get()) {
				if (!metaNameEquals(entry.name, "rustTest"))
					continue;
				seen++;
				if (seen > 1) {
					#if eval
					RustDiagnostic.error(RustDiagnosticId.MetadataArity, "`@:rustTest` can only be declared once per method.", entry.pos);
					#end
					continue;
				}

				if (entry.params == null || entry.params.length == 0)
					continue;

				if (entry.params.length != 1) {
					#if eval
					RustDiagnostic.error(RustDiagnosticId.MetadataArity,
						"`@:rustTest` accepts no params or a single string/object parameter.", entry.pos);
					#end
					continue;
				}

				var param = unwrapMetaExpr(entry.params[0]);
				switch (param.expr) {
					case EConst(CString(s, _)):
						cfg.nameOverride = StringTools.trim(s);
					case EObjectDecl(fields):
						for (field in fields) {
							switch (field.field) {
								case "name":
									var nameValue = readConstString(field.expr);
									if (nameValue == null) {
										#if eval
										RustDiagnostic.error(RustDiagnosticId.MetadataValue,
											"`@:rustTest` field `name` must be a compile-time string.", field.expr.pos);
										#end
										continue;
									}
									cfg.nameOverride = StringTools.trim(nameValue);
								case "serial":
									var serialValue = readConstBool(field.expr);
									if (serialValue == null) {
										#if eval
										RustDiagnostic.error(RustDiagnosticId.MetadataValue,
											"`@:rustTest` field `serial` must be a compile-time bool.", field.expr.pos);
										#end
										continue;
									}
									cfg.serial = serialValue;
								case _:
									#if eval
									RustDiagnostic.error(RustDiagnosticId.MetadataValue,
										"`@:rustTest` only supports `name` and `serial` fields.", field.expr.pos);
									#end
							}
						}
					case _:
						#if eval
						RustDiagnostic.error(RustDiagnosticId.MetadataValue,
							"`@:rustTest` parameter must be a string name or object `{ name, serial }`.", entry.pos);
						#end
				}
			}
			return cfg;
		}

		for (moduleType in Context.getAllModuleTypes()) {
			switch (moduleType) {
				case TClassDecl(clsRef):
					var cls = clsRef.get();
					if (cls == null || cls.isExtern)
						continue;

					var isMain = isMainClass(cls);
					if (!shouldEmitClass(cls, isMain))
						continue;

					for (cf in cls.statics.get()) {
						switch (cf.kind) {
							case FMethod(_):
							case _:
								continue;
						}

						var cfg = readRustTestConfig(cf);
						if (cfg == null)
							continue;

						if (isMain) {
							#if eval
							RustDiagnostic.error(RustDiagnosticId.MetadataPlacement,
								"`@:rustTest` methods must live in non-main classes so wrappers can call `crate::<module>::Type::method`.", cf.pos);
							#end
							continue;
						}

						if (!cf.isPublic) {
							#if eval
							RustDiagnostic.error(RustDiagnosticId.MetadataPlacement,
								"`@:rustTest` methods must be `public static` so generated wrappers can call them.", cf.pos);
							#end
							continue;
						}

						var returnKind:Null<RustTestReturnKind> = null;
						switch (followType(cf.type)) {
							case TFun(params, ret):
								if (params.length != 0) {
									#if eval
									RustDiagnostic.error(RustDiagnosticId.MetadataPlacement,
										"`@:rustTest` methods must have zero parameters.", cf.pos);
									#end
									continue;
								}

								if (TypeHelper.isVoid(ret)) {
									returnKind = TestVoid;
								} else if (TypeHelper.isBool(ret)) {
									returnKind = TestBool;
								} else {
									#if eval
									RustDiagnostic.error(RustDiagnosticId.MetadataPlacement,
										"`@:rustTest` methods must return `Void` or `Bool` (got `" + TypeTools.toString(ret) + "`).", cf.pos);
									#end
									continue;
								}
							case _:
								#if eval
								RustDiagnostic.error(RustDiagnosticId.MetadataPlacement, "`@:rustTest` can only be used on methods.", cf.pos);
								#end
								continue;
						}

						var baseName = cfg.nameOverride;
						if (baseName == null || baseName.length == 0) {
							var prefix = cls.pack.length > 0 ? (cls.pack.join("_") + "_") : "";
							baseName = prefix + cls.name + "_" + cf.getHaxeName();
						}
						baseName = RustNaming.snakeIdent(baseName);
						if (baseName == null || baseName.length == 0)
							baseName = "hx_test";

						pending.push({
							classType: cls,
							field: cf,
							wrapperBase: baseName,
							serial: cfg.serial,
							returnKind: returnKind,
							pos: cf.pos
						});
					}
				case _:
			}
		}

		pending.sort((a, b) -> {
			var ak = classKey(a.classType) + "." + a.field.getHaxeName();
			var bk = classKey(b.classType) + "." + b.field.getHaxeName();
			return compareStrings(ak, bk);
		});

		var used:Map<String, Bool> = [];
		for (p in pending) {
			var wrapper = RustNaming.stableUnique(p.wrapperBase, used);
			rustTestSpecs.push({
				classType: p.classType,
				field: p.field,
				wrapperName: wrapper,
				serial: p.serial,
				returnKind: p.returnKind,
				pos: p.pos
			});
		}
	}

	/**
		Renders the Rust `#[cfg(test)]` module for collected Haxe tests.

		Why
		- Rust's test harness requires `#[test]` functions at crate/module scope.
		- Generated wrappers keep app tests authored in Haxe while preserving native Rust test UX.

		How
		- Emits `mod __hx_tests` in `main.rs`.
		- Each wrapper calls the compiled Haxe static method.
		- `Bool` tests emit `assert!(...)`; `Void` tests succeed if no exception/panic occurs.
		- `serial=true` tests acquire a shared `Mutex` guard to keep stateful harness tests deterministic.
	**/
	function renderRustTestModule():Null<String> {
		if (rustTestSpecs == null || rustTestSpecs.length == 0)
			return null;

		var tests = rustTestSpecs.copy();
		tests.sort((a, b) -> compareStrings(a.wrapperName, b.wrapperName));

		var hasSerial = false;
		for (spec in tests) {
			if (spec.serial) {
				hasSerial = true;
				break;
			}
		}

		var lines:Array<String> = [];
		lines.push("#[cfg(test)]");
		lines.push("mod __hx_tests {");
		if (hasSerial) {
			lines.push("\tuse std::sync::{Mutex, OnceLock};");
			lines.push("");
			lines.push("\tfn __hx_test_lock() -> &'static Mutex<()> {");
			lines.push("\t\tstatic LOCK: OnceLock<Mutex<()>> = OnceLock::new();");
			lines.push("\t\tLOCK.get_or_init(|| Mutex::new(()))");
			lines.push("\t}");
			lines.push("");
		}

		for (spec in tests) {
			var methodPath = "crate::" + rustModulePathForClass(spec.classType) + "::" + rustTypeNameForClass(spec.classType) + "::"
				+ rustMethodName(spec.classType, spec.field);

			lines.push("\t#[test]");
			lines.push("\tfn " + spec.wrapperName + "() {");
			if (spec.serial) {
				lines.push("\t\tlet _guard = __hx_test_lock().lock().unwrap_or_else(|e| e.into_inner());");
			}
			switch (spec.returnKind) {
				case TestBool:
					lines.push("\t\tassert!(" + methodPath + "());");
				case TestVoid:
					lines.push("\t\t" + methodPath + "();");
			}
			lines.push("\t}");
			lines.push("");
		}

		while (lines.length > 0 && StringTools.trim(lines[lines.length - 1]).length == 0) {
			lines.pop();
		}
		lines.push("}");
		return lines.join("\n");
	}

	function hasAsyncFunctionMeta(meta:haxe.macro.Type.MetaAccess):Bool {
		return metaHasAny(meta, ["async", "rustAsync"]);
	}

	function isAwaitMetaName(name:String):Bool {
		return name == ":await" || name == "await" || name == ":rustAwait" || name == "rustAwait";
	}

	function ensureAsyncAllowed(pos:haxe.macro.Expr.Position):Void {
		if (!asyncEnabled()) {
			#if eval
			RustDiagnostic.error(RustDiagnosticId.AsyncNotEnabled, "Async support requires `-D rust_async`.", pos);
			#end
			return;
		}
		if (!ProfileResolver.isRustFirst(profile)) {
			#if eval
			RustDiagnostic.error(RustDiagnosticId.AsyncRequiresMetal, "Async currently requires `-D reflaxe_rust_profile=metal`.", pos);
			#end
		}
		if (noHxrtEnabled()) {
			#if eval
			RustDiagnostic.error(RustDiagnosticId.AsyncNoHxrt,
				"Async is incompatible with `-D rust_no_hxrt`; async lowering currently depends on `hxrt::async_`.", pos);
			#end
		}
	}

	function isRustAsyncClass(cls:ClassType):Bool {
		if (cls == null)
			return false;
		var packPath = cls.pack != null ? cls.pack.join(".") : "";
		var fullPath = (packPath.length > 0 ? packPath + "." : "") + cls.name;
		if ((cls.name == "Async" && packPath == "rust.async") || fullPath == "hxrt.async_" || fullPath == "hxrt::async_")
			return true;
		var nativePath = rustExternBasePath(cls);
		return nativePath == "hxrt::async_";
	}

	function isRustAsyncFutureClass(cls:ClassType):Bool {
		if (cls == null)
			return false;
		var packPath = cls.pack != null ? cls.pack.join(".") : "";
		var fullPath = (packPath.length > 0 ? packPath + "." : "") + cls.name;
		if ((cls.name == "Future" && packPath == "rust.async")
			|| fullPath == "hxrt.async_.HxFuture"
			|| fullPath == "hxrt::async_::HxFuture")
			return true;
		var nativePath = rustExternBasePath(cls);
		return nativePath == "hxrt::async_::HxFuture";
	}

	/**
		Returns whether a class is the Rust-native socket-address facade.

		Why
		- `rust.net.SocketAddr` is an extern Haxe type, but its simplest methods should not require
		  handwritten Rust helper bodies once the compiler can express their closed `std::net` shape.
		- The retained helper is only the private wrapper/conversion boundary used by TCP/UDP owners.

		What
		- Recognizes the public Haxe facade and its native Rust wrapper path.

		How
		- Prefer the Haxe package/name for stability, with the `@:native` path as a packaged-layout
		  fallback.
	**/
	function isRustNetSocketAddrClass(cls:ClassType):Bool {
		if (cls == null)
			return false;
		var packPath = cls.pack != null ? cls.pack.join(".") : "";
		if (cls.name == "SocketAddr" && packPath == "rust.net")
			return true;
		return rustExternBasePath(cls) == "crate::native_socket_addr_tools::SocketAddr";
	}

	/**
		Compile `SocketAddr.localhost(...)` and `localhostDetailed(...)` directly into Rust AST.

		Why
		- Port range checking and loopback address construction are pure functions of a typed `Int`.
		  Keeping those bodies in `native_socket_addr_tools.rs` made the helper look like a second
		  runtime surface instead of a narrow wrapper/conversion island.
		- The compiler already has enough typed call-site information to emit the exact `std::net`
		  operations without raw snippets or `hxrt`.

		What
		- Emits a single-evaluation port binding, `u16::try_from(...)` validation, direct
		  `SocketAddrV4::new(Ipv4Addr::LOCALHOST, ...)` construction, and a final conversion through
		  `SocketAddr::from_std(...)`.
		- The detailed variant maps invalid ports to `SocketError::invalid_input(...)`; the String
		  variant returns the same formatted message as a plain Rust `String`.

		How
		- The helper wrapper remains responsible only for private storage and crate-local conversions.
		  This lowering uses `from_std` because Haxe externs still cannot construct the private Rust
		  field directly.
	**/
	function compileRustSocketAddrLocalhostCall(portExpr:TypedExpr, detailed:Bool):RustExpr {
		var portValue = "__hx_socket_port_value";
		var port = "__hx_socket_port";
		var portRead = EPath(portValue);
		var stdAddr = ECall(EField(ECall(EPath("std::net::SocketAddrV4::new"), [
			EPath("std::net::Ipv4Addr::LOCALHOST"),
			EPath(port)
		]), "into"), []);
		var okValue = ECall(EPath("crate::native_socket_addr_tools::SocketAddr::from_std"), [stdAddr]);
		var errMessage = EMacroCall("format", [ELitString("socket port out of range: {}"), portRead]);
		var errValue = detailed ? ECall(EPath("crate::native_socket_error_tools::SocketError::invalid_input"), [errMessage]) : errMessage;

		return EBlock({
			stmts: [RLet(portValue, false, RI32, compileExpr(portExpr))],
			tail: EMatch(ECall(EPath("u16::try_from"), [portRead]), [
				{pat: PTupleStruct("Result::Ok", [PBind(port)]), expr: ECall(EPath("Result::Ok"), [okValue])},
				{pat: PTupleStruct("Result::Err", [PWildcard]), expr: ECall(EPath("Result::Err"), [errValue])}
			])
		});
	}

	/**
		Compile `SocketAddr.port()` as a direct Rust stdlib accessor.

		Why
		- Reading the port from a typed socket address is a pure `std::net::SocketAddr` operation.
		  It should not keep a public helper method alive when the only unavoidable native boundary is
		  the wrapper's private representation.

		What
		- Emits `i32::from(addr.as_std().port())`, preserving Haxe's `Int` result type.

		How
		- The receiver is bound once, then borrowed through the retained crate-private `as_std()`
		  conversion. This keeps the generated call site inspectable while avoiding direct access to
		  the helper's private field.
	**/
	function compileRustSocketAddrPortCall(receiver:TypedExpr):RustExpr {
		var recvName = "__hx_socket_addr";
		var portRead = ECall(EField(ECall(EField(EPath(recvName), "as_std"), []), "port"), []);
		return EBlock({
			stmts: [RLet(recvName, false, null, compileExpr(receiver))],
			tail: ECall(EPath("i32::from"), [portRead])
		});
	}

	function rustFutureInnerType(t:Type):Null<Type> {
		function resolve(cur:Type):Null<Type> {
			if (cur == null)
				return null;
			return switch (cur) {
				case TInst(clsRef, params):
					var cls = clsRef.get();
					if (params != null && params.length == 1) {
						if (isRustAsyncFutureClass(cls))
							params[0];
						else {
							var tStr = TypeTools.toString(cur);
							if (StringTools.startsWith(tStr, "rust.async.Future<")
								|| StringTools.startsWith(tStr, "hxrt::async_::HxFuture<"))
								params[0]
							else
								null;
						}
					} else {
						null;
					}
				case TType(typeRef, params):
					var tt = typeRef.get();
					if (tt == null) {
						null;
					} else {
						var under:Type = tt.type;
						if (tt.params != null && tt.params.length > 0 && params != null && params.length == tt.params.length) {
							under = TypeTools.applyTypeParameters(under, tt.params, params);
						}
						resolve(under);
					}
				case TAbstract(absRef, params):
					var abs = absRef.get();
					if (params != null && params.length == 1) {
						var absPath = (abs.pack != null && abs.pack.length > 0 ? abs.pack.join(".") + "." : "") + abs.name;
						if (absPath == "rust.async.Future" || absPath == "hxrt::async_.HxFuture")
							params[0]
						else
							null;
					} else {
						null;
					}
				case TLazy(f):
					resolve(f());
				case _:
					null;
			}
		}

		var fromDirect = resolve(t);
		if (fromDirect != null)
			return fromDirect;
		var fromFollow = resolve(followType(t));
		if (fromFollow != null)
			return fromFollow;
		return null;
	}

	function isRustFutureType(t:Type):Bool {
		return rustFutureInnerType(t) != null;
	}

	function extractAsyncReadyValue(expr:TypedExpr):Null<TypedExpr> {
		var cur = expr;
		while (true) {
			switch (cur.expr) {
				case TMeta(_, inner):
					cur = inner;
					continue;
				case TParenthesis(inner):
					cur = inner;
					continue;
				case _:
			}
			break;
		}
		return switch (cur.expr) {
			case TCall(callExpr, args) if (args.length == 1):
				switch (callExpr.expr) {
					case TField(_, FStatic(clsRef, fieldRef)):
						var cls = clsRef.get();
						var field = fieldRef.get();
						if (isRustAsyncClass(cls) && field.getHaxeName() == "ready") args[0] else null;
					case _:
						null;
				}
			case _:
				null;
		}
	}

	function rustAccessorSuffix(classType:ClassType, cf:ClassField):String {
		// Keep accessors warning-free (`non_snake_case`) even when a field name starts with `_`
		// (common for private backing fields like `_x`).
		var name = rustFieldName(classType, cf);
		var underscoreCount = 0;
		while (StringTools.startsWith(name, "_")) {
			underscoreCount++;
			name = name.substr(1);
		}
		if (name.length == 0)
			name = "field";
		return underscoreCount == 0 ? name : ("u" + underscoreCount + "_" + name);
	}

	function rustGetterName(classType:ClassType, cf:ClassField):String {
		return "__hx_get_" + rustAccessorSuffix(classType, cf);
	}

	function rustSetterName(classType:ClassType, cf:ClassField):String {
		return "__hx_set_" + rustAccessorSuffix(classType, cf);
	}

	function isAccessorForPublicPropertyInstance(classType:ClassType, accessorField:ClassField):Bool {
		var name = accessorField.getHaxeName();
		if (name == null)
			return false;
		if (classType.fields == null)
			return false;

		inline function propUsesAccessor(prop:ClassField, kind:String):Bool {
			if (!prop.isPublic)
				return false;
			return switch (prop.kind) {
				case FVar(read, write): (kind == "get" && read == AccCall) || (kind == "set" && write == AccCall);
				case _:
					false;
			}
		}

		if (StringTools.startsWith(name, "get_")) {
			var propName = name.substr(4);
			var cur:Null<ClassType> = classType;
			while (cur != null) {
				for (cf in cur.fields.get())
					if (cf.getHaxeName() == propName)
						return propUsesAccessor(cf, "get");
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
		}
		if (StringTools.startsWith(name, "set_")) {
			var propName = name.substr(4);
			var cur:Null<ClassType> = classType;
			while (cur != null) {
				for (cf in cur.fields.get())
					if (cf.getHaxeName() == propName)
						return propUsesAccessor(cf, "set");
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
		}
		return false;
	}

	function isAccessorForPublicPropertyStatic(classType:ClassType, accessorField:ClassField):Bool {
		var name = accessorField.getHaxeName();
		if (name == null)
			return false;
		if (classType.statics == null)
			return false;

		inline function propUsesAccessor(prop:ClassField, kind:String):Bool {
			if (!prop.isPublic)
				return false;
			return switch (prop.kind) {
				case FVar(read, write): (kind == "get" && read == AccCall) || (kind == "set" && write == AccCall);
				case _:
					false;
			}
		}

		if (StringTools.startsWith(name, "get_")) {
			var propName = name.substr(4);
			var cur:Null<ClassType> = classType;
			while (cur != null) {
				for (cf in cur.statics.get())
					if (cf.getHaxeName() == propName)
						return propUsesAccessor(cf, "get");
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
		}
		if (StringTools.startsWith(name, "set_")) {
			var propName = name.substr(4);
			var cur:Null<ClassType> = classType;
			while (cur != null) {
				for (cf in cur.statics.get())
					if (cf.getHaxeName() == propName)
						return propUsesAccessor(cf, "set");
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
		}
		return false;
	}

	function resolveToAbsolutePath(p:String):String {
		var full = p;
		if (!Path.isAbsolute(full)) {
			full = Path.join([Sys.getCwd(), full]);
		}
		return Path.normalize(full);
	}

	function getUserClassesForModules():Array<ClassType> {
		var out:Array<ClassType> = [];
		var seen = new Map<String, Bool>();

		for (mt in Context.getAllModuleTypes()) {
			switch (mt) {
				case TClassDecl(clsRef):
					{
						var cls = clsRef.get();
						if (cls == null)
							continue;
						if (isMainClass(cls))
							continue;
						if (!shouldEmitClass(cls, false))
							continue;

						var key = classKey(cls);
						if (seen.exists(key))
							continue;
						seen.set(key, true);
						out.push(cls);
					}
				case _:
			}
		}

		out.sort((a, b) -> {
			var ka = classKey(a);
			var kb = classKey(b);
			return ka < kb ? -1 : (ka > kb ? 1 : 0);
		});
		return out;
	}

	/**
		Builds the set of emitted classes that participate in runtime subtype-id checks.

		Why
		- `Std.isOfType(value:Dynamic, SomeClass)` needs a crate-level subtype helper for values that
		  crossed the `Dynamic` boundary with only runtime type-id metadata.
		- The helper must include the main class too, because `getUserClassesForModules()` excludes it.

		What
		- Returns all classes that this compile emits as Rust modules (user + framework std overrides),
		  including the main class.

		How
		- Scans `Context.getAllModuleTypes()`, reuses `shouldEmitClass(...)`, and deduplicates by class key.
	**/
	function getEmittedClassesForTypeIdRegistry():Array<ClassType> {
		var out:Array<ClassType> = [];
		var seen = new Map<String, Bool>();

		for (mt in Context.getAllModuleTypes()) {
			switch (mt) {
				case TClassDecl(clsRef):
					{
						var cls = clsRef.get();
						if (cls == null)
							continue;
						var isMain = isMainClass(cls);
						if (!shouldEmitClass(cls, isMain))
							continue;

						var key = classKey(cls);
						if (seen.exists(key))
							continue;
						seen.set(key, true);
						out.push(cls);
					}
				case _:
			}
		}

		out.sort((a, b) -> compareStrings(classKey(a), classKey(b)));
		return out;
	}

	/**
		Reports whether this compilation needs the closed reflection registry.

		Why
		- Emitting lookup tables into every crate would add dead generated code to programs that never use
		  dynamic reflection.
		- Recording usage only while files are emitted is order-sensitive: a non-main module may be emitted
		  after `main.rs`, where the crate-root helpers live.

		What
		- Detects runtime-handle forms of the admitted `Type` operations across the complete emitted-class
		  graph before root emission.
		- Static `TTypeExpr` name/constructor queries remain direct compiler constants and do not require a
		  registry.

		How
		- Reuses the existing class-emission policy, then walks those initializers and field bodies with
		  `TypedExprTools`; merely typing an unused upstream std helper cannot activate the registry.
		- Caches the answer for the compilation so output order cannot change the generated contract.
	**/
	function needsReflectionSupport():Bool {
		if (cachedNeedsReflectionSupport != null)
			return cachedNeedsReflectionSupport;

		function isRegistryCall(expr:TypedExpr):Bool {
			return switch (expr.expr) {
				case TCall(callTarget, args):
					switch (callTarget.expr) {
						case TField(_, FStatic(classRef, fieldRef)): {
								var classType = classRef.get();
								var field = fieldRef.get();
								if (classType == null || field == null || classType.pack.length != 0 || classType.name != "Type")
									false;
								else switch (field.name) {
									case "resolveClass" | "resolveEnum": true;
									case "getClassName" | "getEnumName" | "getEnumConstructs":
										args.length != 1 || switch (unwrapMetaParen(args[0]).expr) {
											case TTypeExpr(_): false;
											case _: true;
										};
									case "createEmptyInstance" | "createEnum": true;
									case _: false;
								}
							}
						case _: false;
					}
				case _: false;
			}
		}

		function expressionNeedsRegistry(root:Null<TypedExpr>):Bool {
			if (root == null)
				return false;
			var found = false;
			function visit(expr:TypedExpr):Void {
				if (found)
					return;
				if (isRegistryCall(expr)) {
					found = true;
					return;
				}
				TypedExprTools.iter(expr, visit);
			}
			visit(root);
			return found;
		}

		function fieldNeedsRegistry(field:ClassField):Bool {
			var expression:Null<TypedExpr> = null;
			try
				expression = field.expr()
			catch (_:haxe.Exception) {}
			return expressionNeedsRegistry(expression);
		}

		var found = false;
		for (classType in getEmittedClassesForTypeIdRegistry()) {
			if (found)
				break;
			if (expressionNeedsRegistry(classType.init)) {
				found = true;
				continue;
			}
			if (classType.constructor != null && fieldNeedsRegistry(classType.constructor.get())) {
				found = true;
				continue;
			}
			for (field in classType.fields.get().concat(classType.statics.get())) {
				if (fieldNeedsRegistry(field)) {
					found = true;
					break;
				}
			}
		}

		cachedNeedsReflectionSupport = found;
		return found;
	}

	/**
		Returns the validated immutable reflection plan for this compilation.

		Why
		- Name and type-id ambiguity cannot be repaired at runtime without choosing a declaration
		  nondeterministically.

		What
		- Reuses the compiler's existing FNV type identity and reports the first deterministic planning
		  issue through the stable reflection diagnostic family.

		How
		- The pure planner owns inventory/name/constructor ordering; this method owns macro diagnostics.
	**/
	function getReflectionRegistryPlan():ReflectionRegistryPlanData {
		if (cachedReflectionRegistryPlan == null) {
			cachedReflectionRegistryPlan = ReflectionRegistryPlan.build(Context.getAllModuleTypes(), fnv1a32);
			if (cachedReflectionRegistryPlan.issues.length > 0) {
				var issue = cachedReflectionRegistryPlan.issues[0];
				RustDiagnostic.error(RustDiagnosticId.ReflectionRegistryCollision, issue.message, issue.pos);
			}
		}
		return cachedReflectionRegistryPlan;
	}

	inline function haxeRuntimeTypeName(pack:Array<String>, name:String):String {
		return pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	function reflectionStringArrayExpr(values:Array<String>):RustExpr {
		var stringType = rustStringTypePath();
		var elements = values.map(value -> stringLiteralExpr(value));
		return ECall(EPath("hxrt::array::Array::<" + stringType + ">::from_vec"), [EMacroCall("vec", elements)]);
	}

	function enumConstructorNames(enumType:EnumType):Array<String> {
		var fields:Array<{name:String, index:Int}> = [];
		for (name in enumType.constructs.keys()) {
			var field = enumType.constructs.get(name);
			if (field != null)
				fields.push({name: field.name, index: field.index});
		}
		fields.sort((left, right) -> left.index == right.index ? compareStrings(left.name, right.name) : left.index - right.index);
		return fields.map(field -> field.name);
	}

	/**
		Rejects an experimental dynamic-construction operation at an application callsite.

		Why
		- Accepting source and emitting `todo!()`, a fake null, or a partially initialized value turns an
		  unsupported feature into a runtime process-panic or semantic corruption risk.
		- Upstream `haxe.Unserializer` contains generic calls that must remain compilable while its dynamic
		  class/enum-construction branches stay explicitly experimental.

		What
		- Application calls receive the stable reflection diagnostic at their own source position.
		- Framework-owned calls continue to compilation and are lowered by
		  `unsupportedReflectionRuntimeExpr(...)` to a Haxe-catchable error if reached.

		How
		- Uses the existing source-ownership boundary; it does not inspect or special-case application
		  names, modules, or call syntax.
	**/
	function rejectApplicationReflectionOperation(operation:String, fullExpr:TypedExpr):Void {
		var sourceFile = sourceFileForPosition(fullExpr.pos);
		if (sourceFile != null && sourceFile.length > 0 && isUserProjectFile(sourceFile)) {
			RustDiagnostic.error(RustDiagnosticId.ReflectionUnsupported,
				operation + " is outside the admitted reflection contract. Use a typed constructor/direct enum constructor, or keep this dynamic path experimental.",
				fullExpr.pos);
		}
	}

	/**
		Converts an accepted `Class<T>` / `Enum<T>` carrier into its compiler-owned type id.

		Why
		- Haxe's own standard library sometimes narrows a `Dynamic` value with `Std.isOfType(...)` and
		  then passes that same value to `Type.getClassName(...)` or `Type.getEnumName(...)`.
		- The Rust target represents typed class/enum carriers directly as `u32`, while a value whose
		  Haxe static type remains `Dynamic` is an `hxrt::dynamic::Dynamic` box.
		- Adding a general runtime reflection helper would duplicate a fact and representation already
		  owned by compiler lowering.

		What
		- Leaves typed carriers as their direct `u32` expression.
		- Downcasts a `Dynamic` carrier to `u32` exactly once and raises a Haxe-catchable error when the
		  runtime value is not a class/enum handle.

		How
		- Uses typed Rust `let` and `match` AST nodes; no raw Rust fragment or new `hxrt` API is needed.
	**/
	function reflectionHandleExpr(value:TypedExpr, operation:String):RustExpr {
		var compiled = compileExpr(value);
		if (!mapsToRustDynamic(value.t, value.pos))
			return compiled;

		var handleName = "__hx_reflection_handle";
		var typeIdName = "__hx_reflection_type_id";
		var downcast = ECall(EField(EPath(handleName), "downcast_ref::<u32>"), []);
		var invalidMessage = operation + " expected a Class or Enum handle";
		return EBlock({
			stmts: [RLet(handleName, false, null, compiled)],
			tail: EMatch(downcast, [
				{pat: PTupleStruct("Some", [PBind(typeIdName)]), expr: EUnary("*", EPath(typeIdName))},
				{
					pat: PPath("None"),
					expr: ECall(EPath("crate::__hx_unsupported_reflection::<u32>"), [stringLiteralExpr(invalidMessage)])
				}
			])
		});
	}

	function unsupportedReflectionRuntimeExpr(operation:String, args:Array<TypedExpr>, fullExpr:TypedExpr):RustExpr {
		var statements:Array<RustStmt> = [];
		for (arg in args)
			statements.push(RLet("_", false, null, compileExpr(arg)));
		var returnType = rustTypeToString(toRustType(fullExpr.t, fullExpr.pos));
		var message = stringLiteralExpr(operation + " is unavailable in the current experimental dynamic-reflection path");
		return EBlock({
			stmts: statements,
			tail: ECall(EPath("crate::__hx_unsupported_reflection::<" + returnType + ">"), [message])
		});
	}

	/**
		Emits typed crate-root helpers for the admitted closed reflection operations.

		Why
		- Runtime lookup is required only for string names and opaque `Class<T>` / `Enum<T>` ids.
		- The registry is generated code, not runtime-owned state; it must remain deterministic and free of
		  raw `todo!()`/sentinel implementations.

		What
		- Emits name-to-id, id-to-name, and enum-id-to-constructor-list functions.
		- Unknown names map to the existing `0u32` nullable handle representation. Unknown ids return the
		  target String null/default and unknown enum ids return an empty array; Haxe documents null-handle
		  inputs to the corresponding name/constructor operations as unspecified.

		How
		- Uses typed Rust match AST nodes and the canonical String/Array lowering primitives.
		- Public entries and constructor order come solely from `ReflectionRegistryPlan`.
	**/
	function emitReflectionRegistryFns():Array<RustItem> {
		var plan = getReflectionRegistryPlan();
		var stringType = rustStringType();
		var stringArrayType = rustRelativeType(["hxrt", "array", "Array"], [stringType]);

		function reflectionFunctionItem(name:String, argName:String, argType:RustType, returnType:RustType,
			arms:Array<RustMatchArm>, defaultExpr:RustExpr):RustItem {
			arms.push({pat: PWildcard, expr: defaultExpr});
			return RFn({
				name: name,
				isPub: false,
				vis: VPubCrate,
				generics: RustGenericParameters.empty(),
				args: [{name: argName, ty: argType}],
				ret: returnType,
				body: {stmts: [], tail: EMatch(EPath(argName), arms)}
			});
		}

		var resolveClassArms:Array<RustMatchArm> = plan.classes.map(entry -> ({
			pat: PLitString(entry.runtimeName),
			expr: typeIdExprForKey(entry.stableKey)
		} : RustMatchArm));
		var resolveEnumArms:Array<RustMatchArm> = plan.enums.map(entry -> ({
			pat: PLitString(entry.runtimeName),
			expr: typeIdExprForKey(entry.stableKey)
		} : RustMatchArm));
		var classNameArms:Array<RustMatchArm> = plan.classes.map(entry -> ({
			pat: PPath(typeIdLiteralForKey(entry.stableKey)),
			expr: stringLiteralExpr(entry.runtimeName)
		} : RustMatchArm));
		var enumNameArms:Array<RustMatchArm> = plan.enums.map(entry -> ({
			pat: PPath(typeIdLiteralForKey(entry.stableKey)),
			expr: stringLiteralExpr(entry.runtimeName)
		} : RustMatchArm));
		var enumConstructArms:Array<RustMatchArm> = plan.enums.map(entry -> ({
			pat: PPath(typeIdLiteralForKey(entry.stableKey)),
			expr: reflectionStringArrayExpr(entry.constructors)
		} : RustMatchArm));
		var unsupportedReflection = RFn({
			name: "__hx_unsupported_reflection",
			isPub: false,
			vis: VPubCrate,
			generics: RustGenericParameters.of([GenericTypeParam(RustIdentifier.named("T"), [], null)]),
			args: [{name: "operation", ty: stringType}],
			ret: rustNamedType("T"),
			body: {
				stmts: [],
				tail: ECall(EPath("hxrt::exception::throw"), [ECall(EPath("hxrt::dynamic::from"), [EPath("operation")])])
			}
		});

		return [
			unsupportedReflection,
			reflectionFunctionItem("__hx_resolve_class_name", "name", RBorrow(rustNamedType("str"), false, null), rustNamedType("u32"), resolveClassArms,
				ECast(ELitInt(0), "u32")),
			reflectionFunctionItem("__hx_resolve_enum_name", "name", RBorrow(rustNamedType("str"), false, null), rustNamedType("u32"), resolveEnumArms,
				ECast(ELitInt(0), "u32")),
			reflectionFunctionItem("__hx_class_name", "type_id", rustNamedType("u32"), stringType, classNameArms, stringNullExpr()),
			reflectionFunctionItem("__hx_enum_name", "type_id", rustNamedType("u32"), stringType, enumNameArms, stringNullExpr()),
			reflectionFunctionItem("__hx_enum_constructs", "type_id", rustNamedType("u32"), stringArrayType, enumConstructArms,
				ECall(EPath("hxrt::array::Array::<" + rustTypeToString(stringType) + ">::new"), []))
		];
	}

	/**
		Emits the crate-root subtype helper used by `Std.isOfType` at dynamic boundaries.

		Why
		- Runtime `Dynamic` values only carry stable type ids for class/enum checks.
		- A direct `Any` downcast cannot express inheritance (`Dog` is-a `Animal`), so we need an
		  explicit id-based subtype relation table in generated crate code.

		What
		- Generates:
		  `pub(crate) fn __hx_is_subtype_type_id(actual: u32, expected: u32) -> bool`
		- The function fast-paths exact equality, then matches `actual` against emitted class ids and
		  accepts known superclass ids.

		How
		- Builds ancestry from each emitted class through `superClass` links.
		- Emits deterministic `match` arms (class-key sorted input) so snapshots stay stable.
	**/
	function emitSubtypeTypeIdRegistryFn():String {
		function collectInterfaceAncestors(iface:ClassType, seen:Map<String, Bool>, out:Array<ClassType>):Void {
			if (iface == null)
				return;
			var key = classKey(iface);
			if (seen.exists(key))
				return;
			seen.set(key, true);
			out.push(iface);
			for (parent in iface.interfaces) {
				var parentIface = parent.t.get();
				if (parentIface != null)
					collectInterfaceAncestors(parentIface, seen, out);
			}
		}

		var lines:Array<String> = [];
		lines.push("/// Runtime subtype check for stable Haxe class type ids.");
		lines.push("///");
		lines.push("/// Generated by reflaxe.rust from the emitted class inheritance graph.");
		lines.push("#[inline]");
		lines.push("pub(crate) fn __hx_is_subtype_type_id(actual: u32, expected: u32) -> bool {");
		lines.push("\tif actual == expected {");
		lines.push("\t\treturn true;");
		lines.push("\t}");

		var arms:Array<String> = [];
		for (cls in getEmittedClassesForTypeIdRegistry()) {
			var ancestors:Array<String> = [];
			var seenAncestors = new Map<String, Bool>();

			function addAncestorTypeId(id:String):Void {
				if (!seenAncestors.exists(id)) {
					seenAncestors.set(id, true);
					ancestors.push(id);
				}
			}

			var cur = cls.superClass != null ? cls.superClass.t.get() : null;
			while (cur != null) {
				addAncestorTypeId(typeIdLiteralForClass(cur));
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}

			var ifaceSeen:Map<String, Bool> = [];
			var ifaceAncestors:Array<ClassType> = [];
			var curForIfaces:Null<ClassType> = cls;
			while (curForIfaces != null) {
				for (iface in curForIfaces.interfaces) {
					var ifaceType = iface.t.get();
					if (ifaceType != null)
						collectInterfaceAncestors(ifaceType, ifaceSeen, ifaceAncestors);
				}
				curForIfaces = curForIfaces.superClass != null ? curForIfaces.superClass.t.get() : null;
			}
			for (ifaceType in ifaceAncestors)
				addAncestorTypeId(typeIdLiteralForClass(ifaceType));

			if (ancestors.length == 0)
				continue;
			ancestors.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

			var actualId = typeIdLiteralForClass(cls);
			arms.push("\t\t" + actualId + " => matches!(expected, " + ancestors.join(" | ") + "),");
		}

		if (arms.length == 0) {
			lines.push("\tfalse");
		} else {
			lines.push("\tmatch actual {");
			for (arm in arms)
				lines.push(arm);
			lines.push("\t\t_ => false,");
			lines.push("\t}");
		}
		lines.push("}");
		return lines.join("\n");
	}

	function getUserEnumsForModules():Array<EnumType> {
		var out:Array<EnumType> = [];
		var seen = new Map<String, Bool>();

		for (mt in Context.getAllModuleTypes()) {
			switch (mt) {
				case TEnumDecl(enumRef):
					{
						var en = enumRef.get();
						if (en == null)
							continue;
						if (!shouldEmitEnum(en))
							continue;

						var key = en.pack.join(".") + "." + en.name;
						if (seen.exists(key))
							continue;
						seen.set(key, true);
						out.push(en);
					}
				case _:
			}
		}

		out.sort((a, b) -> compareStrings(enumKey(a), enumKey(b)));
		return out;
	}

	override public function onOutputComplete() {
		emitMetalFallbackSummary();
		analyzeMetalViability();
		enforceMetalIslandContracts();

		if (!didEmitMain)
			return;
		if (output == null || output.outputDir == null)
			return;

		var outDir = output.outputDir;
		emitMetalViabilityReports(outDir);
		emitProfileContractReports(outDir);
		emitHxrtPlanReports(outDir);
		emitOptimizerPlanReports(outDir);
		var manifest = Path.join([outDir, "Cargo.toml"]);
		if (!FileSystem.exists(manifest))
			return;

		// Best-effort formatting/build. Avoid hard failing compilation if cargo/rustfmt are unavailable.
		if (Context.defined("rustfmt")) {
			var code = Sys.command("cargo", ["fmt", "--manifest-path", manifest]);
			if (code != 0) {
				#if eval
				Context.warning("`cargo fmt` failed (exit " + code + ") for output: " + manifest, Context.currentPos());
				#end
			}
		}

		var disableBuild = Context.defined("rust_no_build") || Context.defined("rust_codegen_only");
		var wantsBuild = !disableBuild;
		if (wantsBuild) {
			var cargoCmd = Context.definedValue("rust_cargo_cmd");
			if (cargoCmd == null || cargoCmd.length == 0)
				cargoCmd = "cargo";

			var subcommand = Context.definedValue("rust_cargo_subcommand");
			if (subcommand == null || subcommand.length == 0)
				subcommand = "build";

			var targetDir = Context.definedValue("rust_cargo_target_dir");
			if (targetDir != null && targetDir.length > 0) {
				Sys.putEnv("CARGO_TARGET_DIR", targetDir);
			}

			var args = [subcommand, "--manifest-path", manifest];

			if (Context.defined("rust_cargo_quiet"))
				args.push("-q");
			if (Context.defined("rust_cargo_locked"))
				args.push("--locked");
			if (Context.defined("rust_cargo_offline"))
				args.push("--offline");
			if (Context.defined("rust_cargo_no_default_features"))
				args.push("--no-default-features");
			if (Context.defined("rust_cargo_all_features"))
				args.push("--all-features");

			var features = Context.definedValue("rust_cargo_features");
			if (features != null && features.length > 0) {
				args.push("--features");
				args.push(features);
			}

			var jobs = Context.definedValue("rust_cargo_jobs");
			if (jobs != null && jobs.length > 0) {
				args.push("-j");
				args.push(jobs);
			}

			if (Context.defined("rust_build_release") || Context.defined("rust_release")) {
				args.push("--release");
			}
			var target = Context.definedValue("rust_target");
			if (target != null && target.length > 0) {
				args.push("--target");
				args.push(target);
			}
			var code = Sys.command(cargoCmd, args);
			if (code != 0) {
				#if eval
				RustDiagnostic.error(RustDiagnosticId.CargoInvocation,
					"`" + cargoCmd + " " + subcommand + "` failed (exit " + code + ") for output: " + manifest, Context.currentPos());
				#end
			}
		}
	}

	function findConstructor(funcFields:Array<ClassFuncData>):Null<ClassFuncData> {
		for (f in funcFields) {
			if (f.isStatic)
				continue;
			if (f.field.getHaxeName() != "new")
				continue;
			return f;
		}
		return null;
	}

	/**
		Why
		- Haxe property access syntax and Rust struct storage are not the same thing.
		- Some Haxe "readonly outside, stored inside" patterns use `get,null` together with
		  internal assignments (for example `sys.thread.FixedThreadPool.threadsCount`).
		- We need one authoritative rule for "does this `FVar` actually have a backing field?"
		  so constructor init, field reads, and field writes do not drift apart.

		What
		- Returns `true` only for vars that genuinely need stored Rust fields.
		- Supports both explicit storage (`@:isVar`, `default`, `ctor`) and implicit internal
		  storage patterns (`this.x = ...` in class methods, or `get_x()` returning `x`).

		How
		- First checks explicit accessor/storage metadata.
		- Then scans the declaring class's method bodies for internal writes to the property or
		  getter self-reads that imply an internal backing slot.
		- Results are cached per declaring class + property to keep lowering deterministic and cheap.
	**/
	function varFieldHasPhysicalStorage(classType:ClassType, cf:ClassField):Bool {
		var haxeName = cf.getHaxeName();
		if (haxeName == null || haxeName.length == 0)
			return false;
		var cacheKey = classKey(classType) + "::" + haxeName;
		if (physicalVarFieldCache.exists(cacheKey))
			return physicalVarFieldCache.get(cacheKey);

		function finish(value:Bool):Bool {
			physicalVarFieldCache.set(cacheKey, value);
			return value;
		}

		if (cf.meta != null && cf.meta.has(":isVar"))
			return finish(true);

		switch (cf.kind) {
			case FVar(read, write):
				switch ([read, write]) {
					case [AccNormal | AccCtor, _] | [_, AccNormal | AccCtor]:
						return finish(true);
					case _:
				}
			case _:
				return finish(false);
		}

		function isDirectSelfPropertyAccess(node:TypedExpr):Bool {
			var current = unwrapMetaParen(node);
			return switch (current.expr) {
				case TField(obj, fa):
					{
						if (!isThisExpr(obj) && !isSuperExpr(obj))
							false;
						else {
							switch (fa) {
								case FInstance(_, _, targetRef): {
										var target = targetRef.get();
										target == cf || target.getHaxeName() == haxeName
										;
									}
								case _:
									false;
							}
						}
					}
				case _:
					false;
			}
		}

		function methodImpliesBackingStorage(methodField:ClassField, body:TypedExpr):Bool {
			var methodName = methodField.getHaxeName();
			var getterName = "get_" + haxeName;
			var found = false;
			function scan(node:TypedExpr):Void {
				if (found)
					return;
				var current = unwrapMetaParen(node);
				switch (current.expr) {
					case TBinop(OpAssign | OpAssignOp(_), lhs, _):
						if (isDirectSelfPropertyAccess(lhs)) {
							found = true;
							return;
						}
					case TUnop(OpIncrement | OpDecrement, _, target):
						if (isDirectSelfPropertyAccess(target)) {
							found = true;
							return;
						}
					case _:
				}
				if (methodName == getterName && isDirectSelfPropertyAccess(current)) {
					found = true;
					return;
				}
				TypedExprTools.iter(current, scan);
			}
			scan(body);
			return found;
		}

		for (methodField in classType.fields.get()) {
			switch (methodField.kind) {
				case FMethod(_):
					{
						var ex = methodField.expr();
						if (ex == null)
							continue;
						var body = unwrapFieldFunctionBody(ex);
						if (methodImpliesBackingStorage(methodField, body))
							return finish(true);
					}
				case _:
			}
		}

		return finish(false);
	}

	function defaultValueExprForType(t:Type, pos:haxe.macro.Expr.Position):RustExpr {
		// `Null<T>` defaults to `null` in Haxe.
		//
		// IMPORTANT: detect this on the raw type before `TypeTools.follow` erases the abstract wrapper.
		switch (t) {
			case TAbstract(absRef, params):
				{
					var abs = absRef.get();
					if (abs != null && abs.module == "StdTypes" && abs.name == "Null" && params.length == 1) {
						// Collapse nested nullability (`Null<Null<T>>`).
						var innerType:Type = params[0];
						while (true) {
							var n = nullInnerType(innerType);
							if (n == null)
								break;
							innerType = n;
						}

						var inner = toRustType(innerType, pos);
						var carrierInner = rustTypeSingleGenericArgument(inner);

						var dynRefTraitObjectNull = dynRefNullExprForTraitObject(innerType, pos);
						if (dynRefTraitObjectNull != null) {
							return dynRefTraitObjectNull;
						}

						// Some Rust representations already have an explicit null value (no extra `Option<...>` needed).
						if (rustTypeIsDynamicCarrier(inner)) {
							return rustDynamicNullExpr();
						}
						if (rustTypeIsNullableStringCarrier(inner)) {
							return ECall(EPath("hxrt::string::HxString::null"), []);
						}
						// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
						if (isCoreClassOrEnumHandleType(innerType)) {
							return ECast(ELitInt(0), "u32");
						}
						if (rustTypeIsHxRef(inner) && carrierInner != null) {
							return ECall(EPath("crate::HxRef::<" + rustTypeToString(carrierInner) + ">::null"), []);
						}
						if (rustTypeIsArrayCarrier(inner) && carrierInner != null) {
							return ECall(EPath("hxrt::array::Array::<" + rustTypeToString(carrierInner) + ">::null"), []);
						}
						if (rustTypeIsDynRefCarrier(inner) && carrierInner != null) {
							return ECall(EPath(dynRefBasePath() + "::<" + rustTypeToString(carrierInner) + ">::null"), []);
						}

						// Fallback: `Null<T>` is represented as `Option<T>`.
						return EPath("None");
					}
				}
			case _:
		}

		// Function-typed fields are common in the stdlib (callbacks, handlers).
		//
		// Rust trait objects do not implement `Default`, so we must synthesize a valid value.
		// We use a no-op closure (or a closure returning a default value) and wrap it into our
		// function-value representation (`HxDynRef<dyn Fn...>`).
		switch (followType(t)) {
			case TFun(params, ret):
				{
					var argNames:Array<String> = [];
					for (i in 0...params.length)
						argNames.push("_a" + i);
					var closureBody:RustBlock = if (TypeHelper.isVoid(ret)) {
						{stmts: [], tail: null};
					} else {
						{stmts: [], tail: defaultValueExprForType(ret, pos)};
					}
					var closure = EClosure(argNames, closureBody, true);
					var rcExpr = ECall(EPath(rcBasePath() + "::new"), [closure]);
					return ECall(EPath(dynRefBasePath() + "::new"), [rcExpr]);
				}
			case _:
		}

		if (TypeHelper.isBool(t))
			return ELitBool(false);
		if (TypeHelper.isInt(t))
			return ELitInt(0);
		if (TypeHelper.isFloat(t))
			return ELitFloat(0.0);
		if (isStringType(t))
			return stringNullExpr();
		if (isDynamicType(t))
			return rustDynamicNullExpr();
		if (isRustVecType(t))
			return ECall(EPath("Vec::new"), []);
		if (isRustHashMapType(t))
			return ECall(EPath("std::collections::HashMap::new"), []);
		if (isArrayType(t)) {
			var elem = arrayElementType(t);
			var elemRust = toRustType(elem, pos);
			return ECall(EPath("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::new"), []);
		}
		if (traitObjectRustInnerPath(t, pos) != null) {
			// Bare interface / polymorphic class values lower to non-null `HxRc<dyn Trait>`.
			// When Haxe source supplies `null` in that slot, `Default::default()` is invalid
			// because Rust trait objects do not implement `Default`; emit a typed diverging
			// null access instead so the generated function remains well-typed.
			return ECall(EPath("hxrt::exception::throw"), [
				ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString("Null Access")])])
			]);
		}
		if (canUseNullClassReferenceDefault(t)) {
			return nullFillExprForType(t, pos);
		}

		// For many std types we prefer constructing a real instance over `Default::default()`,
		// because `crate::HxRef<T>` defaults require `T: Default` (not always true).
		switch (followType(t)) {
			case TInst(clsRef, params):
				{
					var cls = clsRef.get();
					if (cls != null && !cls.isInterface && !cls.isExtern && !classHasSubclasses(cls) && shouldEmitClass(cls, false)) {
						var ctor:Null<ClassField> = cls.constructor != null ? cls.constructor.get() : null;
						if (ctor != null) {
							var sig = followType(ctor.type);
							var ctorArgs:Array<RustExpr> = [];
							switch (sig) {
								case TFun(fnParams, _): {
										for (p in fnParams) {
											ctorArgs.push(defaultValueExprForType(p.t, pos));
										}
									}
								case _:
							}

							var modName = rustModulePathForClass(cls);
							var typeName = rustTypeNameForClass(cls);
							var typeParams = params != null
								&& params.length > 0 ? ("::<" + [for (p in params) rustTypeToString(toRustType(p, pos))].join(", ") + ">") : "";
							return ECall(EPath("crate::" + modName + "::" + typeName + typeParams + "::new"), ctorArgs);
						}
					}
				}
			case _:
		}

		return ECall(EPath("Default::default"), []);
	}

	function defaultValueForType(t:Type, pos:haxe.macro.Expr.Position):String {
		return reflaxe.rust.ast.RustASTPrinter.printExprForInjection(defaultValueExprForType(t, pos));
	}

	/**
		Returns whether a default-argument expression can be emitted at the caller.

		Why
		- Haxe optional parameters with defaults keep the default expression on the typed function
		  argument, not in the Rust signature.
		- Both normal calls and constructor calls need the same conservative rule for deciding when an
		  omitted argument can be lowered at the callsite.

		What
		- Allows constants and pure literal-shaped expressions made from constants.
		- Rejects locals, `this`, control flow, and other context-sensitive expressions so they do not
		  accidentally capture the wrong caller-side state.

		How
		- The accepted shapes mirror the existing compile-call contract: if the default is safe, compile
		  and coerce it for the parameter; otherwise let the parameter's null-fill representation stand.
	**/
	function defaultArgExprIsCallsiteSafe(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TConst(_): true;
			case TArrayDecl(values):
				values == null ? true : Lambda.fold(values, (x, acc) -> acc && defaultArgExprIsCallsiteSafe(x), true);
			case TObjectDecl(fields):
				fields == null ? true : Lambda.fold(fields, (f, acc) -> acc && defaultArgExprIsCallsiteSafe(f.expr), true);
			case TBinop(_, x, y): defaultArgExprIsCallsiteSafe(x) && defaultArgExprIsCallsiteSafe(y);
			case TUnop(_, _, x):
				defaultArgExprIsCallsiteSafe(x);
			case TCall(f2, a2): defaultArgExprIsCallsiteSafe(f2) && (a2 == null ? true : Lambda.fold(a2, (x, acc) -> acc && defaultArgExprIsCallsiteSafe(x),
					true));
			case TNew(_, _, a2):
				a2 == null ? true : Lambda.fold(a2, (x, acc) -> acc && defaultArgExprIsCallsiteSafe(x), true);
			case TCast(inner, _):
				defaultArgExprIsCallsiteSafe(inner);
			case TParenthesis(inner):
				defaultArgExprIsCallsiteSafe(inner);
			case TMeta(_, inner):
				defaultArgExprIsCallsiteSafe(inner);
			case TTypeExpr(_):
				true;
			case _:
				false;
		};
	}

	// "Null fill" value for extending Haxe arrays.
	//
	// Haxe grows arrays on out-of-bounds writes and fills intermediate slots with `null`.
	// For Rust output we need a concrete value of the element type to use as that fill.
	//
	// IMPORTANT: this is not the same as `defaultValueForType`:
	// - defaults are used for local/field initialization and may prefer `new(...)` for std types
	// - array growth must prefer the "null" representation for reference-like types
	function nullFillExprForType(t:Type, pos:haxe.macro.Expr.Position):RustExpr {
		// `Null<T>` fill value: `None` when represented as `Option<T>`, otherwise the inner type's null value.
		switch (t) {
			case TAbstract(absRef, params):
				{
					var abs = absRef.get();
					if (abs != null && abs.module == "StdTypes" && abs.name == "Null" && params.length == 1) {
						// Collapse nested nullability (`Null<Null<T>>`).
						var innerType:Type = params[0];
						while (true) {
							var n = nullInnerType(innerType);
							if (n == null)
								break;
							innerType = n;
						}

						var inner = toRustType(innerType, pos);
						var carrierInner = rustTypeSingleGenericArgument(inner);

						var dynRefTraitObjectNull = dynRefNullExprForTraitObject(innerType, pos);
						if (dynRefTraitObjectNull != null) {
							return dynRefTraitObjectNull;
						}

						// Some Rust representations already have an explicit null value (no extra `Option<...>` needed).
						if (rustTypeIsDynamicCarrier(inner)) {
							return rustDynamicNullExpr();
						}
						if (rustTypeIsNullableStringCarrier(inner)) {
							return ECall(EPath("hxrt::string::HxString::null"), []);
						}
						// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
						if (isCoreClassOrEnumHandleType(innerType)) {
							return ECast(ELitInt(0), "u32");
						}
						if (rustTypeIsHxRef(inner) && carrierInner != null) {
							return ECall(EPath("crate::HxRef::<" + rustTypeToString(carrierInner) + ">::null"), []);
						}
						if (rustTypeIsArrayCarrier(inner) && carrierInner != null) {
							return ECall(EPath("hxrt::array::Array::<" + rustTypeToString(carrierInner) + ">::null"), []);
						}
						if (rustTypeIsDynRefCarrier(inner) && carrierInner != null) {
							return ECall(EPath(dynRefBasePath() + "::<" + rustTypeToString(carrierInner) + ">::null"), []);
						}

						return EPath("None");
					}
				}
			case _:
		}

		if (TypeHelper.isBool(t))
			return ELitBool(false);
		if (TypeHelper.isInt(t))
			return ELitInt(0);
		if (TypeHelper.isFloat(t))
			return ELitFloat(0.0);
		if (isStringType(t))
			return stringNullExpr();
		if (isDynamicType(t))
			return rustDynamicNullExpr();

		if (isArrayType(t)) {
			var elem = arrayElementType(t);
			var elemRust = toRustType(elem, pos);
			return ECall(EPath("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::null"), []);
		}

		// Concrete class/Bytes/anon-object values are represented as `HxRef<_>` and can be null.
		if (isBytesType(t) || isHxRefValueType(t) || isRustHxRefType(t) || isAnonObjectType(t)) {
			return ECall(EPath("crate::HxRef::null"), []);
		}

		// For types that don't have a null representation today (enums, trait objects, etc.),
		// fall back to throwing when/if an out-of-bounds write requires a fill value.
		return ECall(EPath("hxrt::exception::throw"), [
			ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString("Null Access")])])
		]);
	}

	function compileConstructor(classType:ClassType, varFields:Array<ClassVarData>, f:ClassFuncData):reflaxe.rust.ast.RustAST.RustFunction {
		if (hasAsyncFunctionMeta(f.field.meta)) {
			ensureAsyncAllowed(f.field.pos);
			#if eval
			RustDiagnostic.error(RustDiagnosticId.AsyncConstructor,
				"Constructors cannot be marked `@:async` / `@:rustAsync` under the Rust async contract.", f.field.pos);
			#end
		}
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		var rustSelfType = rustTypeNameForClass(classType);
		var selfRefTy = rustHxRefClassInstType(classType);

		var stmts:Array<RustStmt> = [];
		if (f.expr != null) {
			// If this ctor calls `super(...)`, we inline base-ctor bodies into this Rust function.
			// Compute local mutation/read-count context over the combined (base+derived) bodies so
			// `mut` and clone decisions remain correct and name collisions are avoided.
			var ctxExpr:TypedExpr = f.expr;
			if (classType.superClass != null) {
				var chain:Array<TypedExpr> = [];
				var cur = classType.superClass != null ? classType.superClass.t.get() : null;
				while (cur != null) {
					if (cur.constructor != null) {
						var cf = cur.constructor.get();
						if (cf != null) {
							var ex = cf.expr();
							if (ex != null) {
								// ClassField.expr() returns a `TFunction` for methods; we want the body expression.
								var body = switch (ex.expr) {
									case TFunction(fn): fn.expr;
									case _: ex;
								};
								chain.push(body);
							}
						}
					}
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
				if (chain.length > 0) {
					ctxExpr = {expr: TBlock(chain.concat([f.expr])), pos: f.expr.pos, t: f.expr.t};
				}
			}

			withFunctionContext(ctxExpr, [for (a in f.args) a.getName()], f.ret, () -> {
				for (a in f.args) {
					args.push({
						name: rustArgIdent(a.getName()),
						ty: toRustType(a.type, f.field.pos)
					});
				}

				// Best-effort: if the constructor starts with `this.field = <arg>` assignments, move those
				// into the Rust struct literal so we don't require `Default` for generic fields.
				//
				// This keeps the rest of the constructor body intact (side effects, control flow), and is
				// conservative: we only lift the *leading* assignments.
				var liftedFieldInit:Map<String, RustExpr> = new Map();
				var remainingExprs:Null<Array<TypedExpr>> = null;

				var exprU = unwrapMetaParen(f.expr);
				switch (exprU.expr) {
					case TBlock(exprs): {
							var ctorArgNames:Map<String, Bool> = new Map();
							for (a in f.args) {
								var n = a.getName();
								if (n != null && n.length > 0)
									ctorArgNames.set(n, true);
							}

							function isCtorArgLocal(v:TVar):Bool {
								return v != null && v.name != null && ctorArgNames.exists(v.name);
							}

							function tryLift(e:TypedExpr):Null<{field:String, rhs:RustExpr}> {
								var u = unwrapMetaParen(e);
								return switch (u.expr) {
									case TBinop(OpAssign, lhs, rhs): {
											var l = unwrapMetaParen(lhs);
											switch (l.expr) {
												case TField(obj, fa): {
														switch (unwrapMetaParen(obj).expr) {
															case TConst(TThis): {
																	// Resolve the Haxe field name.
																	var haxeFieldName:Null<String> = null;
																	var haxeFieldType:Null<Type> = null;
																	switch (fa) {
																		case FInstance(_, _, cfRef): {
																				var cf = cfRef.get();
																				if (cf != null) {
																					haxeFieldName = cf.getHaxeName();
																					haxeFieldType = cf.type;
																				}
																			}
																		case FAnon(cfRef): {
																				var cf = cfRef.get();
																				if (cf != null) {
																					haxeFieldName = cf.getHaxeName();
																					haxeFieldType = cf.type;
																				}
																			}
																		case FDynamic(name): {
																				haxeFieldName = name;
																				haxeFieldType = null;
																			}
																		case _:
																	}
																	if (haxeFieldName == null)
																		return null;

																	var r = unwrapMetaParen(rhs);
																	var wantsOptionWrap = haxeFieldType != null
																		&& shouldOptionWrapStructFieldType(haxeFieldType);
																	function shouldCoerceLiftedFieldRhs(source:TypedExpr):Bool {
																		if (haxeFieldType == null)
																			return false;
																		if (isNullConstExpr(source))
																			return true;
																		if (nullOptionInnerType(haxeFieldType, source.pos) != null)
																			return true;
																		if (nullOptionInnerType(source.t, source.pos) != null)
																			return true;
																				var expectedRust = toRustType(haxeFieldType, source.pos);
																				var actualRust = toRustType(source.t, source.pos);
																				return !rustTypesEqual(expectedRust, actualRust);
																	}
																	function coerceLiftedFieldRhs(source:TypedExpr, compiled:RustExpr):RustExpr {
																		if (wantsOptionWrap) {
																			if (isNullConstExpr(source))
																				return EPath("None");
																			var inner = shouldCoerceLiftedFieldRhs(source) ? coerceExprToExpected(compiled,
																				source, haxeFieldType) : compiled;
																			return ECall(EPath("Some"), [inner]);
																		}
																		return shouldCoerceLiftedFieldRhs(source) ? coerceExprToExpected(compiled, source,
																			haxeFieldType) : compiled;
																	}
																	function rhsUsesOnlyCtorArgsAndConsts(e:TypedExpr, allowNonArgLocal:Bool = false):Bool {
																		var u = unwrapMetaParen(e);
																		return switch (u.expr) {
																			case TConst(c): switch (c) {
																					case TThis | TSuper:
																						false;
																					case _:
																						true;
																				}
																			case TLocal(v):
																				true;
																			case TNew(_, _, args):
																				args == null ? true : Lambda.fold(args,
																					(x, acc) -> acc && rhsUsesOnlyCtorArgsAndConsts(x, false), true);
																			case TArrayDecl(values):
																				values == null ? true : Lambda.fold(values,
																					(x, acc) -> acc
																						&& rhsUsesOnlyCtorArgsAndConsts(x, allowNonArgLocal), true);
																			case TObjectDecl(fields):
																				fields == null ? true : Lambda.fold(fields,
																					(f, acc) -> acc
																						&& rhsUsesOnlyCtorArgsAndConsts(f.expr, allowNonArgLocal),
																					true);
																			case TBinop(_, a, b): rhsUsesOnlyCtorArgsAndConsts(a,
																					allowNonArgLocal) && rhsUsesOnlyCtorArgsAndConsts(b, allowNonArgLocal);
																			case TUnop(_, _, a):
																				rhsUsesOnlyCtorArgsAndConsts(a, allowNonArgLocal);
																			case TCall(f2,
																				a2): // Allow the callee itself to be a non-arg local (e.g. builtins like `__rust__`),
																				// but keep argument expressions restricted to ctor args/constants.
																				rhsUsesOnlyCtorArgsAndConsts(f2, true)
																				&& (a2 == null ? true : Lambda.fold(a2,
																					(x, acc) -> acc && rhsUsesOnlyCtorArgsAndConsts(x, false), true));
																			case TArray(a, i): rhsUsesOnlyCtorArgsAndConsts(a,
																					allowNonArgLocal) && rhsUsesOnlyCtorArgsAndConsts(i, allowNonArgLocal);
																			case TField(o2, _):
																				rhsUsesOnlyCtorArgsAndConsts(o2, allowNonArgLocal);
																			case TCast(inner, _):
																				rhsUsesOnlyCtorArgsAndConsts(inner, allowNonArgLocal);
																			case TParenthesis(inner):
																				rhsUsesOnlyCtorArgsAndConsts(inner, allowNonArgLocal);
																			case TMeta(_, inner):
																				rhsUsesOnlyCtorArgsAndConsts(inner, allowNonArgLocal);
																			case TTypeExpr(_):
																				true;
																			case _:
																				false;
																		}
																	}
																	switch (r.expr) {
																		case TLocal(v) if (isCtorArgLocal(v)):
																			{
																				var baseExpr = compileExpr(r);

																				// Prefer moving constructor args into the struct init when safe:
																				// - Copy types never need `.clone()`
																				// - For non-Copy types, only clone when the arg is used again later in the constructor body
																				//   (based on local read counts collected for the function context).
																				var needsClone = !isCopyType(v.t);
																				if (needsClone && currentLocalReadCounts != null
																					&& currentLocalReadCounts.exists(v.id)) {
																					var reads = currentLocalReadCounts.get(v.id);
																					if (reads <= 1)
																						needsClone = false;
																				}

																				{
																					field: haxeFieldName,
																					rhs: {
																						var base = needsClone ? ECall(EField(baseExpr, "clone"), []) : baseExpr;
																						coerceLiftedFieldRhs(r, base);
																					},
																				}
																			}
																		case _ if (rhsUsesOnlyCtorArgsAndConsts(r)): {
																				// Compile with substitutions that clone non-Copy ctor args to avoid moving them.
																				var prevSubst = inlineLocalSubstitutions;
																				var subst:Map<String, RustExpr> = new Map();
																				for (a in f.args) {
																					var n = a.getName();
																					if (n == null || n.length == 0)
																						continue;
																					if (!isCopyType(a.type)) {
																						var rustName = rustArgIdent(n);
																						subst.set(n, ECall(EField(EPath(rustName), "clone"), []));
																					}
																				}
																				inlineLocalSubstitutions = subst;
																				var compiledRhs = compileExpr(r);
																				inlineLocalSubstitutions = prevSubst;

																				var rhsExpr = coerceLiftedFieldRhs(r, compiledRhs);
																				{field: haxeFieldName, rhs: rhsExpr};
																			}
																		case _:
																			null;
																	}
																}
															case _:
																null;
														}
													}
												case _:
													null;
											}
										}
									case _:
										null;
								}
							}

							var out:Array<TypedExpr> = [];
							var lifting = true;
							for (e in exprs) {
								var u = unwrapMetaParen(e);
								switch (u.expr) {
									case TConst(TNull):
										// Ignore.
										continue;
									case _:
								}

								if (lifting) {
									var lifted = tryLift(e);
									if (lifted != null) {
										liftedFieldInit.set(lifted.field, lifted.rhs);
										continue;
									}
									lifting = false;
								}

								out.push(e);
							}

							remainingExprs = out;
						}
					case _:
				}

				var fieldInits:Array<RustStructLitField> = [];
				var ctorAssignedFields:Map<String, Bool> = collectThisAssignedFields(f.expr);
				for (spec in getAllInstanceVarFieldSpecsForStruct(classType)) {
					var cf = spec.field;
					var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
					var haxeName = cf.getHaxeName();
					if (liftedFieldInit.exists(haxeName)) {
						fieldInits.push({
							name: rustFieldName(classType, cf),
							expr: liftedFieldInit.get(haxeName)
						});
					} else {
						var defExpr = if (shouldOptionWrapStructFieldType(fieldType)) {
							EPath("None");
						} else if (ctorAssignedFields.exists(haxeName) && canUseNullClassReferenceDefault(fieldType)) {
							nullFillExprForType(fieldType, cf.pos);
						} else {
							defaultValueExprForType(fieldType, cf.pos);
						}
						fieldInits.push({
							name: rustFieldName(classType, cf),
							expr: defExpr
						});
					}
				}
				for (spec in getAllInstanceDynamicMethodFieldSpecsForStorage(classType)) {
					var cf = spec.field;
					var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
					fieldInits.push({
						name: rustDynamicMethodFieldName(classType, cf),
						expr: defaultValueExprForType(fieldType, cf.pos)
					});
				}
				if (classNeedsPhantomForUnusedTypeParams(classType)) {
					fieldInits.push({
						name: "__hx_phantom",
						expr: EPath("std::marker::PhantomData")
					});
				}
				var structInitExpr = EStructLit(rustSelfType, fieldInits);
				stmts.push(RLet("self_", false, selfRefTy, ECall(EPath("crate::HxRef::new"), [structInitExpr])));
				for (spec in getAllInstanceDynamicMethodFieldSpecsForStorage(classType)) {
					var cf = spec.field;
					var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
					var recvExpr = EPath("self_");
					var recvName = "__hx_dyn_recv_" + rustMethodName(classType, cf);
					var fieldName = rustDynamicMethodFieldName(classType, cf);
					var defaultName = rustDynamicMethodDefaultName(classType, cf);
					var fnInfo = switch (followType(fieldType)) {
						case TFun(params, ret): {params: params, ret: ret};
						case _: null;
					};
					if (fnInfo == null)
						continue;

					var argParts:Array<String> = [];
					var callArgs:Array<RustExpr> = [];
					for (i in 0...fnInfo.params.length) {
						var p = fnInfo.params[i];
						var argName = "a" + i;
						argParts.push(argName + ": " + rustTypeToString(toRustType(p.t, cf.pos)));
						callArgs.push(EPath(argName));
					}

					var defaultPath = classNameFromClass(classType) + "::" + defaultName;
					var defaultCallArgs:Array<RustExpr> = [EUnary("&", EUnary("*", EPath(recvName)))];
					for (a in callArgs)
						defaultCallArgs.push(a);

					var closureBody:RustBlock = if (TypeHelper.isVoid(fnInfo.ret)) {
						{stmts: [RSemi(ECall(EPath(defaultPath), defaultCallArgs))], tail: null};
					} else {
						{stmts: [], tail: ECall(EPath(defaultPath), defaultCallArgs)};
					};

					var fnTraitType = rustFunctionTraitObjectType([for (p in fnInfo.params) toRustType(p.t, cf.pos)],
						TypeHelper.isVoid(fnInfo.ret) ? null : toRustType(fnInfo.ret, cf.pos));

					stmts.push(RSemi(EBlock({
						stmts: [
							RLet(recvName, false, null, ECall(EField(recvExpr, "clone"), [])),
							RLet("__hx_dyn_rc", false, rustRcType(fnTraitType),
								ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, closureBody, true)])),
							RSemi(EAssign(EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName),
								ECall(EPath(dynRefBasePath() + "::new"), [EPath("__hx_dyn_rc")])))
						],
						tail: null
					})));
				}

				function unwrapLeadingSuperCall(e:TypedExpr):Null<Array<TypedExpr>> {
					var cur = unwrapMetaParen(e);
					return switch (cur.expr) {
						case TCall(target, a): {
								var t = unwrapMetaParen(target);
								switch (t.expr) {
									case TConst(TSuper): a;
									case _: null;
								}
							}
						case _: null;
					}
				}

				function allocTemp(base:String):String {
					if (currentLocalUsed == null)
						return base;
					return RustNaming.stableUnique(base, currentLocalUsed);
				}

				function ctorFieldFor(cls:ClassType):Null<ClassField> {
					return cls != null && cls.constructor != null ? cls.constructor.get() : null;
				}

				function ctorParamsFor(cls:ClassType):Array<{name:String, t:Type, opt:Bool}> {
					var cf = ctorFieldFor(cls);
					if (cf == null)
						return [];
					var ctorType = specializeAncestorType(classType, cls, cf.type);
					return switch (followType(ctorType)) {
						case TFun(params, _): params;
						case _: [];
					};
				}

				function ctorBodyFor(cls:ClassType):Null<TypedExpr> {
					var cf = ctorFieldFor(cls);
					var ex = cf != null ? cf.expr() : null;
					if (ex == null)
						return null;
					// ClassField.expr() returns a `TFunction` for methods; we want the body expression.
					return switch (ex.expr) {
						case TFunction(fn): fn.expr;
						case _: ex;
					};
				}

				function compilePositionalArgsFor(owner:ClassType, params:Array<{name:String, t:Type, opt:Bool}>,
						args:Array<TypedExpr>):Array<{param:{name:String, t:Type, opt:Bool}, rust:RustExpr, typed:Null<TypedExpr>}> {
					var out:Array<{param:{name:String, t:Type, opt:Bool}, rust:RustExpr, typed:Null<TypedExpr>}> = [];
					for (i in 0...params.length) {
						var p = params[i];
						if (i < args.length) {
							var a = args[i];
							var compiled = compileExpr(a);
							compiled = coerceArgForParam(compiled, a, p.t);
							// A generic base constructor parameter is specialized before this call. If the
							// actual argument is an already-typed local HxString, the general string bridge
							// can conservatively wrap it again because the source AST still names `T`.
							// Remove only that direct identity wrapper at this generic constructor edge;
							// literals/native String expressions retain the ordinary bridge.
							if (owner.params != null && owner.params.length > 0 && isLocalExpr(a)) {
								var expectedRust = toRustType(p.t, a.pos);
								var actualRust = toRustType(a.t, a.pos);
								if (rustTypeIsNullableStringCarrier(expectedRust) && rustTypesEqual(actualRust, expectedRust)) {
									compiled = switch (compiled) {
										case ECall(EPath("hxrt::string::HxString::from"), [inner]): inner;
										case _: compiled;
									}
								}
							}
							out.push({param: p, rust: compiled, typed: a});
						} else if (p.opt) {
							out.push({param: p, rust: nullFillExprForType(p.t, f.field.pos), typed: null});
						} else {
							// Typechecker should prevent this; keep a deterministic fallback.
							out.push({
								param: p,
								rust: ERaw(RustRawCode.compilerAt(defaultValueForType(p.t, f.field.pos), RawDefaultValueFallback, f.field.pos)),
								typed: null
							});
						}
					}
					return out;
				}

				function emitCtorChainInit(cls:ClassType, callArgs:Array<TypedExpr>, depth:Int):Void {
					if (cls == null)
						return;
					var ctorExpr = ctorBodyFor(cls);
					if (ctorExpr == null)
						return;
					var previousMethodOwner = currentMethodOwnerType;
					currentMethodOwnerType = cls;

					var params = ctorParamsFor(cls);
					var compiledArgs = compilePositionalArgsFor(cls, params, callArgs);

					// Evaluate super-call args once, in order, into temps.
					var subst:Map<String, RustExpr> = new Map();
					for (i in 0...compiledArgs.length) {
						var p = compiledArgs[i].param;
						var rust = compiledArgs[i].rust;
						var typed = compiledArgs[i].typed;
						if (typed != null) {
							rust = maybeCloneForReuseValue(rust, typed);
						}

						var tmp = allocTemp("__hx_super_" + depth + "_" + i);
						stmts.push(RLet(tmp, false, toRustType(p.t, f.field.pos), rust));

						var byValue = EPath(tmp);
						var useExpr = isCopyType(p.t) ? byValue : ECall(EField(byValue, "clone"), []);
						subst.set(p.name, useExpr);
					}

					function withSubst<T>(m:Map<String, RustExpr>, fn:() -> T):T {
						var prev = inlineLocalSubstitutions;
						inlineLocalSubstitutions = m;
						var out = fn();
						inlineLocalSubstitutions = prev;
						return out;
					}

					withSubst(subst, () -> {
						// If this ctor starts with a `super(...)` call, inline the super-ctor first.
						var exprU = unwrapMetaParen(ctorExpr);
						var remaining:Array<TypedExpr> = null;
						var superArgs:Null<Array<TypedExpr>> = null;
						switch (exprU.expr) {
							case TBlock(exprs) if (exprs.length > 0): {
									superArgs = unwrapLeadingSuperCall(exprs[0]);
									remaining = superArgs != null ? exprs.slice(1) : exprs;
								}
							case _:
						}

						if (superArgs != null) {
							var base = cls.superClass != null ? cls.superClass.t.get() : null;
							if (base == null) {
								#if eval
								Context.error("super() call found, but class has no superclass", ctorExpr.pos);
								#end
							} else {
								emitCtorChainInit(base, superArgs, depth + 1);
							}
						}

						if (remaining != null) {
							var bodyExpr:TypedExpr = {expr: TBlock(remaining), pos: ctorExpr.pos, t: ctorExpr.t};
							var block = compileVoidBody(bodyExpr);
							for (s in block.stmts)
								stmts.push(s);
							if (block.tail != null)
								stmts.push(RSemi(block.tail));
						} else {
							var block = compileVoidBody(ctorExpr);
							for (s in block.stmts)
								stmts.push(s);
							if (block.tail != null)
								stmts.push(RSemi(block.tail));
						}
						return null;
					});
					currentMethodOwnerType = previousMethodOwner;
				}

				// Remove a leading `super(...)` call from the derived ctor body and inline the base ctor chain.
				var bodyExpr:TypedExpr = f.expr;
				var exprsForBody:Null<Array<TypedExpr>> = remainingExprs;
				if (exprsForBody == null) {
					switch (unwrapMetaParen(f.expr).expr) {
						case TBlock(exprs): exprsForBody = exprs;
						case _:
					}
				}

				if (exprsForBody != null && exprsForBody.length > 0) {
					var superArgs = unwrapLeadingSuperCall(exprsForBody[0]);
					if (superArgs != null) {
						var base = classType.superClass != null ? classType.superClass.t.get() : null;
						if (base == null) {
							#if eval
							Context.error("super() call found, but class has no superclass", exprsForBody[0].pos);
							#end
						} else {
							emitCtorChainInit(base, superArgs, 0);
						}
						exprsForBody = exprsForBody.slice(1);
					}
				}

				if (exprsForBody != null) {
					bodyExpr = {expr: TBlock(exprsForBody), pos: f.expr.pos, t: f.expr.t};
				}

				var bodyBlock = compileFunctionBody(bodyExpr, f.ret, true);
				for (s in bodyBlock.stmts)
					stmts.push(s);
				if (bodyBlock.tail != null)
					stmts.push(RSemi(bodyBlock.tail));

				stmts.push(RReturn(EPath("self_")));
			});
		}

		return {
			name: "new",
			isPub: true,
			generics: RustGenericParameters.empty(),
			args: args,
			ret: selfRefTy,
			body: {stmts: stmts, tail: null}
		};
	}

	function compileInstanceMethod(classType:ClassType, f:ClassFuncData, methodOwner:ClassType):reflaxe.rust.ast.RustAST.RustFunction {
		var isAsyncMethod = hasAsyncFunctionMeta(f.field.meta);
		var asyncInnerRet:Null<Type> = null;
		if (isAsyncMethod) {
			ensureAsyncAllowed(f.field.pos);
			asyncInnerRet = rustFutureInnerType(f.ret);
			if (asyncInnerRet == null) {
				#if eval
				RustDiagnostic.error(RustDiagnosticId.AsyncReturnFuture,
					"`@:async`/`@:rustAsync` instance methods must return `rust.async.Future<T>` (got `" + TypeTools.toString(f.ret) + "`).",
					f.field.pos);
				#end
			}
		}
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		var generics = rustGenericParamsForFunction(f);
		var selfName = exprUsesThis(f.expr) ? "self_" : "_self_";
		args.push({
			name: selfName,
			ty: rustBorrowedRefCellClassInstType(classType)
		});
		var body = {stmts: [], tail: null};
		var prevOwner = currentMethodOwnerType;
		currentMethodOwnerType = methodOwner;
		var prevField = currentMethodField;
		currentMethodField = f.field;
		withFunctionContext(f.expr, [for (a in f.args) a.getName()], isAsyncMethod ? asyncInnerRet : f.ret, () -> {
			var prevThisIdent = currentThisIdent;
			if (selfName == "self_")
				currentThisIdent = "__hx_this";
			for (a in f.args) {
				args.push({
					name: rustArgIdent(a.getName()),
					ty: toRustType(a.type, f.field.pos)
				});
			}
			if (isAsyncMethod) {
				var innerBody = compileFunctionBody(f.expr, asyncInnerRet, true);
				var prefix:Array<RustStmt> = [];
				if (selfName == "self_") {
					var thisTy = rustHxRefClassInstType(classType);
					prefix.push(RLet("__hx_this", false, thisTy, ECall(EField(EPath(selfName), "self_ref"), [])));
				}
				body = {
					stmts: prefix.concat([RReturn(EPinAsyncMove(innerBody))]),
					tail: null
				};
			} else {
				body = compileFunctionBody(f.expr, f.ret, true);
				if (selfName == "self_") {
					var thisTy = rustHxRefClassInstType(classType);
					body.stmts.unshift(RLet("__hx_this", false, thisTy, ECall(EField(EPath(selfName), "self_ref"), [])));
				}
			}
			currentThisIdent = prevThisIdent;
		}, isAsyncMethod);
		currentMethodOwnerType = prevOwner;
		currentMethodField = prevField;

		function needsCrateVisibility(cls:ClassType, cf:ClassField):Bool {
			// If a class/field uses `@:allow(...)` or `@:access(...)`, Haxe may permit cross-type
			// access to private members. Rust module privacy is stricter than Haxe's, so we widen
			// such members to `pub(crate)` to keep the generated crate compiling.
			return (cls.meta != null && (cls.meta.has(":allow") || cls.meta.has(":access")))
				|| (cf.meta != null && (cf.meta.has(":allow") || cf.meta.has(":access")));
		}

		var isPub = f.field.isPublic || isAccessorForPublicPropertyInstance(classType, f.field);
		return {
			name: rustMethodName(classType, f.field),
			// Haxe allows `public var x(get, never)` while keeping `get_x()` itself private.
			// Rust module privacy is stricter, so make accessors public when the property is public.
			isPub: isPub,
			vis: (!isPub && needsCrateVisibility(classType, f.field)) ? RustVisibility.VPubCrate : null,
			generics: generics,
			args: args,
			ret: rustReturnTypeForField(f.field, f.ret, f.field.pos),
			body: body
		};
	}

	function compileDynamicInstanceMethodDefault(classType:ClassType, f:ClassFuncData, methodOwner:ClassType):reflaxe.rust.ast.RustAST.RustFunction {
		var fn = compileInstanceMethod(classType, f, methodOwner);
		fn.name = rustDynamicMethodDefaultName(classType, f.field);
		fn.isPub = false;
		fn.vis = null;
		var prefix:Array<RustStmt> = [];
		for (arg in fn.args) {
			if (arg.name == null || arg.name.length == 0)
				continue;
			if (arg.name == "self_" || arg.name == "_self_")
				continue;
			prefix.push(RLet("_", false, null, EUnary("&", EPath(arg.name))));
		}
		if (prefix.length > 0) {
			fn.body = {
				stmts: prefix.concat(fn.body.stmts),
				tail: fn.body.tail
			};
		}
		return fn;
	}

	function compileDynamicInstanceMethodWrapper(classType:ClassType, f:ClassFuncData):reflaxe.rust.ast.RustAST.RustFunction {
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		var selfTy = rustBorrowedRefCellClassInstType(classType);
		args.push({name: "self_", ty: selfTy});

		var callArgs:Array<RustExpr> = [];
		for (a in f.args) {
			var argName = rustArgIdent(a.getName());
			args.push({name: argName, ty: toRustType(a.type, f.field.pos)});
			callArgs.push(EPath(argName));
		}

		var fieldName = rustDynamicMethodFieldName(classType, f.field);
		var invoke = ECall(EPath("__hx_dyn"), callArgs);
		var dynValue = ECall(EField(EField(ECall(EField(EPath("self_"), "borrow"), []), fieldName), "clone"), []);
		var body:RustBlock = {
			stmts: [RLet("__hx_dyn", false, null, dynValue)],
			tail: null
		};
		if (TypeHelper.isVoid(f.ret)) {
			body.stmts.push(RSemi(invoke));
		} else {
			body.tail = invoke;
		}

		function needsCrateVisibility(cls:ClassType, cf:ClassField):Bool {
			return (cls.meta != null && (cls.meta.has(":allow") || cls.meta.has(":access")))
				|| (cf.meta != null && (cf.meta.has(":allow") || cf.meta.has(":access")));
		}

		var isPub = f.field.isPublic || isAccessorForPublicPropertyInstance(classType, f.field);
		return {
			name: rustMethodName(classType, f.field),
			isPub: isPub,
			vis: (!isPub && needsCrateVisibility(classType, f.field)) ? RustVisibility.VPubCrate : null,
			generics: rustGenericParamsForFunction(f),
			args: args,
			ret: rustReturnTypeForField(f.field, f.ret, f.field.pos),
			body: body
		};
	}

	function compileStaticMethod(classType:ClassType, f:ClassFuncData):reflaxe.rust.ast.RustAST.RustFunction {
		var compiled = compileStaticFunctionShape(f);

		function needsCrateVisibility(cls:ClassType, cf:ClassField):Bool {
			return (cls.meta != null && (cls.meta.has(":allow") || cls.meta.has(":access")))
				|| (cf.meta != null && (cf.meta.has(":allow") || cf.meta.has(":access")));
		}

		var isPub = f.field.isPublic || isAccessorForPublicPropertyStatic(classType, f.field);
		return {
			name: rustMethodName(classType, f.field),
			isPub: isPub,
			vis: (!isPub && needsCrateVisibility(classType, f.field)) ? RustVisibility.VPubCrate : null,
			generics: compiled.generics,
			args: compiled.args,
			ret: compiled.ret,
			body: compiled.body
		};
	}

	/**
		Builds the Rust signature/body for a Haxe static method exactly once.

		Why
		- The compiler emits static methods in two places: associated functions on normal classes
		  and top-level helper functions for the main class.
		- Duplicating that lowering caused the main-class path to drift and drop generic parameters,
		  producing invalid Rust like `fn option_map(value: Option<T>)` without `fn option_map<T>(...)`.

		What
		- Centralizes argument lowering, generic parameter emission, async handling, and return type selection
		  for static methods so all call sites share the same contract.

		How
		- Reads the generic declaration from the typed `ClassField`.
		- Reuses the same `withFunctionContext(...)` flow for async and sync bodies.
		- Returns a typed shape that callers can wrap either as an impl method or a top-level helper.
	**/
	function compileStaticFunctionShape(f:ClassFuncData):{
		generics:RustGenericParameters,
		args:Array<reflaxe.rust.ast.RustAST.RustFnArg>,
		ret:reflaxe.rust.ast.RustAST.RustType,
		body:reflaxe.rust.ast.RustAST.RustBlock
	} {
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		var generics = rustGenericParamsForFunction(f);
		var body = {stmts: [], tail: null};
		var isAsyncMethod = hasAsyncFunctionMeta(f.field.meta);
		var asyncInnerRet:Null<Type> = null;
		if (isAsyncMethod) {
			ensureAsyncAllowed(f.field.pos);
			asyncInnerRet = rustFutureInnerType(f.ret);
			if (asyncInnerRet == null) {
				#if eval
				RustDiagnostic.error(RustDiagnosticId.AsyncReturnFuture,
					"`@:async`/`@:rustAsync` static methods must return `rust.async.Future<T>` (got `" + TypeTools.toString(f.ret) + "`).",
					f.field.pos);
				#end
			}
		}
		var prevField = currentMethodField;
		currentMethodField = f.field;
		withFunctionContext(f.expr, [for (a in f.args) a.getName()], isAsyncMethod ? asyncInnerRet : f.ret, () -> {
			for (a in f.args) {
				args.push({
					name: rustArgIdent(a.getName()),
					ty: toRustType(a.type, f.field.pos)
				});
			}
			if (isAsyncMethod) {
				var innerBody = compileFunctionBody(f.expr, asyncInnerRet, true);
				body = {
					stmts: [RReturn(EPinAsyncMove(innerBody))],
					tail: null
				};
			} else {
				body = compileFunctionBody(f.expr, f.ret, true);
			}
		}, isAsyncMethod);
		currentMethodField = prevField;

		return {
			generics: generics,
			args: args,
			ret: rustReturnTypeForField(f.field, f.ret, f.field.pos),
			body: body
		};
	}

	function compileSuperThunk(classType:ClassType, owner:ClassType, cf:ClassField):reflaxe.rust.ast.RustAST.RustFunction {
		var ex = cf.expr();
		if (ex == null) {
			// Should only happen if `noteSuperThunk` registered a method with no body.
			return {
				name: superThunkName(owner, cf),
				isPub: false,
				generics: RustGenericParameters.empty(),
				args: [
					{name: "_self_", ty: rustBorrowedRefCellClassInstType(classType)}
				],
				ret: RUnit,
				body: {stmts: [RSemi(ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, cf.pos)))], tail: null}
			};
		}

		var bodyExpr = unwrapFieldFunctionBody(ex);
		var sig = switch (followType(specializeAncestorType(classType, owner, cf.type))) {
			case TFun(params, ret): {params: params, ret: ret};
			case _: null;
		};
		if (sig == null) {
			return {
				name: superThunkName(owner, cf),
				isPub: false,
				generics: RustGenericParameters.empty(),
				args: [
					{name: "_self_", ty: rustBorrowedRefCellClassInstType(classType)}
				],
				ret: RUnit,
				body: {stmts: [RSemi(ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, cf.pos)))], tail: null}
			};
		}

		var selfName = exprUsesThis(bodyExpr) ? "self_" : "_self_";
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		args.push({
			name: selfName,
			ty: rustBorrowedRefCellClassInstType(classType)
		});

		var argNames:Array<String> = [];
		for (i in 0...sig.params.length) {
			var p = sig.params[i];
			var baseName = p.name != null && p.name.length > 0 ? p.name : ("a" + i);
			argNames.push(baseName);
			args.push({
				name: rustArgIdent(baseName),
				ty: toRustType(p.t, cf.pos)
			});
		}

		var generics = rustGenericParamsForFieldSignature(cf, [for (p in sig.params) p.t], sig.ret);
		var body = {stmts: [], tail: null};
		var prevOwner = currentMethodOwnerType;
		currentMethodOwnerType = owner;
		var prevField = currentMethodField;
		currentMethodField = cf;
		withFunctionContext(bodyExpr, argNames, sig.ret, () -> {
			var prevThisIdent = currentThisIdent;
			if (selfName == "self_")
				currentThisIdent = "__hx_this";
			body = compileFunctionBody(bodyExpr, sig.ret, true);
			if (selfName == "self_") {
				var thisTy = rustHxRefClassInstType(classType);
				body.stmts.unshift(RLet("__hx_this", false, thisTy, ECall(EField(EPath(selfName), "self_ref"), [])));
			}
			currentThisIdent = prevThisIdent;
		});
		currentMethodOwnerType = prevOwner;
		currentMethodField = prevField;

		return {
			name: superThunkName(owner, cf),
			isPub: false,
			generics: generics,
			args: args,
			ret: rustReturnTypeForField(cf, sig.ret, cf.pos),
			body: body
		};
	}

	function rustGenericParamsForFunction(f:ClassFuncData):RustGenericParameters {
		return rustGenericParamsForFieldSignature(f.field, [for (a in f.args) a.type], f.ret);
	}

	/**
		Infers Rust method generic declarations from the typed Haxe signature.

		Why
		- Generated Haxe classes default their Rust type parameters to `Clone + Send + Sync`
		  because `HxRef<T>` storage, field reads, and thread-safe runtime handles rely on those
		  traits.
		- Static/helper methods have their own generic declarations. If `make<T>(): Payload<T>`
		  emits `fn make<T>() -> HxRef<Payload<T>>`, Rust rejects the signature because
		  `Payload<T>` itself was generated as `Payload<T: Clone + Send + Sync>`.
		- This is a compile-time codegen contract, not an `hxrt` responsibility; adding a runtime
		  wrapper would hide the missing Rust bounds instead of fixing the generated signature.

		What
		- Keeps explicit `@:rustGeneric` method metadata authoritative.
		- For implicit method generics, walks argument and return types and copies bounds from any
		  generated class payload that uses the method generic as one of its type arguments.
		- Leaves unconstrained helpers such as `Option<T> -> Option<U>` as bare `T, U`.

		How
		- The class declaration policy remains centralized in `rustGenericDeclsForClass(...)`.
		- When a signature mentions an emitted generated class such as `Payload<T>`, this helper
		  maps the class parameter declaration (`T: Clone + Send + Sync`) onto the method's actual
		  type parameter (`T`) and merges duplicate trait fragments deterministically.
	**/
	function rustGenericParamsForFieldSignature(field:ClassField, argTypes:Array<Type>, ret:Type):RustGenericParameters {
		var fallback = [for (p in field.params) p.name];
		var explicit = rustGenericParamsFromFieldMetaExplicit(field.meta);
		if (explicit != null)
			return explicit;
		if (fallback.length == 0)
			return RustGenericParameters.empty();

		var paramSet:Map<String, Bool> = [];
		for (name in fallback)
			paramSet.set(name, true);

		var bounds:Map<String, Array<RustGenericBound>> = [];
		for (t in argTypes)
			inferFunctionGenericBoundsFromType(t, paramSet, bounds);
		inferFunctionGenericBoundsFromType(ret, paramSet, bounds);

		return RustGenericParameters.of([
			for (name in fallback)
				GenericTypeParam(RustIdentifier.named(name), bounds.exists(name) ? bounds.get(name) : [], null)
		]);
	}

	function inferFunctionGenericBoundsFromType(t:Type, methodParams:Map<String, Bool>, bounds:Map<String, Array<RustGenericBound>>):Void {
		var ft = followType(t);
		switch (ft) {
			case TInst(clsRef, params):
				{
					var cls = clsRef.get();
					if (cls != null) {
						switch (cls.kind) {
							case KTypeParameter(_):
							case _:
								if (shouldEmitClass(cls, isMainClass(cls))) {
									var classDecls = rustGenericDeclsForClass(cls);
									var max = params.length < classDecls.count ? params.length : classDecls.count;
									for (i in 0...max) {
										var classBounds:Array<RustGenericBound> = switch (classDecls.at(i)) {
											case GenericTypeParam(_, declaredBounds, _): declaredBounds;
											case _: [];
										};
										if (classBounds.length == 0)
											continue;
										var usedMethodParams:Map<String, Bool> = [];
										collectMethodTypeParamsInType(params[i], methodParams, usedMethodParams);
										for (name in usedMethodParams.keys()) {
											for (classBound in classBounds)
												addRustGenericBound(bounds, name, classBound);
										}
									}
								}
						}
					}
					for (p in params)
						inferFunctionGenericBoundsFromType(p, methodParams, bounds);
				}
			case TEnum(_, params) | TAbstract(_, params):
				{
					for (p in params)
						inferFunctionGenericBoundsFromType(p, methodParams, bounds);
				}
			case TFun(params, ret):
				{
					for (p in params)
						inferFunctionGenericBoundsFromType(p.t, methodParams, bounds);
					inferFunctionGenericBoundsFromType(ret, methodParams, bounds);
				}
			case TAnonymous(anonRef):
				{
					var anon = anonRef.get();
					if (anon != null && anon.fields != null) {
						for (cf in anon.fields)
							inferFunctionGenericBoundsFromType(cf.type, methodParams, bounds);
					}
				}
			case _:
		}
	}

	function collectMethodTypeParamsInType(t:Type, methodParams:Map<String, Bool>, out:Map<String, Bool>):Void {
		var ft = followType(t);
		switch (ft) {
			case TInst(clsRef, params):
				{
					var cls = clsRef.get();
					if (cls != null) {
						switch (cls.kind) {
							case KTypeParameter(_):
								if (methodParams.exists(cls.name)) out.set(cls.name, true);
							case _:
						}
					}
					for (p in params)
						collectMethodTypeParamsInType(p, methodParams, out);
				}
			case TEnum(_, params) | TAbstract(_, params):
				{
					for (p in params)
						collectMethodTypeParamsInType(p, methodParams, out);
				}
			case TFun(params, ret):
				{
					for (p in params)
						collectMethodTypeParamsInType(p.t, methodParams, out);
					collectMethodTypeParamsInType(ret, methodParams, out);
				}
			case TAnonymous(anonRef):
				{
					var anon = anonRef.get();
					if (anon != null && anon.fields != null) {
						for (cf in anon.fields)
							collectMethodTypeParamsInType(cf.type, methodParams, out);
					}
				}
			case _:
		}
	}

	function addRustGenericBound(bounds:Map<String, Array<RustGenericBound>>, name:String, bound:RustGenericBound):Void {
		var existing = bounds.exists(name) ? bounds.get(name) : [];
		for (current in existing)
			if (rustGenericBoundsEqual(current, bound)) return;
		existing.push(bound);
		bounds.set(name, existing);
	}

	function rustGenericParamsFromFieldMetaExplicit(meta:haxe.macro.Type.MetaAccess):Null<RustGenericParameters> {
		var out:Array<String> = [];
		var found = false;
		var metadataPos:Null<haxe.macro.Expr.Position> = null;

		for (entry in meta.get()) {
			if (entry.name != ":rustGeneric")
				continue;
			found = true;
			if (metadataPos == null)
				metadataPos = entry.pos;

			if (entry.params == null || entry.params.length == 0) {
				#if eval
				RustDiagnostic.error(RustDiagnosticId.MetadataArity, "`@:rustGeneric` requires a single parameter.", entry.pos);
				#end
				continue;
			}

			switch (entry.params[0].expr) {
				case EConst(CString(s, _)):
					out.push(s);
				case EArrayDecl(values):
					{
						for (v in values) {
							switch (v.expr) {
								case EConst(CString(s, _)):
									out.push(s);
								case _:
									#if eval
									RustDiagnostic.error(RustDiagnosticId.MetadataValue,
										"`@:rustGeneric` array must contain only strings.", entry.pos);
									#end
							}
						}
					}
				case _:
					#if eval
					RustDiagnostic.error(RustDiagnosticId.MetadataValue,
						"`@:rustGeneric` must be a string or array of strings.", entry.pos);
					#end
			}
		}

		if (!found)
			return null;
		try {
			return RustMetadataSyntax.parseGenericParameterFragments(out);
		} catch (message:String) {
			#if eval
			RustDiagnostic.error(RustDiagnosticId.MetadataValue, "Invalid `@:rustGeneric` syntax: " + message, metadataPos);
			#end
			return RustGenericParameters.empty();
		}
	}

	function rustGenericParamsFromFieldMeta(meta:haxe.macro.Type.MetaAccess, fallback:RustGenericParameters):RustGenericParameters {
		var explicit = rustGenericParamsFromFieldMetaExplicit(meta);
		return explicit != null ? explicit : fallback;
	}

	function rustReturnTypeFromMeta(meta:haxe.macro.Type.MetaAccess):Null<reflaxe.rust.ast.RustAST.RustType> {
		for (entry in meta.get()) {
			if (entry.name != ":rustReturn")
				continue;
			if (entry.params == null || entry.params.length != 1) {
				#if eval
				Context.error("`@:rustReturn` requires a single string parameter.", entry.pos);
				#end
				return null;
			}
			return switch (entry.params[0].expr) {
				case EConst(CString(s, _)):
					try {
						RustMetadataSyntax.parseType(s);
					} catch (message:String) {
						#if eval
						RustDiagnostic.error(RustDiagnosticId.MetadataValue, "Invalid `@:rustReturn` type syntax: " + message, entry.pos);
						#end
						RUnit;
					}
				case _:
					#if eval
					Context.error("`@:rustReturn` must be a compile-time string.", entry.pos);
					#end
					null;
			}
		}
		return null;
	}

	function rustReturnTypeForField(field:ClassField, haxeRet:Type, pos:haxe.macro.Expr.Position):reflaxe.rust.ast.RustAST.RustType {
		var overrideTy = rustReturnTypeFromMeta(field.meta);
		return overrideTy != null ? overrideTy : toRustType(haxeRet, pos);
	}

	function rustGenericNamesFromDecls(decls:RustGenericParameters):Array<String> {
		var out:Array<String> = [];
		for (parameter in decls) {
			switch (parameter) {
				case GenericLifetimeParam(name, _): out.push("'" + name.name);
				case GenericTypeParam(name, _, _) | GenericConstParam(name, _, _): out.push(name.name);
			}
		}
		return out;
	}

	function rustGenericArgumentsFromDecls(decls:RustGenericParameters):Array<RustGenericArgument> {
		var out:Array<RustGenericArgument> = [];
		for (parameter in decls) {
			switch (parameter) {
				case GenericLifetimeParam(name, _): out.push(GenericLifetime(RustLifetime.named(name.name)));
				case GenericTypeParam(name, _, _): out.push(GenericType(rustNamedType(name.name)));
				case GenericConstParam(name, _, _): out.push(GenericConst(reflaxe.rust.ast.RustAST.RustConstArgument.path(RustPath.single(name.name))));
			}
		}
		return out;
	}

	function rustGenericDeclsForClass(classType:ClassType):RustGenericParameters {
		var out:Array<String> = [];
		var found = false;
		var metadataPos:Null<haxe.macro.Expr.Position> = null;

		for (entry in classType.meta.get()) {
			if (entry.name != ":rustGeneric")
				continue;
			found = true;
			if (metadataPos == null)
				metadataPos = entry.pos;

			if (entry.params == null || entry.params.length == 0) {
				#if eval
				RustDiagnostic.error(RustDiagnosticId.MetadataArity, "`@:rustGeneric` requires a single parameter.", entry.pos);
				#end
				continue;
			}

			switch (entry.params[0].expr) {
				case EConst(CString(s, _)):
					out.push(s);
				case EArrayDecl(values):
					{
						for (v in values) {
							switch (v.expr) {
								case EConst(CString(s, _)):
									out.push(s);
								case _:
									#if eval
									RustDiagnostic.error(RustDiagnosticId.MetadataValue,
										"`@:rustGeneric` array must contain only strings.", entry.pos);
									#end
							}
						}
					}
				case _:
					#if eval
					RustDiagnostic.error(RustDiagnosticId.MetadataValue,
						"`@:rustGeneric` must be a string or array of strings.", entry.pos);
					#end
			}
		}

		if (found) {
			try {
				return RustMetadataSyntax.parseGenericParameterFragments(out);
			} catch (message:String) {
				#if eval
				RustDiagnostic.error(RustDiagnosticId.MetadataValue, "Invalid class `@:rustGeneric` syntax: " + message, metadataPos);
				#end
				return RustGenericParameters.empty();
			}
		}

		// Default bounds policy for class-level generics:
		//
		// Class instances are interior-mutable (`HxRef<_>`) and methods commonly need to return
		// values by value while borrowing `self`. To preserve Haxe's "values are reusable" semantics,
		// codegen often clones non-`Copy` fields/values, so we default to `T: Clone` for class params.
		var defaultBounds:Array<RustGenericBound> = [
			GenericTraitBound(RustPath.single("Clone"), TraitBoundRequired),
			GenericTraitBound(RustPath.single("Send"), TraitBoundRequired),
			GenericTraitBound(RustPath.single("Sync"), TraitBoundRequired)
		];
		return RustGenericParameters.of([
			for (parameter in classType.params)
				GenericTypeParam(RustIdentifier.named(parameter.name), defaultBounds.copy(), null)
		]);
	}

	function rustClassTypeInstType(classType:ClassType):RustType {
		var decls = rustGenericDeclsForClass(classType);
		return RNamed(rustRelativePath([rustTypeNameForClass(classType)], rustGenericArgumentsFromDecls(decls)));
	}

	function rustCrateClassInstType(classType:ClassType):RustType {
		var names = rustModuleSegmentsForClass(classType);
		names.push(rustTypeNameForClass(classType));
		return RNamed(rustCratePath(names, rustGenericArgumentsFromDecls(rustGenericDeclsForClass(classType))));
	}

	function rustHxRefClassInstType(classType:ClassType):RustType {
		return rustHxRefType(rustCrateClassInstType(classType));
	}

	function rustBorrowedRefCellClassInstType(classType:ClassType):RustType {
		return RBorrow(rustRefCellType(rustClassTypeInstType(classType)), false, null);
	}

	function rustClassTypeInst(classType:ClassType):String {
		return rustTypeToString(rustClassTypeInstType(classType));
	}

	function haxeTypeContainsClassTypeParam(t:Type, typeParamNames:Map<String, Bool>):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, params): {
					var cls = clsRef.get();
					if (cls != null) {
						switch (cls.kind) {
							case KTypeParameter(_):
								return typeParamNames.exists(cls.name);
							case _:
						}
					}
					for (p in params)
						if (haxeTypeContainsClassTypeParam(p, typeParamNames))
							return true;
					false;
				}
			case TAbstract(_, params): {
					for (p in params)
						if (haxeTypeContainsClassTypeParam(p, typeParamNames))
							return true;
					false;
				}
			case TEnum(_, params): {
					for (p in params)
						if (haxeTypeContainsClassTypeParam(p, typeParamNames))
							return true;
					false;
				}
			case TFun(params, ret): {
					for (p in params)
						if (haxeTypeContainsClassTypeParam(p.t, typeParamNames))
							return true;
					haxeTypeContainsClassTypeParam(ret, typeParamNames);
				}
			case TAnonymous(anonRef): {
					var anon = anonRef.get();
					if (anon != null && anon.fields != null) {
						for (cf in anon.fields)
							if (haxeTypeContainsClassTypeParam(cf.type, typeParamNames))
								return true;
					}
					false;
				}
			case _:
				false;
		}
	}

	function classNeedsPhantomForUnusedTypeParams(classType:ClassType):Bool {
		var decls = rustGenericDeclsForClass(classType);
		var names = rustGenericNamesFromDecls(decls);
		if (names.length == 0)
			return false;

		var nameSet:Map<String, Bool> = new Map();
		for (n in names)
			nameSet.set(n, true);

		for (spec in getAllInstanceVarFieldSpecsForStruct(classType)) {
			var fieldType = specializeAncestorType(classType, spec.owner, spec.field.type);
			if (haxeTypeContainsClassTypeParam(fieldType, nameSet))
				return false;
		}
		for (spec in getAllInstanceDynamicMethodFieldSpecsForStorage(classType)) {
			var fieldType = specializeAncestorType(classType, spec.owner, spec.field.type);
			if (haxeTypeContainsClassTypeParam(fieldType, nameSet))
				return false;
		}
		return true;
	}

	/**
		Compiles a typed expression as a Rust block, optionally injecting function-entry arg rebinding.

		Why:
		- Real Rust function bodies need a one-time `let mut arg = arg;` prefix for mutated parameters.
		- Nested block expressions inside a function are not fresh function entries; repeating that
		  prefix there causes bogus moves like `let mut divisor = divisor;` inside inline-expanded
		  helper branches.

		What:
		- `includeArgRebinds = true` is only for actual function/closure/method entry bodies.
		- Nested expression blocks should use the default `false`.

		How:
		- Function-context callers pass `true`.
		- Expression-position helpers such as switch arms and branch blocks keep the default.
	 */
	function compileFunctionBody(e:TypedExpr, expectedReturn:Null<Type> = null, includeArgRebinds:Bool = false):RustBlock {
		var allowTail = true;
		if (expectedReturn != null && TypeHelper.isVoid(expectedReturn)) {
			allowTail = false;
		}

		var out:RustBlock = switch (e.expr) {
			case TBlock(exprs): compileBlock(exprs, allowTail, expectedReturn);
			case _: {
					// Single-expression function body. Non-void expression bodies must remain tails so
					// value expressions such as `try/catch` lower to the function return value.
					if (allowTail && canUseAsTailExpr(e, expectedReturn))
						{stmts: [], tail: coerceExprToExpected(compileExpr(e), e, expectedReturn)} else {stmts: [compileStmt(e)], tail: null};
				}
		};

		// Rust function parameters are immutable by default. Haxe code (including upstream std)
		// occasionally assigns to arguments (e.g. `s = urlEncode(s)`), which requires `mut`.
		//
		// Keep the signature stable (no `mut` in params) and shadow mutated args in the body:
		// `let mut s = s;`
		if (includeArgRebinds && currentMutatedArgs != null && currentMutatedArgs.length > 0) {
			var prefix:Array<RustStmt> = [];
			for (a in currentMutatedArgs) {
				if (a == null || a.length == 0)
					continue;
				if (a == "_" || a == "self_" || a == "_self_")
					continue;
				prefix.push(RLet(a, true, null, EPath(a)));
			}
			if (prefix.length > 0) {
				out = {stmts: prefix.concat(out.stmts), tail: out.tail};
			}
		}

		return out;
	}

	function compileBlock(exprs:Array<TypedExpr>, allowTail:Bool = true, expectedTail:Null<Type> = null):RustBlock {
		var stmts:Array<RustStmt> = [];
		var tail:Null<RustExpr> = null;

		for (i in 0...exprs.length) {
			var e = exprs[i];
			var isLast = (i == exprs.length - 1);

			if (allowTail && isLast && canUseAsTailExpr(e, expectedTail)) {
				tail = coerceExprToExpected(compileExpr(e), e, expectedTail);
				break;
			}

			// Rust warns on `unused_assignments` if we emit default initializers that are immediately
			// overwritten (common for `Null<T>` locals initialized to `null` and then assigned).
			//
			// Keep semantics and output tidy by eliding the initializer when the very next statement
			// is a direct assignment to that local.
			//
			// This is intentionally conservative: only the immediate-next statement is considered
			// (no control-flow analysis).
			var u = unwrapMetaParen(e);
			var handled = false;
			switch (u.expr) {
				case TVar(v, init) if (init != null && isNullType(v.t) && isNullConstExpr(init)):
					{
						if (!isCapturedCellLocal(v) && currentMutatedLocals != null && currentMutatedLocals.exists(v.id) && i + 1 < exprs.length) {
							function isDirectLocalAssignTo(target:TVar, expr:TypedExpr):Bool {
								var ue = unwrapMetaParen(expr);
								return switch (ue.expr) {
									case TBinop(OpAssign, lhs, _):
										switch (unwrapMetaParen(lhs).expr) {
											case TLocal(v2): v2.id == target.id;
											case _: false;
										}
									case TBinop(OpAssignOp(_), lhs, _):
										switch (unwrapMetaParen(lhs).expr) {
											case TLocal(v2): v2.id == target.id;
											case _: false;
										}
									case _:
										false;
								}
							}

							if (isDirectLocalAssignTo(v, exprs[i + 1])) {
								var name = rustLocalDeclIdent(v);
								var rustTy = toRustType(v.t, e.pos);
								#if eval
								if (Context.defined("rust_debug_string_types")
									&& useNullableStringRepresentation()
									&& rustTypesEqual(rustTy, RString)) {
									var vt = TypeTools.toString(v.t);
									var it = init != null ? TypeTools.toString(init.t) : "<none>";
									Context.warning("rust_debug_string_types nullable-init TVar `" + name + "`: v.t=" + vt + ", init.t=" + it, e.pos);
								}
								#end
								function countDirectAssignsTo(target:TVar, expr:TypedExpr):Int {
									var count = 0;
									function scan(x:TypedExpr):Void {
										switch (x.expr) {
											case TBinop(OpAssign, lhs, _) | TBinop(OpAssignOp(_), lhs, _):
												{
													switch (unwrapMetaParen(lhs).expr) {
														case TLocal(v2) if (v2.id == target.id):
															count++;
														case _:
													}
												}
											case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement):
												{
													switch (unwrapMetaParen(inner).expr) {
														case TLocal(v2) if (v2.id == target.id):
															count++;
														case _:
													}
												}
											case _:
										}
										TypedExprTools.iter(x, scan);
									}
									scan(expr);
									return count;
								}

								var assignCount = 0;
								for (j in (i + 1)...exprs.length) {
									assignCount += countDirectAssignsTo(v, exprs[j]);
								}

								// Rust allows `let x; x = value;` without `mut` (the first assignment is initialization).
								// Only require `mut` if we see multiple assignments (or `++/--`).
								var mutable = assignCount > 1;
								stmts.push(RLet(name, mutable, rustTy, null));
								handled = true;
							} else {
								// fall through to default
							}
						}
					}
				case TVar(v, init) if (init != null && i + 1 < exprs.length):
					{
						// Conservative move optimization (straight-line only):
						// If we immediately overwrite a local `x` on the next statement, then `var y = x; x = ...;`
						// does not need to clone `x` into `y`. Moving `x` is safe because the old value dies before
						// any subsequent read of `x`.
						//
						// This is primarily useful for `String` (owned `String` in Rust), where cloning is costly.
						function unwrapToLocal(e:TypedExpr):Null<TVar> {
							var cur = unwrapMetaParen(e);
							while (true) {
								switch (cur.expr) {
									case TCast(inner, _):
										cur = unwrapMetaParen(inner);
										continue;
									case _:
								}
								break;
							}
							return switch (cur.expr) {
								case TLocal(v): v;
								case _: null;
							}
						}

						var src = unwrapToLocal(init);
						if (src != null && isStringType(src.t) && isStringType(v.t)) {
							function isDirectLocalAssignTo(target:TVar, expr:TypedExpr):Bool {
								var ue = unwrapMetaParen(expr);
								return switch (ue.expr) {
									case TBinop(OpAssign, lhs, _):
										switch (unwrapMetaParen(lhs).expr) {
											case TLocal(v2): v2.id == target.id;
											case _: false;
										}
									case _:
										false;
								}
							}

							if (isDirectLocalAssignTo(src, exprs[i + 1])) {
								var name = rustLocalDeclIdent(v);
								var rustTy = toRustType(v.t, e.pos);
								#if eval
								if (Context.defined("rust_debug_string_types")
									&& useNullableStringRepresentation()
									&& rustTypesEqual(rustTy, RString)) {
									var vt = TypeTools.toString(v.t);
									var it = init != null ? TypeTools.toString(init.t) : "<none>";
									Context.warning("rust_debug_string_types move-opt TVar `" + name + "`: v.t=" + vt + ", init.t=" + it, e.pos);
								}
								#end
								var initExpr = wrapBorrowIfNeeded(compileExpr(init), rustTy, init);
								var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(v.id);
								stmts.push(RLet(name, mutable, rustTy, initExpr));
								handled = true;
							}
						}
					}
				case _:
			}

			var emittedStmt:Null<RustStmt> = null;
			if (!handled) {
				emittedStmt = compileStmt(e);
				stmts.push(emittedStmt);
			}

			// Avoid emitting Rust code that is statically unreachable (and triggers `unreachable_code` warnings).
			//
			// Why both checks:
			// - `exprAlwaysDiverges(e)` catches typed Haxe diverging forms (`throw/return/break/continue`).
			// - `rustStmtAlwaysDiverges(...)` catches divergence that only becomes obvious after lowering
			//   (for example `if/else` where both branches lower to `hxrt::exception::throw(...)`).
			//
			// This keeps explicit-return lambdas/functions warning-free without requiring source-style
			// workarounds (implicit returns).
			if ((emittedStmt != null && rustStmtAlwaysDiverges(emittedStmt)) || exprAlwaysDiverges(e))
				break;
		}

		return {stmts: stmts, tail: tail};
	}

	function isStmtOnlyExpr(e:TypedExpr):Bool {
		// Statement-ness should ignore wrapper nodes so `@:meta return ...` and `(return ...)`
		// are treated consistently with plain `return ...` in tail-position checks.
		var cur = unwrapMetaParen(e);
		return switch (cur.expr) {
			case TVar(_, _): true;
			case TReturn(_): true;
			case TThrow(_): true;
			case TWhile(_, _, _): true;
			case TFor(_, _, _): true;
			case TBreak: true;
			case TContinue: true;
			case _: false;
		}
	}

	function canUseAsTailExpr(e:TypedExpr, expectedTail:Null<Type>):Bool {
		// A throwing expression is valid in any non-Void value position because the generated
		// Rust call returns `!`. Keeping it as the tail preserves that diverging type; lowering
		// it as a semicolon statement would turn enclosing blocks into `()`.
		switch (unwrapMetaParen(e).expr) {
			case TThrow(_):
				return expectedTail != null && !TypeHelper.isVoid(expectedTail);
			case _:
		}
		if (isStmtOnlyExpr(e))
			return false;
		if (!TypeHelper.isVoid(e.t))
			return true;
		if (expectedTail == null || TypeHelper.isVoid(expectedTail))
			return false;

		// Haxe types a top-level try/catch as Void when every branch exits via `return`,
		// but Rust still needs the generated catch_unwind match to be the final expression
		// of the non-Void function. Emitting it as a semicolon statement changes the body
		// type to `()`.
		return switch (unwrapMetaParen(e).expr) {
			case TTry(_, _): true;
			case _: false;
		}
	}

	function exprAlwaysDiverges(e:TypedExpr):Bool {
		var cur = unwrapMetaParen(e);
		return switch (cur.expr) {
			case TThrow(_): true;
			case TReturn(_): true;
			case TBreak: true;
			case TContinue: true;
			case _: false;
		}
	}

	/**
		Returns true when a Rust statement is statically diverging (`!`) and never produces a value.

		Why this exists:
		Rust warns on `return <expr>` when `<expr>` already diverges (for example `todo!()`,
		`panic!()`, `hxrt::exception::throw(...)`). The `return` itself becomes unreachable.

		How it is used:
		`TReturn` lowering checks this via `rustExprAlwaysDiverges(...)` and emits the diverging
		expression directly, preserving behavior while keeping generated code warning-free.
	**/
	function rustStmtAlwaysDiverges(s:RustStmt):Bool {
		return switch (s) {
			case RReturn(_):
				true;
			case RSemi(e):
				rustExprAlwaysDiverges(e);
			case RExpr(e, _):
				rustExprAlwaysDiverges(e);
			case RBreak | RContinue:
				true;
			case _:
				false;
		}
	}

	/**
		Conservative divergence detector for generated Rust expressions.

		This only answers "true" when we are confident the expression has `!` semantics.
		False negatives are acceptable (they only miss an optimization), while false positives
		would change control flow. Keep checks intentionally strict.
	**/
	function rustExprAlwaysDiverges(e:RustExpr):Bool {
		return switch (e) {
			case ERaw(fragment): var raw = StringTools.trim(fragment.code); raw == "todo!()" || raw == "unreachable!()" || StringTools.startsWith(raw, "panic!(");
			case EMacroCall(name, _): name == "todo" || name == "unreachable" || name == "panic";
			case ECall(func, _):
				switch (func) {
					case EPath(path):
						path == "hxrt::exception::throw";
					case _:
						false;
				}
			case EBlock(b):
				if (b.tail != null) {
					rustExprAlwaysDiverges(b.tail);
				} else if (b.stmts.length > 0) {
					rustStmtAlwaysDiverges(b.stmts[b.stmts.length - 1]);
				} else {
					false;
				}
			case EIf(_, thenExpr, elseExpr): elseExpr != null && rustExprAlwaysDiverges(thenExpr) && rustExprAlwaysDiverges(elseExpr);
			case EMatch(_, arms):
				if (arms.length == 0) {
					false;
				} else {
					var allDiverge = true;
					for (arm in arms) {
						if (!rustExprAlwaysDiverges(arm.expr)) {
							allDiverge = false;
							break;
						}
					}
					allDiverge;
				}
			case _:
				false;
		}
	}

	function compileStmt(e:TypedExpr):RustStmt {
		function unwrapMetaParenCast(expr:TypedExpr):TypedExpr {
			var u = unwrapMetaParen(expr);
			return switch (u.expr) {
				case TCast(e1, _): unwrapMetaParenCast(e1);
				case _: u;
			}
		}

		function matchesFieldName(fa:FieldAccess, expected:String):Bool {
			return switch (fa) {
				case FInstance(_, _, cfRef): var cf = cfRef.get(); cf != null && cf.getHaxeName() == expected;
				case FAnon(cfRef): var cf = cfRef.get(); cf != null && cf.getHaxeName() == expected;
				case FClosure(_, cfRef): var cf = cfRef.get(); cf != null && cf.getHaxeName() == expected;
				case FDynamic(name):
					name == expected;
				case _:
					false;
			}
		}

		function localFromExpr(expr:TypedExpr):Null<TVar> {
			return switch (unwrapMetaParenCast(expr).expr) {
				case TLocal(v): v;
				case _: null;
			}
		}

		function exprReferencesAnyLocalIds(root:TypedExpr, localIds:Map<Int, Bool>):Bool {
			var found = false;
			function scan(node:TypedExpr):Void {
				if (found)
					return;
				switch (unwrapMetaParenCast(node).expr) {
					case TLocal(v):
						if (localIds.exists(v.id)) {
							found = true;
							return;
						}
					case _:
				}
				TypedExprTools.iter(node, scan);
			}
			scan(root);
			return found;
		}

		function exprListReferencesAnyLocalIds(exprs:Array<TypedExpr>, localIds:Map<Int, Bool>):Bool {
			for (expr in exprs) {
				if (exprReferencesAnyLocalIds(expr, localIds))
					return true;
			}
			return false;
		}

		function asExprList(expr:TypedExpr):Array<TypedExpr> {
			return switch (unwrapMetaParen(expr).expr) {
				case TBlock(es): {
						var out:Array<TypedExpr> = [];
						for (x in es) {
							switch (unwrapMetaParen(x).expr) {
								case TConst(TNull):
								case _:
									out.push(x);
							}
						}
						out;
					}
				case _:
					[expr];
			}
		}

		function canUseBorrowedArrayIteration(iterable:TypedExpr, loopBodyExprs:Array<TypedExpr>):Bool {
			var iterableLocal = localFromExpr(iterable);
			if (iterableLocal == null) {
				recordLoopOptimizationSkipped("array_iter_borrowed.direct_for.iterable_not_local");
				return false;
			}
			var aliases = arrayAliasIdsForLocal(iterableLocal.id);
			if (exprListReferencesAnyLocalIds(loopBodyExprs, aliases)) {
				recordLoopOptimizationSkipped("array_iter_borrowed.direct_for.alias_hazard");
				return false;
			}
			recordLoopOptimizationApplied("array_iter_borrowed.direct_for");
			return true;
		}

		return switch (e.expr) {
			case TBlock(exprs): {
					// Haxe desugars `for (x in iterable)` into:
					// `{ var it = iterable.iterator(); while (it.hasNext()) { var x = it.next(); body } }`
					//
					// For Rust-first surfaces (Vec/Slice), lower this back to a Rust `for` loop and avoid
					// having to represent Haxe's `Iterator<T>` type in the backend.
					function iterClonedExpr(x:TypedExpr):RustExpr {
						var base = ECall(EField(compileExpr(x), "iter"), []);
						return ECall(EField(base, iterBorrowMethod(x.t)), []);
					}

					function extractRustForIterable(init:TypedExpr):Null<RustExpr> {
						var u = unwrapMetaParenCast(init);
						return switch (u.expr) {
							case TCall(callExpr, callArgs): {
									var c = unwrapMetaParenCast(callExpr);
									switch (c.expr) {
										// Instance `obj.iterator()` (may print as `obj.iter()` due to @:native).
										case TField(obj, fa): {
												var objU = unwrapMetaParenCast(obj);

												// The while-loop shape already proved this "iterator" variable is used
												// with `.hasNext()` / `.next()`. For Rust-first surfaces, recover an idiomatic
												// Rust iterable to feed into a `for` loop.
												if (isRustVecType(objU.t) || isRustSliceType(objU.t)) {
													return iterClonedExpr(objU);
												}

												// Owned iterators (`rust.Iter<T>`) can be consumed directly by a Rust `for`.
												if (isRustIterType(objU.t) && matchesFieldName(fa, "iterator")) {
													return compileExpr(u);
												}

												// `rust.HashMap` iterators (`keys()` / `values()`) are already valid Rust
												// iterables; use them directly (borrowed items, no cloning).
												if (isRustHashMapType(objU.t)
													&& (matchesFieldName(fa, "keys") || matchesFieldName(fa, "values"))) {
													return compileExpr(u);
												}

												if (callArgs != null && callArgs.length == 1 && isRustSliceType(callArgs[0].t)) {
													// Abstract impl calls: `Slice_Impl_.iter(s)` show up as static field calls.
													switch (fa) {
														case FStatic(_, _) | FDynamic(_):
															return iterClonedExpr(callArgs[0]);
														case _:
															return null;
													}
												}

												return null;
											}
										case _:
											null;
									}
								}
							case _:
								null;
						}
					}

					function tryLowerDesugaredFor(exprs:Array<TypedExpr>):Null<RustStmt> {
						if (exprs == null || exprs.length < 2)
							return null;

						// Statement-position blocks often include stray `null` expressions; ignore them
						// so we can pattern-match the canonical `for` desugaring shape.
						function stripNulls(es:Array<TypedExpr>):Array<TypedExpr> {
							var out:Array<TypedExpr> = [];
							for (e in es) {
								var u = unwrapMetaParen(e);
								switch (u.expr) {
									case TConst(TNull):
									case _:
										out.push(e);
								}
							}
							return out;
						}

						var es = stripNulls(exprs);

						function extractArraySourceFromCond(cond:TypedExpr, idxVar:TVar):Null<TypedExpr> {
							var condU = unwrapMetaParenCast(cond);
							return switch (condU.expr) {
								case TBinop(OpLt, lhs, rhs): {
										var lhsLocal = localFromExpr(lhs);
										if (lhsLocal == null || lhsLocal.id != idxVar.id) {
											null;
										} else {
											switch (unwrapMetaParenCast(rhs).expr) {
												case TField(obj, fa) if (matchesFieldName(fa, "length")):
													obj;
												case _:
													null;
											}
										}
									}
								case _:
									null;
							}
						}

						function matchesArrayReadHead(init:TypedExpr, idxVarId:Int, arrayLocalId:Int):Bool {
							return switch (unwrapMetaParenCast(init).expr) {
								case TArray(arr, idx): {
										var arrLocal = localFromExpr(arr);
										if (arrLocal == null || arrLocal.id != arrayLocalId) {
											false;
										} else {
											var idxAliases:Map<Int, Bool> = [];
											idxAliases.set(idxVarId, true);
											exprReferencesAnyLocalIds(idx, idxAliases);
										}
									}
								case _:
									false;
							}
						}

						function isIndexAdvanceExpr(expr:TypedExpr, idxVarId:Int):Bool {
							var idxAliases:Map<Int, Bool> = [];
							idxAliases.set(idxVarId, true);
							return switch (unwrapMetaParenCast(expr).expr) {
								case TBinop(OpAssign, lhs, rhs) | TBinop(OpAssignOp(_), lhs, rhs): {
										var lhsLocal = localFromExpr(lhs);
										lhsLocal != null && lhsLocal.id == idxVarId && exprReferencesAnyLocalIds(rhs, idxAliases)
										;
									}
								case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement): {
										var innerLocal = localFromExpr(inner);
										innerLocal != null && innerLocal.id == idxVarId
										;
									}
								case TBlock(inner):
									{
										var cleaned = stripNulls(inner);
										if (cleaned.length == 0) {
											false;
										} else {
											var firstIsAdvance = isIndexAdvanceExpr(cleaned[0], idxVarId);
											var tailIsIdxOnly = true;
											for (i in 1...cleaned.length) {
												if (!exprReferencesAnyLocalIds(cleaned[i], idxAliases)) {
													tailIsIdxOnly = false;
													break;
												}
											}
											firstIsAdvance && tailIsIdxOnly
											;
										}
									}
								case _:
									false;
							}
						}

						function tryLowerDesugaredArrayFor(es:Array<TypedExpr>):Null<RustStmt> {
							if (es.length != 2 && es.length != 3)
								return null;

							var idxVar:Null<TVar> = null;
							switch (unwrapMetaParen(es[0]).expr) {
								case TVar(v, _):
									idxVar = v;
								case _:
									return null;
							}
							if (idxVar == null)
								return null;

							var whileExpr = unwrapMetaParen(es[es.length - 1]);
							var whileCond:Null<TypedExpr> = null;
							var whileBody:Null<TypedExpr> = null;
							switch (whileExpr.expr) {
								case TWhile(cond, body, normalWhile) if (normalWhile):
									whileCond = cond;
									whileBody = body;
								case _:
									return null;
							}
							if (whileCond == null || whileBody == null)
								return null;

							var arraySource = extractArraySourceFromCond(whileCond, idxVar);
							if (arraySource == null)
								return null;
							if (!isArrayType(arraySource.t))
								return null;

							var arraySourceLocal = localFromExpr(arraySource);
							if (arraySourceLocal == null)
								return null;

							var aliasIds:Map<Int, Bool> = [];
							aliasIds.set(arraySourceLocal.id, true);
							var preludeStmt:Null<RustStmt> = null;

							if (es.length == 3) {
								switch (unwrapMetaParen(es[1]).expr) {
									case TVar(arrVar, init) if (init != null && isArrayType(arrVar.t)):
										{
											aliasIds.set(arrVar.id, true);
											var sourceLocal = localFromExpr(init);
											if (sourceLocal != null)
												aliasIds.set(sourceLocal.id, true);
											preludeStmt = compileStmt(es[1]);
										}
									case _:
										return null;
								}
							}

							// Include function-scope aliases of already-known array locals.
							// This keeps borrowed-loop lowering semantics-safe when aliases are
							// created outside the loop block (e.g. `var ys = xs;`).
							var aliasSeed:Array<Int> = [for (id in aliasIds.keys()) id];
							for (seedId in aliasSeed) {
								var knownAliases = arrayAliasIdsForLocal(seedId);
								for (id in knownAliases.keys())
									aliasIds.set(id, true);
							}

							var bodyExprs = switch (unwrapMetaParen(whileBody).expr) {
								case TBlock(inner): stripNulls(inner);
								case _:
									return null;
							}
							if (bodyExprs.length == 0)
								return null;

							var loopVar:Null<TVar> = null;
							switch (unwrapMetaParen(bodyExprs[0]).expr) {
								case TVar(v, init) if (init != null && matchesArrayReadHead(init, idxVar.id, arraySourceLocal.id)):
									loopVar = v;
								case _:
									return null;
							}
							if (loopVar == null)
								return null;

							var userBodyExprs = bodyExprs.slice(1);
							if (userBodyExprs.length > 0 && isIndexAdvanceExpr(userBodyExprs[0], idxVar.id))
								userBodyExprs = userBodyExprs.slice(1);

							// Conservative safety gate: if user loop body touches the iterated array
							// binding (or its immediate source local), keep canonical index/while lowering.
							if (exprListReferencesAnyLocalIds(userBodyExprs, aliasIds)) {
								recordLoopOptimizationSkipped("array_iter_borrowed.desugared_for.alias_hazard");
								return null;
							}

							var iterExpr = ECall(EField(compileExpr(arraySource), "iter_borrowed"), []);
							recordLoopOptimizationApplied("array_iter_borrowed.desugared_for");
							var bodyBlock = compileBlock(userBodyExprs, false);
							var loweredFor = RFor(rustLocalDeclIdent(loopVar), iterExpr, bodyBlock);
							return if (preludeStmt == null) {
								loweredFor;
							} else {
								RExpr(EBlock({stmts: [preludeStmt, loweredFor], tail: null}), false);
							}
						}

						var loweredArray = tryLowerDesugaredArrayFor(es);
						if (loweredArray != null)
							return loweredArray;

						if (es.length != 2)
							return null;

						var first = unwrapMetaParen(es[0]);
						var second = unwrapMetaParen(es[1]);

						var itVar:Null<TVar> = null;
						var itInit:Null<TypedExpr> = null;
						switch (first.expr) {
							case TVar(v, init) if (init != null):
								itVar = v;
								itInit = init;
							case _:
								return null;
						}

						switch (second.expr) {
							case TWhile(cond, body, normalWhile) if (normalWhile):
								{
									function isIterMethodCall(callExpr:TypedExpr, expected:String):Bool {
										var c = unwrapMetaParen(callExpr);
										return switch (c.expr) {
											case TField(obj, fa):
												switch (unwrapMetaParen(obj).expr) {
													case TLocal(v) if (itVar != null && v.id == itVar.id && matchesFieldName(fa, expected)):
														true;
													case _:
														false;
												}
											case _:
												false;
										}
									}

									// Condition: it.hasNext()
									var c = unwrapMetaParen(cond);
									switch (c.expr) {
										case TCall(callExpr, []): {
												if (!isIterMethodCall(callExpr, "hasNext"))
													return null;
											}
										case _:
											return null;
									}

									// Body: `{ var x = it.next(); ... }`
									var b = unwrapMetaParen(body);
									var bodyExprs = switch (b.expr) {
										case TBlock(es): es;
										case _: return null;
									}
									bodyExprs = stripNulls(bodyExprs);
									if (bodyExprs.length == 0)
										return null;

									var head = unwrapMetaParen(bodyExprs[0]);
									var loopVar:Null<TVar> = null;
									switch (head.expr) {
										case TVar(v, init) if (init != null): {
												// init must be it.next()
												var initU = unwrapMetaParen(init);
												switch (initU.expr) {
													case TCall(callExpr, []):
														if (!isIterMethodCall(callExpr, "next"))
															return null;
														loopVar = v;
													case _:
														return null;
												}
											}
										case _:
											return null;
									}
									if (loopVar == null)
										return null;

									// Why: Haxe also accepts shared anonymous records whose mutable function-valued
									// fields happen to implement `hasNext` / `next`. Those values are not native Rust
									// iterators: their field identity and mutation remain observable through aliases.
									// What: keep the canonical Haxe `while` protocol for ordinary anonymous records.
									// How: returning `null` lets the enclosing block lower its original iterator local,
									// `hasNext()` condition, and `next()` call through typed `Anon` field access.
									if (itVar != null && isAnonObjectType(itVar.t) && !isIteratorStructType(itVar.t)) {
										recordLoopOptimizationSkipped("anon_iterator_record.protocol_semantics");
										return null;
									}

									var it = extractRustForIterable(itInit);
									// If we can't recover a Rust-native iterable, fall back to using the iterator value
									// directly. `hxrt::iter::Iter<T>` implements `IntoIterator`, so Rust `for` loops can
									// consume it safely.
									if (it == null)
										it = compileExpr(itInit);

									var bodyBlock = compileBlock(bodyExprs.slice(1), false);
									return RFor(rustLocalDeclIdent(loopVar), it, bodyBlock);
								}
							case _:
								return null;
						}
					}

					var lowered = tryLowerDesugaredFor(exprs);
					if (lowered != null)
						return lowered;

					// Fallback: treat block as a statement-position expression (unit block; no semicolon).
					RExpr(EBlock(compileBlock(exprs, false)), false);
				}
			case TVar(v, init): {
					var name = rustLocalDeclIdent(v);
					var rustTy = toRustType(v.t, e.pos);
					var cellBackedLocal = isCapturedCellLocal(v);
					var localStorageTy:RustType = cellBackedLocal ? rustHxRefType(rustTy) : rustTy;
					#if eval
					if (Context.defined("rust_debug_string_types")
						&& useNullableStringRepresentation()
						&& rustTypesEqual(rustTy, RString)) {
						var vt = TypeTools.toString(v.t);
						var it = init != null ? TypeTools.toString(init.t) : "<none>";
						Context.warning("rust_debug_string_types TVar `" + name + "`: v.t=" + vt + ", init.t=" + it, e.pos);
					}
					#end
					var initExpr = init != null ? compileExpr(init) : null;
					if (initExpr != null) {
						// Haxe's inliner/desugarer frequently introduces `_g*` temporaries to preserve evaluation
						// order (e.g. for comprehensions / iterator lowering). For `Array<T>` (mapped to a
						// shared HXRT array handle), these temporaries should not *move* the original value.
						//
						// NOTE: `Array<T>` now maps to `hxrt::array::Array<T>` backed by `HxRef<Vec<T>>`, so
						// cloning is a shared-handle clone and is handled by `maybeCloneForReuseValue(...)`
						// below when needed.

						switch (followType(v.t)) {
							// Function values require coercion into our function representation.
							case TFun(_, _):
								initExpr = coerceArgForParam(initExpr, init, v.t);
							case _:
								initExpr = wrapBorrowIfNeeded(initExpr, rustTy, init);
						}

						// Preserve Haxe reuse/aliasing semantics for reference-like values:
						// `var b = a;` must not move `a` in Rust output.
						initExpr = maybeCloneForReuseValue(initExpr, init);
						if (needsForcedAliasCloneForLocalDecl(v, init, name))
							initExpr = ECall(EField(initExpr, "clone"), []);

						// Coerce the initializer to the declared local type (handles `Null<T>` Option wrapping,
						// trait upcasts, structural typedef adapters, numeric widening, etc).
						initExpr = coerceExprToExpected(initExpr, init, v.t);
					}
					if (cellBackedLocal) {
						// Captured+mutated locals use shared cell storage so closures observe updates from
						// outer scopes. Keep the local binding immutable and mutate through `borrow_mut()`.
						var boxedInit = initExpr != null ? initExpr : ERaw(RustRawCode.compilerAt(defaultValueForType(v.t, e.pos), RawDefaultValueFallback,
							e.pos));
						initExpr = ECall(EPath("crate::HxRef::new"), [boxedInit]);
					}
					var mutable = !cellBackedLocal && currentMutatedLocals != null && currentMutatedLocals.exists(v.id);
					var readCount = currentLocalReadCounts != null
						&& currentLocalReadCounts.exists(v.id) ? currentLocalReadCounts.get(v.id) : 0;
					if (readCount == 0 && !mutable) {
						// Keep initializer side effects but avoid `unused_variables` warnings for
						// compiler-introduced temporaries that are never read.
						var underscoreTy:Null<RustType> = initExpr == null ? localStorageTy : null;
						RLet("_", false, underscoreTy, initExpr);
					} else {
						RLet(name, mutable, localStorageTy, initExpr);
					}
				}
			case TIf(cond, eThen, eElse): {
					// Statement-position if: force unit branches so we can omit a trailing semicolon.
					var condExpr = coerceExprToExpected(compileExpr(cond), cond, Context.getType("Bool"));
					var thenExpr = EBlock(compileVoidBody(eThen));
					var elseExpr:Null<RustExpr> = eElse != null ? EBlock(compileVoidBody(eElse)) : null;
					RExpr(EIf(condExpr, thenExpr, elseExpr), false);
				}
			case TParenthesis(e1):
				compileStmt(e1);
			case TMeta(_, e1):
				compileStmt(e1);
			case TSwitch(switchExpr, cases, edef):
				// Statement-position switch: force void arms.
				RExpr(compileSwitch(switchExpr, cases, edef, Context.getType("Void")), false);
			case TWhile(cond, body, normalWhile): {
					var out = if (normalWhile) {
						// Rust lints `while true { ... }` in favor of `loop { ... }`.
						// `deny_warnings` snapshot expects generated code to remain warning-free.
						switch (unwrapMetaParen(cond).expr) {
							case TConst(TBool(true)):
								RLoop(compileVoidBody(body));
							case _:
								RWhile(coerceExprToExpected(compileExpr(cond), cond, Context.getType("Bool")), compileVoidBody(body));
						}
					} else {
						// do/while: `loop { body; if !cond { break; } }`
						var condExpr = coerceExprToExpected(compileExpr(cond), cond, Context.getType("Bool"));
						var b = compileVoidBody(body);
						var stmts = b.stmts.copy();
						if (b.tail != null)
							stmts.push(RSemi(b.tail));
						stmts.push(RSemi(EIf(EUnary("!", condExpr), EBlock({stmts: [RBreak], tail: null}), null)));
						RLoop({stmts: stmts, tail: null});
					};
					consumeLocalReadsLikeReadCounter(cond);
					consumeLocalReadsLikeReadCounter(body);
					out;
				}
			case TFor(v, iterable, body): {
					function iterCloned(x:TypedExpr):RustExpr {
						// For `Array<T>`, prefer borrowed iteration only when the loop body does not
						// reference the iterable binding. Any reference keeps canonical clone-snapshot
						// lowering to avoid semantic drift.
						if (isArrayType(x.t)) {
							var arrayMethod = canUseBorrowedArrayIteration(x, asExprList(body)) ? "iter_borrowed" : "iter";
							return ECall(EField(compileExpr(x), arrayMethod), []);
						}
						var base = ECall(EField(compileExpr(x), "iter"), []);
						return ECall(EField(base, iterBorrowMethod(x.t)), []);
					}

					var it:RustExpr = switch (unwrapMetaParen(iterable).expr) {
						// Many custom iterables typecheck by providing `iterator()`. We lower specific
						// Rust-first surfaces to Rust iterators to avoid moving values (Haxe values are reusable).
						case TCall(call, []): switch (unwrapMetaParen(call).expr) {
								case TField(obj, FInstance(_, _, cfRef)):
									var cf = cfRef.get();
									if (cf != null && cf.getHaxeName() == "iterator" && (isRustVecType(obj.t) || isRustSliceType(obj.t))) {
										iterCloned(obj);
									} else {
										compileExpr(iterable);
									}
								case _:
									compileExpr(iterable);
							}
						case _:
							if (isArrayType(iterable.t) || isRustVecType(iterable.t) || isRustSliceType(iterable.t)) {
								iterCloned(iterable);
							} else {
								compileExpr(iterable);
							}
					};
					var out = RFor(rustLocalDeclIdent(v), it, compileVoidBody(body));
					consumeLocalReadsLikeReadCounter(body);
					out;
				}
			case TBreak:
				RBreak;
			case TContinue:
				RContinue;
			case TReturn(ret): {
					var retExpr = ret;
					if (currentFunctionIsAsync && ret != null) {
						var inner = extractAsyncReadyValue(ret);
						if (inner != null) {
							retExpr = inner;
						}
					}

					if (retExpr == null) {
						RReturn(null);
					} else {
						var unwrappedRet = unwrapMetaParen(retExpr);
						switch (unwrappedRet.expr) {
							case TBlock(exprs): {
									var retBlock = compileBlock(exprs, true, currentFunctionReturn);
									var retBlockExpr = EBlock(retBlock);
									// Avoid `return { ... return x; }` shapes that trigger Rust
									// `unreachable_code` warnings.
									//
									// If the lowered return block already diverges (`!`), emit it directly
									// instead of wrapping it in `return ...`.
									if (rustExprAlwaysDiverges(retBlockExpr)) {
										RExpr(retBlockExpr, false);
									} else if (retBlock.tail != null) {
										// Normalize `return { s1; ...; tail; }` to `{ s1; ...; return tail; }`.
										// This keeps explicit-return lambdas warning-free while preserving
										// Haxe evaluation order and expression semantics.
										var stmts = retBlock.stmts.copy();
										stmts.push(RReturn(retBlock.tail));
										RExpr(EBlock({stmts: stmts, tail: null}), false);
									} else {
										// Fallback: unit-like returned block.
										RReturn(retBlockExpr);
									}
								}
							case _: {
									var ex = compileExpr(retExpr);
									if (ex != null) {
										ex = coerceExprToExpected(ex, retExpr, currentFunctionReturn);
									}
									if (ex != null && rustExprAlwaysDiverges(ex)) {
										RExpr(ex, false);
									} else {
										RReturn(ex);
									}
								}
						}
					}
				}
			case TUnop(op, postFix, inner) if (postFix && (op == OpIncrement || op == OpDecrement)): {
					// Statement-position postfix local ++/-- does not need the old value.
					// Emit a direct assignment instead of `std::mem::replace(...)` to avoid
					// `unused_must_use` warnings from the returned old value.
					switch (unwrapMetaParen(inner).expr) {
						case TLocal(v): {
								var name = rustLocalRefIdent(v);
								var cellBackedLocal = isCapturedCellLocal(v) || isCapturedCellLocalName(name);
								var delta:RustExpr = TypeHelper.isFloat(inner.t) ? ELitFloat(1.0) : ELitInt(1);
								var binop = (op == OpIncrement) ? "+" : "-";
								if (cellBackedLocal) {
									// Captured+mutated locals are represented as `HxRef<T>`. Even statement-position
									// postfix increments must mutate through the shared cell so closure and outer-scope
									// reads stay coherent.
									RExpr(EBlock({
										stmts: [
											RLet("__b", true, null, ECall(EField(EPath(name), "borrow_mut"), [])),
											RSemi(EAssign(EUnary("*", EPath("__b")), EBinary(binop, EUnary("*", EPath("__b")), delta)))
										],
										tail: null
									}), false);
								} else {
									RSemi(EAssign(EPath(name), EBinary(binop, EPath(name), delta)));
								}
							}
						case _:
							RSemi(compileExpr(e));
					}
				}
			case TBinop(OpAssignOp(OpAdd), lhs, rhs) if (isStringType(followType(e.t)) || isStringType(followType(lhs.t)) || isStringType(followType(rhs.t))): {
					// Statement-position `x += y` where the result is unused.
					//
					// `compileExpr` must preserve the expression value, which can require cloning the updated
					// String. Emit a unit block that only performs the assignment when the lvalue has a
					// dedicated statement lowering.
					switch (unwrapMetaParen(lhs).expr) {
						case TArray(arrayExpr, indexExpr):
							RExpr(compileArrayElementAssignOp(OpAdd, "+", lhs, arrayExpr, indexExpr, rhs, e, false), false);
						case TLocal(_): {
								var lhsExpr = compileExpr(lhs);
								var rhsExpr = maybeCloneForReuseValue(compileExpr(rhs), rhs);
								var rhsStr:RustExpr = isStringType(followType(rhs.t)) ? EPath("__tmp") : ECall(EField(ECall(EPath("hxrt::dynamic::from"),
									[EPath("__tmp")]), "to_haxe_string"), []);

								RExpr(EBlock({
									stmts: [
										RLet("__tmp", false, null, rhsExpr),
										RSemi(EAssign(lhsExpr, wrapRustStringExpr(EMacroCall("format", [ELitString("{}{}"), lhsExpr, rhsStr]))))
									],
									tail: null
								}), false);
							}
						case _:
							RSemi(compileExpr(e));
					}
				}
			case _: {
					RSemi(compileExpr(e));
				}
		}
	}

	function compileVoidBody(e:TypedExpr):RustBlock {
		return switch (e.expr) {
			case TBlock(exprs):
				compileBlock(exprs, false);
			case _:
				{stmts: [compileStmt(e)], tail: null};
		}
	}

	function withFunctionContext<T>(bodyExpr:TypedExpr, argNames:Array<String>, expectedReturn:Null<Type>, fn:() -> T, isAsync:Bool = false):T {
		var prevMutated = currentMutatedLocals;
		var prevReadCounts = currentLocalReadCounts;
		var prevRemainingReads = currentLocalRemainingReads;
		var prevThisReadCount = currentThisReadCount;
		var prevThisRemainingReads = currentThisRemainingReads;
		var prevCapturedCellLocals = currentCapturedCellLocals;
		var prevArgNames = currentArgNames;
		var prevLocalNames = currentLocalNames;
		var prevLocalUsed = currentLocalUsed;
		var prevArrayAliasClosures = currentArrayAliasClosures;
		var prevEnumParamBinds = currentEnumParamBinds;
		var prevReturn = currentFunctionReturn;
		var prevMutatedArgs = currentMutatedArgs;
		var prevIsAsync = currentFunctionIsAsync;
		var prevFunctionContext = currentFunctionContext;

		currentMutatedLocals = collectMutatedLocals(bodyExpr);
		currentLocalReadCounts = collectLocalReadCounts(bodyExpr);
		currentLocalRemainingReads = copyIntMap(currentLocalReadCounts);
		currentThisReadCount = collectThisReadCount(bodyExpr);
		currentThisRemainingReads = currentThisReadCount;
		var capturedInThisFn = collectCapturedMutatedLocals(bodyExpr);
		var mergedCaptured:Map<Int, Bool> = [];
		if (prevCapturedCellLocals != null) {
			for (id in prevCapturedCellLocals.keys())
				mergedCaptured.set(id, true);
		}
		for (id in capturedInThisFn.keys())
			mergedCaptured.set(id, true);
		currentCapturedCellLocals = mergedCaptured;
		currentArrayAliasClosures = collectArrayAliasClosures(bodyExpr);
		currentArgNames = [];
		currentLocalNames = [];
		currentLocalUsed = [];
		// Preserve outer-scope Rust local identifiers inside nested function contexts.
		//
		// Why
		// - Nested closures can capture locals whose Rust names were already disambiguated in the
		//   enclosing scope (`done1_2`, `mutex1_3`, etc.).
		// - If the inner function context re-derives names from the original Haxe symbol, generated
		//   closure bodies can refer to stale identifiers that do not exist in that concrete scope.
		//
		// How
		// - Carry forward all previously assigned outer-local names so nested references resolve to the
		//   exact Rust identifier already emitted by the enclosing scope.
		if (prevLocalNames != null) {
			for (localId in prevLocalNames.keys()) {
				var rustName = prevLocalNames.get(localId);
				currentLocalNames.set(localId, rustName);
				currentLocalUsed.set(rustName, true);
			}
		}
		currentEnumParamBinds = null;
		currentFunctionReturn = expectedReturn;
		currentMutatedArgs = [];
		currentFunctionIsAsync = isAsync;

		// Reserve internal temporaries to avoid collisions with user locals.
		for (n in [
			"self_",
			"__tmp",
			"__hx_ok",
			"__hx_ex",
			"__hx_box",
			"__p",
			"__hx_dyn",
			"__hx_opt"
		]) {
			currentLocalUsed.set(n, true);
		}

		// Pre-allocate argument names so we can use them consistently in the signature + body.
		if (argNames == null)
			argNames = [];
		for (n in argNames) {
			var base = RustNaming.snakeIdent(n);
			var rust = RustNaming.stableUnique(base, currentLocalUsed);
			currentArgNames.set(n, rust);
		}
		currentMutatedArgs = collectMutatedArgRustNames(bodyExpr, argNames);
		var expectedReturnTypeName = expectedReturn == null ? "()" : rustTypeToString(toRustType(expectedReturn, bodyExpr.pos));
		var localNameCount = currentLocalNames == null ? 0 : [for (_ in currentLocalNames.keys()) 1].length;
		var readCountEntries = currentLocalReadCounts == null ? 0 : [for (_ in currentLocalReadCounts.keys()) 1].length;
		currentFunctionContext = new RustFuncContext("anonymous", isAsync, expectedReturnTypeName, currentMutatedArgs.copy(), localNameCount, readCountEntries);

		var out = fn();

		currentMutatedLocals = prevMutated;
		currentLocalReadCounts = prevReadCounts;
		currentLocalRemainingReads = prevRemainingReads;
		currentThisReadCount = prevThisReadCount;
		currentThisRemainingReads = prevThisRemainingReads;
		currentCapturedCellLocals = prevCapturedCellLocals;
		currentArgNames = prevArgNames;
		currentLocalNames = prevLocalNames;
		currentLocalUsed = prevLocalUsed;
		currentArrayAliasClosures = prevArrayAliasClosures;
		currentEnumParamBinds = prevEnumParamBinds;
		currentFunctionReturn = prevReturn;
		currentMutatedArgs = prevMutatedArgs;
		currentFunctionIsAsync = prevIsAsync;
		currentFunctionContext = prevFunctionContext;
		return out;
	}

	function rustArgIdent(name:String):String {
		if (currentArgNames != null && currentArgNames.exists(name)) {
			return currentArgNames.get(name);
		}
		return RustNaming.snakeIdent(name);
	}

	function rustLocalDeclIdent(v:TVar):String {
		if (v == null)
			return "_";

		// If we're inside a function context, ensure stable/unique snake_case naming.
		if (currentLocalNames != null && currentLocalUsed != null) {
			if (currentLocalNames.exists(v.id))
				return currentLocalNames.get(v.id);
			// Rust reserves `_` as a wildcard pattern; it cannot be used as an expression.
			// Haxe code frequently uses `_` as a "throwaway" local, but Haxe for-loop desugaring
			// will still reference it (e.g. `_.hasNext()`), so give it a real identifier.
			var base = (v.name == "_") ? "_unused" : RustNaming.snakeIdent(v.name);
			var rust = RustNaming.stableUnique(base, currentLocalUsed);
			currentLocalNames.set(v.id, rust);
			return rust;
		}

		return (v.name == "_") ? "_unused" : RustNaming.snakeIdent(v.name);
	}

	function rustLocalRefIdent(v:TVar):String {
		if (v == null)
			return "_";

		// If already declared/seen, reuse the assigned name.
		if (currentLocalNames != null && currentLocalNames.exists(v.id)) {
			return currentLocalNames.get(v.id);
		}

		// Function arguments are referenced as locals in the typed AST.
		if (currentArgNames != null && currentArgNames.exists(v.name)) {
			var rust = currentArgNames.get(v.name);
			if (currentLocalNames != null)
				currentLocalNames.set(v.id, rust);
			return rust;
		}

		// Fallback: treat as a local.
		return rustLocalDeclIdent(v);
	}

	inline function isCapturedCellLocalId(localId:Int):Bool {
		return currentCapturedCellLocals != null && currentCapturedCellLocals.exists(localId);
	}

	inline function isCapturedCellLocal(v:TVar):Bool {
		return v != null && isCapturedCellLocalId(v.id);
	}

	function isCapturedCellLocalName(localName:String):Bool {
		if (localName == null || currentCapturedCellLocals == null || currentLocalNames == null)
			return false;
		for (localId in currentCapturedCellLocals.keys()) {
			if (!currentLocalNames.exists(localId))
				continue;
			if (currentLocalNames.get(localId) == localName)
				return true;
		}
		return false;
	}

	function compileFunctionBodyWithContext(e:TypedExpr, expectedReturn:Null<Type>, argNames:Array<String>):RustBlock {
		return withFunctionContext(e, argNames, expectedReturn, () -> compileFunctionBody(e, expectedReturn));
	}

	function compileVoidBodyWithContext(e:TypedExpr, argNames:Array<String>):RustBlock {
		return withFunctionContext(e, argNames, Context.getType("Void"), () -> compileVoidBody(e));
	}

	function collectMutatedArgRustNames(root:TypedExpr, argNames:Array<String>):Array<String> {
		if (argNames == null || argNames.length == 0)
			return [];

		var argSet:Map<String, Bool> = [];
		for (n in argNames)
			argSet.set(n, true);

		// Haxe allows locals to shadow argument names (and the compiler will often introduce locals
		// like `this1` inside inlined abstract helpers). When that happens, a name-based scan would
		// incorrectly treat assignments to the shadowing local as "argument mutation", forcing
		// `let mut arg = arg;` prefixes and triggering `unused_mut` under `#![deny(warnings)]`.
		//
		// Track ids for locals declared in the body (including nested function args) and only
		// treat mutations as "argument mutations" when the assigned TVar is not declared locally.
		var declaredIds:Map<Int, Bool> = [];
		function collectDeclaredIds(e:TypedExpr):Void {
			var u = unwrapMetaParen(e);
			switch (u.expr) {
				case TVar(v, init):
					{
						if (v != null)
							declaredIds.set(v.id, true);
						if (init != null)
							collectDeclaredIds(init);
					}
				case TFor(v, it, body):
					{
						if (v != null)
							declaredIds.set(v.id, true);
						collectDeclaredIds(it);
						collectDeclaredIds(body);
					}
				case TTry(tryExpr, catches):
					{
						collectDeclaredIds(tryExpr);
						if (catches != null) {
							for (c in catches) {
								if (c != null && c.v != null)
									declaredIds.set(c.v.id, true);
								if (c != null && c.expr != null)
									collectDeclaredIds(c.expr);
							}
						}
					}
				case TFunction(fn):
					{
						if (fn != null && fn.args != null) {
							for (a in fn.args) {
								if (a != null && a.v != null)
									declaredIds.set(a.v.id, true);
							}
						}
						if (fn != null && fn.expr != null)
							collectDeclaredIds(fn.expr);
					}
				case _:
					TypedExprTools.iter(u, collectDeclaredIds);
			}
		}
		collectDeclaredIds(root);

		var mutated:Map<String, Bool> = [];

		function unwrapToLocal(e:TypedExpr):Null<TVar> {
			var cur = unwrapMetaParen(e);

			while (true) {
				switch (cur.expr) {
					case TCast(inner, _):
						cur = unwrapMetaParen(inner);
						continue;

					// Handle `@:from` conversions that appear as calls (common for `rust.Ref` / `rust.MutRef`).
					case TCall(callExpr, args) if (args.length == 1):
						{
							switch (callExpr.expr) {
								case TField(_, FStatic(typeRef, cfRef)): {
										var cf = cfRef.get();
										var full = typeRef.toString();
										if (cf != null
											&& cf.name == "fromValue"
											&& (full.indexOf("rust.Ref") != -1 || full.indexOf("rust.MutRef") != -1)) {
											cur = unwrapMetaParen(args[0]);
											continue;
										}
									}
								case _:
							}
						}

					case _:
				}
				break;
			}

			return switch (cur.expr) {
				case TLocal(v): v;
				case _: null;
			};
		}

		function mark(v:TVar):Void {
			if (v == null || v.name == null)
				return;
			if (!argSet.exists(v.name))
				return;
			if (declaredIds.exists(v.id))
				return;
			mutated.set(rustArgIdent(v.name), true);
		}

		function isMutatingMethod(cf:ClassField):Bool {
			for (m in cf.meta.get()) {
				if (m.name == ":rustMutating" || m.name == "rustMutating")
					return true;
			}
			return false;
		}

		function scan(e:TypedExpr):Void {
			var u = unwrapMetaParen(e);
			switch (u.expr) {
				case TBinop(OpAssign, lhs, _) | TBinop(OpAssignOp(_), lhs, _):
					{
						var v = unwrapToLocal(lhs);
						if (v != null)
							mark(v);
					}
				case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement):
					{
						var v = unwrapToLocal(inner);
						if (v != null)
							mark(v);
					}
				case TCall(callExpr, _):
					{
						switch (callExpr.expr) {
							case TField(obj, FInstance(_, _, cfRef)): {
									var cf = cfRef.get();
									if (cf != null && isMutatingMethod(cf)) {
										var v = unwrapToLocal(obj);
										if (v != null)
											mark(v);
									}
								}
							case _:
						}
					}
				case _:
			}
			TypedExprTools.iter(u, scan);
		}

		scan(root);

		var out:Array<String> = [];
		for (n in argNames) {
			var rust = rustArgIdent(n);
			if (mutated.exists(rust))
				out.push(rust);
		}
		return out;
	}

	/**
		Collects a conservative alias-closure map for `hxrt::array::Array<T>` locals in a function body.

		Why
		- Borrowed array iteration fast paths are only semantics-safe when the loop body does not
		  access the iterated array through any alias.
		- Alias creation can happen outside the loop (`var ys = xs;`) and then be used inside it,
		  so a loop-local check alone is insufficient.

		What
		- Builds an undirected local-alias graph from array-local assignments:
		  - declarations (`var b = a`)
		  - direct rebinds (`b = a`)
		- Returns transitive closure sets keyed by local id.

		How
		- The analysis is intentionally conservative and local-id based.
		- False positives only disable a fast path; false negatives risk semantic drift.
	**/
	function collectArrayAliasClosures(root:TypedExpr):Map<Int, Map<Int, Bool>> {
		var adjacency:Map<Int, Map<Int, Bool>> = [];

		inline function ensureNode(id:Int):Void {
			if (!adjacency.exists(id))
				adjacency.set(id, []);
		}

		inline function connect(a:Int, b:Int):Void {
			if (a == b) {
				ensureNode(a);
				return;
			}
			ensureNode(a);
			ensureNode(b);
			adjacency.get(a).set(b, true);
			adjacency.get(b).set(a, true);
		}

		inline function arrayLocalId(expr:TypedExpr):Null<Int> {
			return switch (unwrapMetaParen(expr).expr) {
				case TLocal(v):
					isArrayType(v.t) ? v.id : null;
				case _:
					null;
			}
		}

		function scan(node:TypedExpr):Void {
			switch (unwrapMetaParen(node).expr) {
				case TVar(v, init):
					{
						if (isArrayType(v.t))
							ensureNode(v.id);
						if (init != null) {
							var srcId = arrayLocalId(init);
							if (srcId != null && isArrayType(v.t))
								connect(v.id, srcId);
						}
					}
				case TBinop(OpAssign, lhs, rhs):
					{
						var lhsId = arrayLocalId(lhs);
						var rhsId = arrayLocalId(rhs);
						if (lhsId != null && rhsId != null)
							connect(lhsId, rhsId);
					}
				case _:
			}
			TypedExprTools.iter(node, scan);
		}

		scan(root);

		var closures:Map<Int, Map<Int, Bool>> = [];
		for (start in adjacency.keys()) {
			var seen:Map<Int, Bool> = [];
			var stack:Array<Int> = [start];
			while (stack.length > 0) {
				var id = stack.pop();
				if (seen.exists(id))
					continue;
				seen.set(id, true);
				var neighbors = adjacency.get(id);
				if (neighbors != null) {
					for (neighbor in neighbors.keys()) {
						if (!seen.exists(neighbor))
							stack.push(neighbor);
					}
				}
			}
			closures.set(start, seen);
		}
		return closures;
	}

	inline function arrayAliasIdsForLocal(localId:Int):Map<Int, Bool> {
		var aliases:Map<Int, Bool> = [];
		aliases.set(localId, true);
		if (currentArrayAliasClosures != null && currentArrayAliasClosures.exists(localId)) {
			for (id in currentArrayAliasClosures.get(localId).keys())
				aliases.set(id, true);
		}
		return aliases;
	}

	function collectMutatedLocals(root:TypedExpr):Map<Int, Bool> {
		var mutated:Map<Int, Bool> = [];
		var declaredWithoutInit:Map<Int, Bool> = [];

		/**
			Why
			- Haxe typed-tree traversal is not a contract for declaration-before-use ordering inside
			  every lowered control-flow shape.
			- Rust distinguishes first assignment to `let x;` from reassignment: the former does not
			  require `mut`, and emitting `let mut x;` trips `unused_mut` under `#![deny(warnings)]`.

			What
			- Pre-collect declaration-only locals before write classification so branch-local shapes like
			  `var x; if (...) x = a else x = b;` are understood as deferred initialization.

			How
			- The later scan can then treat writes to those locals as initializers unless they happen in
			  loops or more than once along a single execution path.
		**/
		function collectDeclarationOnlyLocals(e:TypedExpr):Void {
			switch (e.expr) {
				case TVar(v, null):
					declaredWithoutInit.set(v.id, true);
				case _:
			}
			TypedExprTools.iter(e, collectDeclarationOnlyLocals);
		}

		collectDeclarationOnlyLocals(root);

		function unwrapToLocal(e:TypedExpr):Null<TVar> {
			var cur = unwrapMetaParen(e);

			while (true) {
				switch (cur.expr) {
					case TCast(inner, _):
						cur = unwrapMetaParen(inner);
						continue;

					// Handle `@:from` conversions that appear as calls (common for `rust.Ref` / `rust.MutRef`).
					case TCall(callExpr, args) if (args.length == 1):
						{
							switch (callExpr.expr) {
								case TField(_, FStatic(typeRef, cfRef)): {
										var cf = cfRef.get();
										var full = typeRef.toString();
										if (cf != null
											&& cf.name == "fromValue"
											&& (full.indexOf("rust.Ref") != -1 || full.indexOf("rust.MutRef") != -1)) {
											cur = unwrapMetaParen(args[0]);
											continue;
										}
									}
								case _:
							}
						}

					case _:
				}
				break;
			}

			return switch (cur.expr) {
				case TLocal(v): v;
				case _: null;
			}
		}

		function markLocal(e:TypedExpr):Void {
			var v = unwrapToLocal(e);
			if (v != null)
				mutated.set(v.id, true);
		}

		function isRustMutRefType(t:Type):Bool {
			return switch (followType(t)) {
				case TAbstract(absRef, _): {
						var abs = absRef.get();
						abs.pack.join(".") + "." + abs.name == "rust.MutRef";
					}
				case _:
					false;
			}
		}

		function isMutatingMethod(cf:ClassField):Bool {
			for (m in cf.meta.get()) {
				if (m.name == ":rustMutating" || m.name == "rustMutating")
					return true;
			}
			return false;
		}

		function scan(e:TypedExpr, loopDepth:Int):Void {
			switch (e.expr) {
				case TWhile(cond, body, _):
					{
						// Assignments inside loops require `mut`, even if the local was declared without
						// an initializer. Rust only allows the "single assignment without mut" pattern
						// (`let x; x = v;`) when the assignment happens exactly once.
						scan(cond, loopDepth);
						scan(body, loopDepth + 1);
						return;
					}

				case TFor(_, it, body):
					{
						scan(it, loopDepth);
						scan(body, loopDepth + 1);
						return;
					}

				case TVar(v, init):
					{
						if (init != null && isRustMutRefType(v.t)) {
							// Taking a `rust.MutRef<T>` from a local requires the source binding to be `mut`.
							markLocal(init);
						}
					}

				case TBinop(OpAssign, lhs, _) | TBinop(OpAssignOp(_), lhs, _):
					{
						switch (unwrapMetaParen(lhs).expr) {
							case TLocal(v):
								if (declaredWithoutInit.exists(v.id)) {
									if (loopDepth > 0) {
										mutated.set(v.id, true);
									}
								} else {
									mutated.set(v.id, true);
								}
							case TArray(arr, _): {
									// Index assignment on Haxe arrays uses interior mutability (`hxrt::array::Array<T>`),
									// so the binding itself does not need to be `mut`.
									if (!isArrayType(arr.t)) {
										switch (arr.expr) {
											case TLocal(v):
												mutated.set(v.id, true);
											case _:
										}
									}
								}
							case _:
						}
					}

				case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement):
					{
						switch (unwrapMetaParen(inner).expr) {
							case TLocal(v):
								mutated.set(v.id, true);
							case _:
						}
					}

				case TCall(callExpr, _):
					{
						// If we call a known mutating method, require `let mut <receiver>`.
						switch (callExpr.expr) {
							case TField(obj, FInstance(_, _, cfRef)): {
									var cf = cfRef.get();
									if (cf != null && isMutatingMethod(cf)) {
										markLocal(obj);
									}
								}
							case _:
						}
					}

				case _:
			}

			TypedExprTools.iter(e, (c) -> scan(c, loopDepth));
		}

		scan(root, 0);

		/**
			Returns the maximum number of direct writes to `targetId` along any execution path in `e`.

			Why this exists:
			Summing writes across all branches is overly conservative for `var x; if (...) x = ... else x = ...`
			and incorrectly forces `let mut x;` (Rust warns with `unused_mut` because each path initializes once).

			How this is used:
			For uninitialized locals we require `mut` only if some path can write the same local more than once.
			Writes in loop contexts are treated as potentially repeated and therefore require `mut`.
		**/
		function maxWritesOnPath(e:TypedExpr, targetId:Int, loopDepth:Int):Int {
			function isWriteToTarget(x:TypedExpr):Bool {
				return switch (x.expr) {
					case TBinop(OpAssign, lhs, _) | TBinop(OpAssignOp(_), lhs, _):
						switch (unwrapMetaParen(lhs).expr) {
							case TLocal(v):
								v.id == targetId;
							case _:
								false;
						}
					case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement):
						switch (unwrapMetaParen(inner).expr) {
							case TLocal(v):
								v.id == targetId;
							case _:
								false;
						}
					case _:
						false;
				}
			}

			switch (e.expr) {
				case TBlock(exprs):
					{
						var total = 0;
						for (x in exprs)
							total += maxWritesOnPath(x, targetId, loopDepth);
						return total;
					}
				case TIf(cond, eThen, eElse):
					{
						var condWrites = maxWritesOnPath(cond, targetId, loopDepth);
						var thenWrites = maxWritesOnPath(eThen, targetId, loopDepth);
						var elseWrites = eElse != null ? maxWritesOnPath(eElse, targetId, loopDepth) : 0;
						return condWrites + Std.int(Math.max(thenWrites, elseWrites));
					}
				case TSwitch(scrutinee, cases, def):
					{
						var head = maxWritesOnPath(scrutinee, targetId, loopDepth);
						var branchMax = def != null ? maxWritesOnPath(def, targetId, loopDepth) : 0;
						for (c in cases) {
							var w = maxWritesOnPath(c.expr, targetId, loopDepth);
							if (w > branchMax)
								branchMax = w;
						}
						return head + branchMax;
					}
				case TTry(tryExpr, catches):
					{
						var base = maxWritesOnPath(tryExpr, targetId, loopDepth);
						for (c in catches) {
							var w = maxWritesOnPath(c.expr, targetId, loopDepth);
							if (w > base)
								base = w;
						}
						return base;
					}
				case TWhile(cond, body, _):
					{
						var condWrites = maxWritesOnPath(cond, targetId, loopDepth + 1);
						var bodyWrites = maxWritesOnPath(body, targetId, loopDepth + 1);
						if (condWrites > 0 || bodyWrites > 0)
							return 2;
						return 0;
					}
				case TFor(_, it, body):
					{
						var itWrites = maxWritesOnPath(it, targetId, loopDepth + 1);
						var bodyWrites = maxWritesOnPath(body, targetId, loopDepth + 1);
						if (itWrites > 0 || bodyWrites > 0)
							return 2;
						return 0;
					}
				case _:
					{
						var total = isWriteToTarget(e) ? 1 : 0;
						TypedExprTools.iter(e, (c) -> total += maxWritesOnPath(c, targetId, loopDepth));
						return total;
					}
			}
		}

		// If a local was declared without an initializer, require `mut` only when any path writes it more than once.
		for (id in declaredWithoutInit.keys()) {
			var writes = maxWritesOnPath(root, id, 0);
			if (!mutated.exists(id) && writes > 1)
				mutated.set(id, true);
		}
		return mutated;
	}

	/**
		Collects locals that are both:
		1) mutated in this function body, and
		2) captured from an outer lexical scope by nested function literals.

		Why
		- Haxe closures observe later mutations of captured locals.
		- Rust `move` closures capture by value by default, so plain local lowering would snapshot
		  values instead of sharing state.

		How
		- Reuses `collectMutatedLocals(...)` for mutation analysis.
		- Walks the typed AST with lexical scope tracking and marks locals referenced inside nested
		  function scopes that resolve to an outer declaration.
		- Marked locals are lowered through shared-cell storage (`crate::HxRef<T>`) so outer code and
		  closures see the same value.
	**/
	function collectCapturedMutatedLocals(root:TypedExpr):Map<Int, Bool> {
		var mutated = collectMutatedLocals(root);
		var captured:Map<Int, Bool> = [];
		var scopeStack:Array<Map<Int, Bool>> = [[]];

		inline function pushScope():Void {
			scopeStack.push([]);
		}

		inline function popScope():Void {
			if (scopeStack.length > 1)
				scopeStack.pop();
		}

		inline function declareLocal(v:TVar):Void {
			if (v == null)
				return;
			scopeStack[scopeStack.length - 1].set(v.id, true);
		}

		function findDeclScope(localId:Int):Int {
			var idx = scopeStack.length - 1;
			while (idx >= 0) {
				if (scopeStack[idx].exists(localId))
					return idx;
				idx--;
			}
			return -1;
		}

		inline function isCapturedFromOuter(localId:Int):Bool {
			if (scopeStack.length <= 1)
				return false;
			var declScope = findDeclScope(localId);
			return declScope >= 0 && declScope < (scopeStack.length - 1);
		}

		function scan(e:TypedExpr):Void {
			var u = unwrapMetaParen(e);
			switch (u.expr) {
				case TVar(v, init):
					{
						if (init != null)
							scan(init);
						declareLocal(v);
						return;
					}
				case TFor(v, iterable, body):
					{
						scan(iterable);
						pushScope();
						declareLocal(v);
						scan(body);
						popScope();
						return;
					}
				case TTry(tryExpr, catches):
					{
						scan(tryExpr);
						if (catches != null) {
							for (c in catches) {
								pushScope();
								if (c != null && c.v != null)
									declareLocal(c.v);
								if (c != null && c.expr != null)
									scan(c.expr);
								popScope();
							}
						}
						return;
					}
				case TFunction(fn):
					{
						pushScope();
						if (fn != null && fn.args != null) {
							for (a in fn.args) {
								if (a != null && a.v != null)
									declareLocal(a.v);
							}
						}
						if (fn != null && fn.expr != null)
							scan(fn.expr);
						popScope();
						return;
					}
				case TLocal(v):
					{
						if (v != null && mutated.exists(v.id) && isCapturedFromOuter(v.id))
							captured.set(v.id, true);
					}
				case _:
			}
			TypedExprTools.iter(u, scan);
		}

		scan(root);
		return captured;
	}

	/**
		Collects outer-scope locals referenced by a function literal.

		Why
		- `move` closures take ownership of captured values.
		- Haxe still expects captured reusable values (arrays, strings, ref-backed objects, function
		  handles, etc.) to remain usable outside the closure even when Rust needs an owned capture.

		How
		- Walks the function body with lexical-scope tracking and returns `TLocal` vars that resolve
		  outside the literal's own declarations/arguments.
	**/
	function collectFunctionLiteralCapturedOuterLocals(fn:TFunc):Array<TVar> {
		var capturedById:Map<Int, TVar> = [];
		var scopeStack:Array<Map<Int, Bool>> = [[]];

		inline function declareLocal(v:TVar):Void {
			if (v == null)
				return;
			scopeStack[scopeStack.length - 1].set(v.id, true);
		}

		function isDeclaredInCurrentFn(localId:Int):Bool {
			var idx = scopeStack.length - 1;
			while (idx >= 0) {
				if (scopeStack[idx].exists(localId))
					return true;
				idx--;
			}
			return false;
		}

		if (fn != null && fn.args != null) {
			for (a in fn.args) {
				if (a != null && a.v != null)
					declareLocal(a.v);
			}
		}

		function scan(e:TypedExpr):Void {
			var u = unwrapMetaParen(e);
			switch (u.expr) {
				case TVar(v, init):
					{
						if (init != null)
							scan(init);
						declareLocal(v);
						return;
					}
				case TFor(v, iterable, body):
					{
						scan(iterable);
						scopeStack.push([]);
						declareLocal(v);
						scan(body);
						scopeStack.pop();
						return;
					}
				case TTry(tryExpr, catches):
					{
						scan(tryExpr);
						if (catches != null) {
							for (c in catches) {
								scopeStack.push([]);
								if (c != null && c.v != null)
									declareLocal(c.v);
								if (c != null && c.expr != null)
									scan(c.expr);
								scopeStack.pop();
							}
						}
						return;
					}
				case TFunction(inner):
					{
						scopeStack.push([]);
						if (inner != null && inner.args != null) {
							for (a in inner.args) {
								if (a != null && a.v != null)
									declareLocal(a.v);
							}
						}
						if (inner != null && inner.expr != null)
							scan(inner.expr);
						scopeStack.pop();
						return;
					}
				case TLocal(v):
					{
						if (v != null && !isDeclaredInCurrentFn(v.id))
							capturedById.set(v.id, v);
					}
				case _:
			}
			TypedExprTools.iter(u, scan);
		}

		if (fn != null && fn.expr != null)
			scan(fn.expr);

		var out:Array<TVar> = [for (v in capturedById) v];
		out.sort((a, b) -> a.id < b.id ? -1 : (a.id > b.id ? 1 : 0));
		return out;
	}

	function collectLocalReadCounts(root:TypedExpr):Map<Int, Int> {
		var counts:Map<Int, Int> = [];

		function inc(v:TVar):Void {
			if (v == null)
				return;
			var prev = counts.exists(v.id) ? counts.get(v.id) : 0;
			counts.set(v.id, prev + 1);
		}

		function scan(e:TypedExpr):Void {
			switch (e.expr) {
				// Treat loop bodies as repeating by scanning them twice.
				// This prevents incorrect "move" decisions for locals used inside loops.
				case TWhile(cond, body, _):
					{
						scan(cond);
						scan(cond);
						scan(body);
						scan(body);
						return;
					}
				case TFor(_, it, expr):
					{
						scan(it);
						scan(expr);
						scan(expr);
						return;
					}
				// Writes should not count as reads: `x = expr` does not "use" `x` for move/clone analysis.
				//
				// However, compound assignments and ++/-- do read the previous value.
				case TBinop(OpAssign, lhs, rhs):
					{
						switch (unwrapMetaParen(lhs).expr) {
							case TLocal(_):
								// Skip counting the local; still scan RHS.
							case _:
								scan(lhs);
						}
						scan(rhs);
						return;
					}
				case TBinop(OpAssignOp(_), lhs, rhs):
					{
						// Reads + writes: count and scan both sides.
						scan(lhs);
						scan(rhs);
						return;
					}
				case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement):
					{
						// Reads + writes: count as a read.
						scan(inner);
						return;
					}
				case TLocal(v):
					inc(v);
				case _:
			}
			TypedExprTools.iter(e, scan);
		}

		scan(root);
		return counts;
	}

	/**
		Counts `this` reads for ownership-aware transparent-cast lowering.

		Why
		- `TThis` has no `TVar.id`, so the named-local read map cannot say whether a cast-wrapped
		  `this` is transferred on its final use or must remain available later.
		- Always cloning is safe but adds noise to ubiquitous inlined abstract last-use calls; never
		  cloning creates Rust moves in methods that reuse the receiver.

		What
		- Counts receiver reads in the current typed function body, with the same conservative doubled
		  loop accounting used for named locals.

		How
		- Walks typed children and recognizes the canonical `TConst(TThis)` node. Compilation consumes
		  each read as it emits the corresponding Rust receiver expression.
	**/
	function collectThisReadCount(root:TypedExpr):Int {
		var count = 0;

		function scan(e:TypedExpr):Void {
			switch (e.expr) {
				case TWhile(cond, body, _):
					{
						scan(cond);
						scan(cond);
						scan(body);
						scan(body);
						return;
					}
				case TFor(_, iterable, body):
					{
						scan(iterable);
						scan(body);
						scan(body);
						return;
					}
				case TConst(TThis):
					count++;
				case _:
					TypedExprTools.iter(e, scan);
			}
		}

		scan(root);
		return count;
	}

	/**
		Why
		- Constructor allocation must build a complete Rust struct before the Haxe constructor body runs.
		- For fields that the constructor body will assign, eagerly calling nested class constructors as
		  placeholder defaults can execute invalid field-record defaults and panic before the real value is stored.

		What
		- Collects direct `this.field = ...` assignments in a constructor body.
		- The constructor struct literal can then use a null/reference-safe placeholder for emitted class-reference fields.

		How
		- Walks the typed expression tree and records Haxe field names from `TField(TThis, ...)` assignment LHS nodes.
		- This is intentionally conservative about the placeholder only; the normal constructor body still performs
		  the assignment and preserves Haxe evaluation order.
	**/
	function collectThisAssignedFields(root:TypedExpr):Map<String, Bool> {
		var assigned:Map<String, Bool> = [];

		function haxeFieldNameFromAccess(fa:FieldAccess):Null<String> {
			return switch (fa) {
				case FInstance(_, _, cfRef):
					{
						var cf = cfRef.get();
						cf == null ? null : cf.getHaxeName();
					}
				case FAnon(cfRef):
					{
						var cf = cfRef.get();
						cf == null ? null : cf.getHaxeName();
					}
				case FDynamic(name):
					name;
				case _:
					null;
			}
		}

		function scan(e:TypedExpr):Void {
			switch (unwrapMetaParen(e).expr) {
				case TBinop(OpAssign, lhs, rhs):
					{
						switch (unwrapMetaParen(lhs).expr) {
							case TField(obj, fa):
								{
									switch (unwrapMetaParen(obj).expr) {
										case TConst(TThis):
											var fieldName = haxeFieldNameFromAccess(fa);
											if (fieldName != null) assigned.set(fieldName, true);
										case _:
									}
								}
							case _:
						}
						scan(lhs);
						scan(rhs);
						return;
					}
				case _:
			}
			TypedExprTools.iter(e, scan);
		}

		if (root != null)
			scan(root);
		return assigned;
	}

	/**
		Returns whether an emitted concrete class reference can use the runtime null handle as its default.

		Why
		- Haxe class instances are nullable reference values unless the source/API adds a stricter contract.
		- Generated Rust structs must still initialize every field before the constructor body runs.
		- Recursively calling a field class constructor as a placeholder can be wrong: constructors that
		  take structural fields objects may immediately read from a null/default anonymous object.

		What
		- Matches concrete, emitted, non-extern, non-interface Haxe classes represented as `HxRef<T>`.
		- Excludes interfaces/polymorphic trait objects; those have separate non-null/null-access rules.

		How
		- Constructor struct literals and generic default-value lowering use this to emit
		  `HxRef::<T>::null()` instead of `FieldClass::new(Default::default())`.
	**/
	function canUseNullClassReferenceDefault(t:Type):Bool {
		return switch (followType(t)) {
			case TInst(clsRef, _): {
					var cls = clsRef.get();
					cls != null && !cls.isInterface && !cls.isExtern && shouldEmitClass(cls, false)
					;
				}
			case _:
				false;
		}
	}

	function copyIntMap(input:Null<Map<Int, Int>>):Map<Int, Int> {
		var out:Map<Int, Int> = [];
		if (input != null) {
			for (key in input.keys()) {
				out.set(key, input.get(key));
			}
		}
		return out;
	}

	function consumeLocalRead(v:TVar):Void {
		if (v == null || currentLocalRemainingReads == null || !currentLocalRemainingReads.exists(v.id))
			return;
		var remaining = currentLocalRemainingReads.get(v.id) - 1;
		currentLocalRemainingReads.set(v.id, remaining < 0 ? 0 : remaining);
	}

	function consumeThisRead():Void {
		if (currentThisRemainingReads == null)
			return;
		currentThisRemainingReads = currentThisRemainingReads > 0 ? currentThisRemainingReads - 1 : 0;
	}

	function consumeLocalReadsLikeReadCounter(root:TypedExpr):Void {
		function scan(e:TypedExpr):Void {
			switch (e.expr) {
				case TWhile(cond, body, _):
					{
						scan(cond);
						scan(cond);
						scan(body);
						scan(body);
						return;
					}
				case TFor(_, it, expr):
					{
						scan(it);
						scan(expr);
						scan(expr);
						return;
					}
				case TBinop(OpAssign, lhs, rhs):
					{
						switch (unwrapMetaParen(lhs).expr) {
							case TLocal(_):
							case _:
								scan(lhs);
						}
						scan(rhs);
						return;
					}
				case TBinop(OpAssignOp(_), lhs, rhs):
					{
						scan(lhs);
						scan(rhs);
						return;
					}
				case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement):
					{
						scan(inner);
						return;
					}
				case TLocal(v):
					consumeLocalRead(v);
				case TConst(TThis):
					consumeThisRead();
				case _:
			}
			TypedExprTools.iter(e, scan);
		}
		scan(root);
	}

	function remainingLocalReads(localId:Int):Null<Int> {
		if (currentLocalRemainingReads == null || !currentLocalRemainingReads.exists(localId))
			return null;
		return currentLocalRemainingReads.get(localId);
	}

	inline function remainingThisReads():Null<Int> {
		return currentThisRemainingReads;
	}

	inline function isClosureCapturedReusableLocalId(localId:Int):Bool {
		return currentClosureCapturedReusableLocals != null && currentClosureCapturedReusableLocals.exists(localId);
	}

	function compileExpr(e:TypedExpr):RustExpr {
		// Target code injection: __rust__("...{0}...", arg0, ...)
		//
		// Note: injected Rust strings frequently include their own explicit borrow/clone logic.
		// When compiling placeholder arguments we suppress implicit "clone-on-local-use" so
		// patterns like `{ let __o = out.borrow_mut(); ... }` remain valid.
		var prevInj = inCodeInjectionArg;
		inCodeInjectionArg = true;
		var injected = ReflaxeTargetCodeInjection.checkTargetCodeInjectionGeneric(options.targetCodeInjectionName ?? "__rust__", e, this);
		inCodeInjectionArg = prevInj;
		if (injected != null) {
			// `checkTargetCodeInjectionGeneric` returns an empty list when there are no `{0}` placeholders.
			// In that case, the injected code is just the first (string) argument verbatim.
			if (injected.length == 0) {
				var literal:Null<String> = switch (e.expr) {
					case TCall(_, args):
						switch (args[0].expr) {
							case TConst(TString(s)): s;
							case _: null;
						}
					case _: null;
				};
				return ERaw(RustRawCode.sourceAt(literal != null ? literal : "", RawTargetCodeInjection, e.pos));
			}

			var rendered = new StringBuf();
			for (part in injected) {
				switch (part) {
					case Left(s):
						rendered.add(s);
					case Right(expr):
						rendered.add(reflaxe.rust.ast.RustASTPrinter.printExprForInjection(expr));
				}
			}
			return ERaw(RustRawCode.sourceAt(rendered.toString(), RawTargetCodeInjection, e.pos));
		}

		return switch (e.expr) {
			case TConst(c): switch (c) {
					case TInt(v): ELitInt(v);
					case TFloat(s): ELitFloat(Std.parseFloat(s));
					case TString(s): stringLiteralExpr(s);
					case TBool(b): ELitBool(b);
					case TNull:
						if (isNullOptionType(e.t, e.pos)) {
							EPath("None");
						} else if (isStringType(e.t)) {
							failMetalStringNull(e.pos);
							stringNullExpr();
						} else if (mapsToRustDynamic(e.t, e.pos)) {
							rustDynamicNullExpr();
						} else {
							// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids.
							// Use `0u32` as the null sentinel (matches `Type.resolveClass`/`resolveEnum` stubs today).
							if (isCoreClassOrEnumHandleType(e.t)) {
								return ECast(ELitInt(0), "u32");
							}

							var rt = toRustType(e.t, e.pos);
							var carrierInner = rustTypeSingleGenericArgument(rt);
							if (rustTypeIsHxRef(rt) && carrierInner != null) {
								ECall(EPath("crate::HxRef::<" + rustTypeToString(carrierInner) + ">::null"), []);
							} else if (rustTypeIsRcTraitObject(rt)) {
									// Non-null interface / polymorphic class values lower to Rust trait-object
									// handles. Trait objects have no default value, so a source `null` at this
									// boundary must become the same diverging null access used by other
									// non-nullable Rust representations.
									ECall(EPath("hxrt::exception::throw"), [
										ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString("Null Access")])])
									]);
							} else if (rustTypeIsArrayCarrier(rt) && carrierInner != null) {
								ECall(EPath("hxrt::array::Array::<" + rustTypeToString(carrierInner) + ">::null"), []);
							} else if (rustTypeIsDynRefCarrier(rt) && carrierInner != null) {
								ECall(EPath(dynRefBasePath() + "::<" + rustTypeToString(carrierInner) + ">::null"), []);
							} else switch (rt) {
								case RString:
									failMetalStringNull(e.pos);
									stringNullExpr();
								case _:
									ECall(EPath("Default::default"), []);
							}
						}
					case TThis:
						consumeThisRead();
						EPath(currentThisIdent != null ? currentThisIdent : "self_");
					case _: unsupported(e, "const");
				}

			case TArrayDecl(values): {
					// Haxe `Array<T>` literal: `[]` or `[a, b]` -> `hxrt::array::Array::<T>::new()` or `Array::from_vec(vec![...])`
					if (values.length == 0) {
						var elem = arrayElementType(e.t);
						var elemRust = toRustType(elem, e.pos);
						ECall(EPath("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::new"), []);
					} else {
						var elem = arrayElementType(e.t);
						var elemRust = toRustType(elem, e.pos);
						// Why: Haxe types each array-literal element against the literal's unified `Array<T>`
						// contract. Rust's `vec![]` requires the same explicit element type, so a source value
						// such as `7` in `Array<Null<Int>>` must become `Some(7)` before construction.
						// What: preserve Haxe reuse semantics on the source value, then pass the resulting Rust
						// expression through the ordinary typed coercion boundary for `T`.
						// How: each element remains one `vec![]` operand in source order, so evaluation still
						// occurs exactly once and left-to-right without adding a runtime helper or temporary.
						var vecValues:Array<RustExpr> = [];
						for (value in values) {
							var compiled = maybeCloneForReuseValue(compileExpr(value), value);
							// A typed local String has already crossed the compiler's String -> HxString
							// boundary at its declaration. Avoid adding an identity wrapper here; literal,
							// call, field, nullable, and other element forms still use the full coercion path.
							var sourceRustType = toRustType(value.t, value.pos);
							var materializedHxStringLocal = isLocalExpr(value)
								&& rustTypeIsNullableStringCarrier(elemRust)
								&& rustTypeIsNullableStringCarrier(sourceRustType);
							vecValues.push(materializedHxStringLocal ? compiled : coerceExprToExpected(compiled, value, elem));
						}
						var vecExpr = EMacroCall("vec", vecValues);
						ECall(EPath("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::from_vec"), [vecExpr]);
					}
				}

			case TArray(arr, index): {
					// Dynamic indexing (`obj[index]` where `obj:Dynamic`) is used by some upstream std code.
					// Route through runtime helpers so generated Rust stays type-correct.
					if (isDynamicType(followType(arr.t))) {
						var recv = compileExpr(arr);
						var idxT = followType(index.t);

						function nullAccessThrow():RustExpr {
							return ECall(EPath("hxrt::exception::throw"), [
								ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString("Null Access")])])
							]);
						}

						function nullExprForExpected(t:Type):RustExpr {
							// Core `Class<T>` / `Enum<T>` handles use `0u32` as a null sentinel.
							switch (followType(t)) {
								case TAbstract(absRef, _):
									{
										var abs = absRef.get();
										if (abs != null && abs.module == "StdTypes" && (abs.name == "Class" || abs.name == "Enum")) {
											return ECast(ELitInt(0), "u32");
										}
									}
								case _:
							}

							var rt = toRustType(t, e.pos);
							var carrierInner = rustTypeSingleGenericArgument(rt);
							if (rustTypeIsHxRef(rt) && carrierInner != null)
								return ECall(EPath("crate::HxRef::<" + rustTypeToString(carrierInner) + ">::null"), []);
							if (rustTypeIsArrayCarrier(rt) && carrierInner != null)
								return ECall(EPath("hxrt::array::Array::<" + rustTypeToString(carrierInner) + ">::null"), []);
							if (rustTypeIsDynRefCarrier(rt) && carrierInner != null)
								return ECall(EPath(dynRefBasePath() + "::<" + rustTypeToString(carrierInner) + ">::null"), []);
							return ECall(EPath("Default::default"), []);
						}

						function dynDowncastNonNull(expected:Type):RustExpr {
							if (isStringType(expected)) {
								var downStr = ECall(EField(EPath("__hx_dyn"), "downcast_ref::<String>"), []);
								var hasStr = ECall(EField(downStr, "is_some"), []);
								var strExpr = wrapRustStringExpr(ECall(EField(ECall(EField(downStr, "unwrap"), []), "clone"), []));

								var downHxStr = ECall(EField(EPath("__hx_dyn"), "downcast_ref::<hxrt::string::HxString>"), []);
								var hasHxStr = ECall(EField(downHxStr, "is_some"), []);
								var hxStrExpr = useNullableStringRepresentation() ? ECall(EField(ECall(EField(downHxStr, "unwrap"), []), "clone"),
									[]) : ECall(EField(ECall(EField(downHxStr, "unwrap"), []), "to_haxe_string"), []);

								return EIf(hasStr, strExpr, EIf(hasHxStr, hxStrExpr, nullAccessThrow()));
							}

							var tyStr = rustTypeToString(toRustType(expected, e.pos));
							return dynamicDowncastCloneExpr("__hx_dyn", tyStr);
						}

						function coerceDynToExpected(dynExpr:RustExpr):RustExpr {
							// `Dynamic` as a target type: no coercion needed.
							if (mapsToRustDynamic(e.t, e.pos))
								return dynExpr;

							var expectedIsOption = isNullOptionType(e.t, e.pos);
							if (expectedIsOption) {
								var inner = nullOptionInnerType(e.t, e.pos);
								// `Null<T>` may be erased for types that already have explicit null; in that case
								// this branch should not have been selected.
								if (inner == null)
									return dynExpr;

								var innerIsDyn = mapsToRustDynamic(inner, e.pos);
								return EBlock({
									stmts: [RLet("__hx_dyn", false, null, dynExpr)],
									tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []), EPath("None"),
										ECall(EPath("Some"), [innerIsDyn ? EPath("__hx_dyn") : dynDowncastNonNull(inner)]))
								});
							}

							var expectedRust = toRustType(e.t, e.pos);
							var isNullableRef = rustTypeIsHxRef(expectedRust)
								|| rustTypeIsArrayCarrier(expectedRust)
								|| rustTypeIsDynRefCarrier(expectedRust);
							return EBlock({
								stmts: [RLet("__hx_dyn", false, null, dynExpr)],
								tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []),
									isStringType(e.t) ? (useNullableStringRepresentation() ? stringNullExpr() : nullAccessThrow()) : (isNullableRef ? nullExprForExpected(e.t) : nullAccessThrow()),
									dynDowncastNonNull(e.t))
							});
						}

						// Upstream std sometimes uses `o[cast f]` where `f:String` is cast to `Int` by the typer.
						// In that case the expression is still *string* at runtime, so prefer string-key indexing
						// when the unwrapped index expression is a String.
						var idxUncast:TypedExpr = index;
						while (true) {
							var u = unwrapMetaParen(idxUncast);
							switch (u.expr) {
								case TCast(inner, _):
									idxUncast = inner;
									continue;
								case _:
							}
							break;
						}
						var idxUncastT = followType(idxUncast.t);

						if (isStringType(idxUncastT)) {
							var key = compileExpr(idxUncast);
							var asStr = ECall(EField(key, "as_str"), []);
							return coerceDynToExpected(ECall(EPath("hxrt::dynamic::index_get_str"), [EUnary("&", recv), asStr]));
						}

						if (TypeHelper.isInt(idxT)) {
							return coerceDynToExpected(ECall(EPath("hxrt::dynamic::index_get_i32"), [EUnary("&", recv), compileExpr(index)]));
						}
						if (isStringType(idxT)) {
							var key = compileExpr(index);
							var asStr = ECall(EField(key, "as_str"), []);
							return coerceDynToExpected(ECall(EPath("hxrt::dynamic::index_get_str"), [EUnary("&", recv), asStr]));
						}

						// Fallback: dynamic index expression.
						var idxExpr = compileExpr(index);
						// Ensure we pass an actual `Dynamic` by-value when `cast` introduced Dynamic.
						if (isDynamicType(idxT)) {
							var u = unwrapMetaParen(index);
							switch (u.expr) {
								case TCast(inner, _) if (!isDynamicType(followType(inner.t))): {
										var innerExpr = compileExpr(inner);
										innerExpr = maybeCloneForReuseValue(innerExpr, inner);
										idxExpr = ECall(EPath("hxrt::dynamic::from"), [innerExpr]);
									}
								case _:
							}
						} else if (!isDynamicType(idxT)) {
							var boxed = maybeCloneForReuseValue(idxExpr, index);
							idxExpr = ECall(EPath("hxrt::dynamic::from"), [boxed]);
						}
						return coerceDynToExpected(ECall(EPath("hxrt::dynamic::index_get_dyn"), [EUnary("&", recv), EUnary("&", idxExpr)]));
					}

					var idx = ECast(compileExpr(index), "usize");
					// If the expression is typed as `Null<T>`, represent array access as `Option<T>`.
					// This avoids Rust panics on out-of-bounds and matches Haxe’s “nullable access” typing.
					if (isNullOptionType(e.t, e.pos)) {
						var getCall = ECall(EField(compileExpr(arr), "get"), [idx]);
						// If the element type is already nullable (`Null<U>`), avoid a nested `Option<Option<U>>`
						// by flattening the out-of-bounds `None` into the inner null (`None`).
						var elem = arrayElementType(arr.t);
						if (isNullOptionType(elem, e.pos)) {
							// Why: `Array<Null<T>>.get(...)` produces `Option<Option<T>>`, while Haxe indexing
							// exposes one nullable layer and treats both a missing index and a null element as null.
							// What: collapse the outer bounds-check result with Rust's native `Option::flatten`.
							// How: keep the transformation in typed Rust AST lowering so generated crates avoid a
							// redundant `Some(v) => v, None => None` match and remain clean under current Clippy.
							return ECall(EField(getCall, "flatten"), []);
						}
						getCall;
					} else {
						ECall(EField(compileExpr(arr), "get_unchecked"), [idx]);
					}
				}

			case TLocal(v):
				consumeLocalRead(v);
				if (inlineLocalSubstitutions != null && inlineLocalSubstitutions.exists(v.name)) {
					return inlineLocalSubstitutions.get(v.name);
				}
				var localName = rustLocalRefIdent(v);
				var cellBackedLocal = isCapturedCellLocal(v) || isCapturedCellLocalName(localName);
				if (cellBackedLocal) {
					var borrowed = ECall(EField(EPath(localName), "borrow"), []);
					return isCopyType(v.t) ? EUnary("*", borrowed) : ECall(EField(borrowed, "clone"), []);
				}
				EPath(localName);

			case TBinop(op, e1, e2):
				compileBinop(op, e1, e2, e);

			case TUnop(op, postFix, expr):
				compileUnop(op, postFix, expr, e);

			case TIf(cond, eThen, eElse):
				var condExpr = coerceExprToExpected(compileExpr(cond), cond, Context.getType("Bool"));
				if (eElse == null) {
					// `if (...) expr;` in Haxe is statement-shaped; ensure the Rust `if` branches yield `()`.
					EIf(condExpr, EBlock(compileVoidBody(eThen)), null);
				} else if (isNullType(e.t)) {
					var thenExpr = coerceExprToExpected(compileBranchExpr(eThen), eThen, e.t);
					var elseExpr = coerceExprToExpected(compileBranchExpr(eElse), eElse, e.t);
					EIf(condExpr, thenExpr, elseExpr);
				} else if (mapsToRustDynamic(e.t, e.pos)) {
					var thenExpr = coerceExprToExpected(compileBranchExpr(eThen), eThen, e.t);
					var elseExpr = coerceExprToExpected(compileBranchExpr(eElse), eElse, e.t);
					EIf(condExpr, thenExpr, elseExpr);
				} else {
					var thenExpr = coerceExprToExpected(compileBranchExpr(eThen), eThen, e.t);
					var elseExpr = coerceExprToExpected(compileBranchExpr(eElse), eElse, e.t);
					EIf(condExpr, thenExpr, elseExpr);
				}

			case TBlock(exprs):
				// Why: inline expansion often wraps a representation-changing boundary in a typed
				// expression block. For example, `DynamicAccess<T>.get()` becomes a block whose final
				// `Reflect.field` call returns runtime `Dynamic`, while the block itself is `Null<T>`.
				// Compiling the tail without the block's expected type lets that raw representation leak
				// into later casts, which may then emit an invalid `Option::unwrap()` on `Dynamic`.
				//
				// What: make an expression block materialize the Rust representation promised by its own
				// typed Haxe result only when the tail and block representations actually differ.
				//
				// How: compare the typed Rust shapes plus the Dynamic boundary before selecting the existing
				// tail-coercion path. Statements and evaluation order remain unchanged, while equal HxString
				// (and other already-materialized) tails avoid redundant identity wrappers.
				var expectedTail:Null<Type> = null;
				if (exprs.length > 0) {
					var sourceTail = exprs[exprs.length - 1];
					var blockRust = toRustType(e.t, e.pos);
					var tailRust = toRustType(sourceTail.t, sourceTail.pos);
					var dynamicBoundaryDiffers = mapsToRustDynamic(e.t, e.pos) != mapsToRustDynamic(sourceTail.t, sourceTail.pos);
					if (!rustTypesEqual(blockRust, tailRust) || dynamicBoundaryDiffers)
						expectedTail = e.t;
				}
				EBlock(compileBlock(exprs, true, expectedTail));

			case TCall(callExpr, args):
				compileCall(callExpr, args, e);

			case TNew(clsRef, typeParams, args): {
					var cls = clsRef.get();
					// `new Array<T>()` must lower to `hxrt::array::Array::<T>::new()` rather than an extern `Array::new()`.
					if (isArrayType(e.t) && (args == null || args.length == 0)) {
						var elem = arrayElementType(e.t);
						var elemRust = toRustType(elem, e.pos);
						return ECall(EPath("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::new"), []);
					}
					// Why: Haxe inlines `Array.iterator()` and `Array.keyValueIterator()` to nominal
					// classes under `haxe.iterators`. Those upstream std classes are typed but intentionally
					// not emitted, while their public structural boundaries already map to `hxrt::iter::Iter`.
					// What: materialize both canonical array-backed iterators directly in the matching backend
					// representation without treating ordinary anonymous `{ key, value }` records specially.
					// How: clone the array elements once through its typed `to_vec()` primitive. Value iteration
					// consumes that vector directly; key-value iteration uses Rust's `enumerate`/`map` and the
					// existing typed anonymous-record constructor. Both retain one shared cursor across aliases.
					if (args != null && args.length == 1 && isArrayType(args[0].t)) {
						switch (haxeArrayIteratorKind(cls)) {
							case ArrayIteratorValues:
								var elem = typeParams != null && typeParams.length == 1 ? typeParams[0] : arrayElementType(args[0].t);
								var elemRust = toRustType(elem, e.pos);
								var values = ECall(EField(compileExpr(args[0]), "to_vec"), []);
								return ECall(EPath("hxrt::iter::Iter::<" + rustTypeToString(elemRust) + ">::from_vec"), [values]);
							case ArrayIteratorKeyValues:
								var values = ECall(EField(compileExpr(args[0]), "to_vec"), []);
								var intoIter = ECall(EField(values, "into_iter"), []);
								var enumerated = ECall(EField(intoIter, "enumerate"), []);
								var record = ECall(EPath("hxrt::iter::key_value"), [ECast(EPath("__hx_key"), "i32"), EPath("__hx_value")]);
								var mapped = ECall(EField(enumerated, "map"), [
									EClosure(["(__hx_key, __hx_value)"], {stmts: [], tail: record}, false)
								]);
								var records = ECall(EField(mapped, "collect::<Vec<_>>"), []);
								return ECall(EPath("hxrt::iter::Iter::<crate::HxRef<hxrt::anon::Anon>>::from_vec"), [records]);
							case null:
						}
					}
					if (cls != null && !cls.isExtern && isMainClass(cls)) {
						return unsupported(e, "new main class");
					}
					var ctorPath = (cls != null && cls.isExtern ? rustExternBasePath(cls) : null);
					var ctorBase = if (ctorPath != null) {
						ctorPath;
					} else if (cls != null && cls.isExtern) {
						cls.name;
					} else if (cls != null) {
						"crate::" + rustModulePathForClass(cls) + "::" + rustTypeNameForClass(cls);
					} else {
						"todo!()";
					}
					var ctorParams = "";
					if (typeParams != null && typeParams.length > 0) {
						var rustParams = [for (p in typeParams) rustTypeToString(toRustType(p, e.pos))];
						ctorParams = "::<" + rustParams.join(", ") + ">";
					}

					// Constructors can have optional parameters and `Null<T>` parameters.
					// Mirror `compileCall(...)` behavior: coerce provided args and fill omitted optional args.
					var ctorParamDefs:Null<Array<{name:String, t:Type, opt:Bool}>> = null;
					var ctorParamDefaultExprs:Null<Array<Null<TypedExpr>>> = null;
					if (cls != null && cls.constructor != null) {
						var cf = cls.constructor.get();
						if (cf != null) {
							switch (followType(cf.type)) {
								case TFun(params, _):
									ctorParamDefs = params;
								case _:
							}
							var fd = cf.findFuncData(cls, false);
							if (fd != null && fd.args != null) {
								ctorParamDefaultExprs = [for (a in fd.args) a.expr];
							}
						}
					}

					var outArgs:Array<RustExpr> = [];
					if (ctorParamDefs != null) {
						for (i in 0...ctorParamDefs.length) {
							var p = ctorParamDefs[i];
							if (i < args.length) {
								var a = args[i];
								var compiled = compileExpr(a);
								compiled = coerceArgForParam(compiled, a, p.t);
								outArgs.push(compiled);
							} else if (p.opt) {
								var def:Null<TypedExpr> = (ctorParamDefaultExprs != null && i < ctorParamDefaultExprs.length) ? ctorParamDefaultExprs[i] : null;
								if (def != null && defaultArgExprIsCallsiteSafe(def)) {
									var compiled = compileExpr(def);
									compiled = coerceArgForParam(compiled, def, p.t);
									outArgs.push(compiled);
									continue;
								}
								// Optional-without-default: implicit `null`.
								// Important: this is NOT always `None` because many Rust
								// representations have their own explicit null value.
								outArgs.push(nullFillExprForType(p.t, e.pos));
							} else {
								// Typechecker should prevent this; keep a deterministic fallback.
								outArgs.push(ERaw(RustRawCode.compilerAt(defaultValueForType(p.t, e.pos), RawDefaultValueFallback, e.pos)));
							}
						}
					} else {
						outArgs = [for (x in args) compileExpr(x)];
					}

					ECall(EPath(ctorBase + ctorParams + "::new"), outArgs);
				}

			case TTypeExpr(mt):
				compileTypeExpr(mt, e);

			case TField(obj, fa):
				compileField(obj, fa, e);

			case TWhile(_, _, _) | TFor(_, _, _):
				// Loops are statements in Rust; if they appear in expression position, wrap in a block.
				EBlock({stmts: [compileStmt(e)], tail: null});

			case TBreak:
				EBlock({stmts: [RBreak], tail: null});

			case TContinue:
				EBlock({stmts: [RContinue], tail: null});

			case TReturn(_):
				// `return` can surface in expression position (for example lambda bodies encoded as
				// expression trees). Lower it through statement lowering to preserve return semantics
				// and avoid unsupported-expression fallback.
				EBlock({stmts: [compileStmt(e)], tail: null});

			case TSwitch(switchExpr, cases, edef):
				compileSwitch(switchExpr, cases, edef, e.t);

			case TTry(tryExpr, catches):
				compileTry(tryExpr, catches, e);

			case TThrow(thrown):
				compileThrow(thrown, e.pos);

			case TEnumIndex(e1):
				compileEnumIndex(e1, e.pos);

			case TEnumParameter(e1, ef, index):
				compileEnumParameter(e1, ef, index, e.t, e.pos);

			case TParenthesis(e1):
				compileExpr(e1);

			case TMeta(m, e1):
				if (isAwaitMetaName(m.name)) {
					if (!currentFunctionIsAsync) {
						#if eval
						RustDiagnostic.error(RustDiagnosticId.AsyncAwaitContext,
							"`@:await` / `@:rustAwait` is only allowed inside `@:async` / `@:rustAsync` functions.", e.pos);
						#end
					}
					EAwait(compileExpr(e1));
				} else {
					compileExpr(e1);
				}

			case TFunction(fn): {
					// Lower a Haxe function literal to our runtime function representation.
					//
					// Representation:
					// - `HxDynRef<dyn Fn(...) -> ...>` (nullable, shared, thread-safe)
					//
					// Important: `HxDynRef<T>` does not currently support Rust unsized coercions
					// (`HxDynRef<{closure}>` -> `HxDynRef<dyn Fn...>`), so we first coerce the inner
					// `HxRc` to the `dyn Fn...` trait object via an explicitly typed `let`.
					// NOTE:
					// - We emit a `move` closure so the result is storable/passable in Rust-owned APIs.
					// - Before building the closure, we clone captured reusable Haxe values into fresh Rust
					//   locals. That preserves Haxe's "capturing this callback/value does not consume the
					//   original binding" contract even when the same local is captured by multiple closures.
					var baseArgNames:Array<String> = [];
					for (a in fn.args) {
						var n = (a.v != null && a.v.name != null && a.v.name.length > 0) ? a.v.name : "a";
						baseArgNames.push(n);
					}
					var capturedOuterLocals = collectFunctionLiteralCapturedOuterLocals(fn);
					var capturedCloneLocals:Array<{name:String}> = [];
					var capturedReusableLocals:Map<Int, Bool> = [];
					for (v in capturedOuterLocals) {
						var needsReusableClone = !isCopyType(v.t) && isHaxeReusableValueType(v.t);
						if (!isCapturedCellLocal(v) && !needsReusableClone)
							continue;
						capturedReusableLocals.set(v.id, true);
						capturedCloneLocals.push({
							name: rustLocalRefIdent(v)
						});
					}

					var argParts:Array<String> = [];
					var body:RustBlock = {stmts: [], tail: null};

					withFunctionContext(fn.expr, baseArgNames, fn.t, () -> {
						for (i in 0...fn.args.length) {
							var a = fn.args[i];
							var baseName = baseArgNames[i];
							var rustName = rustArgIdent(baseName);
							argParts.push(rustName + ": " + rustTypeToString(toRustType(a.v.t, e.pos)));
						}
						var prevClosureCapturedReusableLocals = currentClosureCapturedReusableLocals;
						currentClosureCapturedReusableLocals = capturedReusableLocals;
						body = compileFunctionBody(fn.expr, fn.t, true);
						currentClosureCapturedReusableLocals = prevClosureCapturedReusableLocals;
					});

					var fnTraitType = rustFunctionTraitObjectType([for (a in fn.args) toRustType(a.v.t, e.pos)],
						TypeHelper.isVoid(fn.t) ? null : toRustType(fn.t, e.pos));

					var rcTy:RustType = rustRcType(fnTraitType);
					var rcExpr:RustExpr = ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, body, true)]);
					var preStmts:Array<RustStmt> = [];
					for (captured in capturedCloneLocals) {
						preStmts.push(RLet(captured.name, false, null, ECall(EField(EPath(captured.name), "clone"), [])));
					}
					preStmts.push(RLet("__rc", false, rcTy, rcExpr));
					EBlock({
						stmts: preStmts,
						tail: ECall(EPath(dynRefBasePath() + "::new"), [EPath("__rc")])
					});
				}

			case TCast(e1, _): {
					var inner = compileExpr(e1);
					if (rustExprAlwaysDiverges(inner))
						return inner;
					var fromT = followType(e1.t);
					var toT = followType(e.t);
					var fromIsDyn = mapsToRustDynamic(fromT, e1.pos);
					var toIsDyn = mapsToRustDynamic(toT, e.pos);

					function nullAccessThrow():RustExpr {
						return ECall(EPath("hxrt::exception::throw"), [
							ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString("Null Access")])])
						]);
					}

					function dynamicToConcrete(dynExpr:RustExpr, target:Type, pos:haxe.macro.Expr.Position):RustExpr {
						var nullInner = nullOptionInnerType(target, pos);
						if (nullInner != null) {
							var innerRust = rustTypeToString(toRustType(nullInner, pos));
							var optTyStr = "Option<" + innerRust + ">";
							var stmts:Array<RustStmt> = [];
							stmts.push(RLet("__hx_dyn", false, null, dynExpr));
							// `null` dynamic -> `None`
							var isNull = ECall(EField(EPath("__hx_dyn"), "is_null"), []);
							stmts.push(RLet("__hx_opt", false, null, ECall(EField(EPath("__hx_dyn"), "downcast_ref::<" + optTyStr + ">"), [])));
							var hasOpt = ECall(EField(EPath("__hx_opt"), "is_some"), []);
							var thenExpr = ECall(EField(ECall(EField(EPath("__hx_opt"), "unwrap"), []), "clone"), []);
							var downInner = ECall(EField(EPath("__hx_dyn"), "downcast_ref::<" + innerRust + ">"), []);
							var innerRef = ECall(EField(downInner, "unwrap"), []);
							var elseExpr = ECall(EPath("Some"), [ECall(EField(innerRef, "clone"), [])]);
							return EBlock({stmts: stmts, tail: EIf(isNull, EPath("None"), EIf(hasOpt, thenExpr, elseExpr))});
						}

						var tyStr = rustTypeToString(toRustType(target, pos));
						return EBlock({
							stmts: [RLet("__hx_dyn", false, null, dynExpr)],
							tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []), nullAccessThrow(), dynamicDowncastCloneExpr("__hx_dyn", tyStr))
						});
					}

					/**
						Elides an `Option` unwrap when typed lowering has just proven the value present.

						Why / What / How
						- A typed expression block may materialize `Null<T>` as `Some(value)` immediately before
						  an explicit Haxe `Null<T> -> T` cast.
						- Emitting `Some(value).unwrap()` is correct but obscures the direct typed value and adds
						  avoidable generated-Rust noise.
						- Recognize only a literal `Some` tail, preserve every preceding block statement in order,
						  and otherwise retain the normal runtime unwrap for genuinely nullable values.
					**/
					function unwrapKnownSome(value:RustExpr):Null<RustExpr> {
						return switch (value) {
							case ECall(EPath("Some"), [present]): present;
							case EBlock(block) if (block.tail != null): {
									var present = unwrapKnownSome(block.tail);
									present == null ? null : EBlock({stmts: block.stmts, tail: present});
								}
							case _: null;
						}
					}

					// Numeric casts (`Int` <-> `Float`) must be explicit in Rust.
					if (!isNullType(e1.t)
						&& !isNullType(e.t)
						&& (TypeHelper.isInt(fromT) || TypeHelper.isFloat(fromT))
						&& (TypeHelper.isInt(toT) || TypeHelper.isFloat(toT))) {
						var target = rustTypeToString(toRustType(toT, e.pos));
						ECast(inner, target);
					} else if (rustRefKind(e.t) != null) {
						// Casts introduced by `rust.Ref<T>` / `rust.MutRef<T>` `@:from` conversions are
						// compile-time borrow markers. Do not route `Dynamic -> Ref<Dynamic>` through a
						// runtime downcast here; the call-argument coercion layer emits the actual `&`/`&mut`.
						inner;
					} else if (!fromIsDyn && toIsDyn) {
						// Casting to `Dynamic` must box the value (our `Dynamic` is a runtime wrapper).
						coerceExprToExpected(inner, e1, haxeDynamicBoundaryType());
					} else if (fromIsDyn && !toIsDyn) {
						// Casting from `Dynamic` to a concrete type: downcast through the runtime wrapper.
						dynamicToConcrete(inner, e.t, e.pos);
					} else if (isNullOptionType(e1.t, e1.pos) && isNullOptionType(e.t, e.pos)) {
						// `Option<T>` -> `Option<T>`: no-op.
						inner;
					} else if (isNullOptionType(e1.t, e1.pos) && !isNullOptionType(e.t, e.pos)) {
						// Explicit casts from `Null<T>` to `T` are treated as "assert non-null".
						// In Rust output, `Null<T>` is `Option<T>`, so unwrap unless typed block lowering
						// has just constructed a statically present `Some(value)`.
						var present = unwrapKnownSome(inner);
						present != null ? present : ECall(EField(inner, "unwrap"), []);
					} else if (!isNullOptionType(e1.t, e1.pos) && isNullOptionType(e.t, e.pos)) {
						// Explicit casts from `T` to `Null<T>` are treated as "wrap into nullability".
						ECall(EPath("Some"), [inner]);
					} else {
						inner;
					}
				}

			case TObjectDecl(fields): {
					// Anonymous objects / structural records.
					// Why: all Haxe anonymous records are shared mutable reference values, including the
					// common `{ key, value }` shape used by key-value iterators. Field names alone do not
					// authorize an owned Rust value representation.
					// What: lower every record literal through the ordinary `HxRef<Anon>` contract.
					// How: Rust-native APIs that want an owned pair must expose a nominal facade rather than
					// changing the semantics of structurally identical Haxe records.

					// General record literal -> allocate an `HxRef<hxrt::anon::Anon>`, mutate its fields,
					// then return the shared handle.
					function typedNoneForNull(t:Type, pos:haxe.macro.Expr.Position):RustExpr {
						var inner = nullOptionInnerType(t, pos);
						if (inner == null)
							return EPath("None");
						var innerRust = rustTypeToString(toRustType(inner, pos));
						return EPath("Option::<" + innerRust + ">::None");
					}

					var newAnon = ECall(EPath("hxrt::anon::Anon::new"), []);
					var newRef = ECall(EPath("crate::HxRef::new"), [newAnon]);
					// Why: a zero-field record has nothing to initialize. Taking a write guard anyway is
					// observable synchronization work and cleanup would reduce it to Clippy-invalid
					// `let _ = value.borrow_mut()`.
					// What: return the newly allocated handle directly for empty records.
					// How: populated records retain their single-borrow initialization path below; empty
					// records avoid both the guard and an otherwise redundant one-use local binding.
					if (fields == null || fields.length == 0)
						return newRef;

					var stmts:Array<RustStmt> = [];
					var objName = "__o";
					stmts.push(RLet(objName, false, null, newRef));

					var innerStmts:Array<RustStmt> = [];
					innerStmts.push(RLet("__b", true, null, ECall(EField(EPath(objName), "borrow_mut"), [])));
					for (f in fields) {
						var valueExpr = f.expr;
						var compiledVal:RustExpr;
						if (isNullConstExpr(valueExpr) && isNullOptionType(valueExpr.t, valueExpr.pos)) {
							compiledVal = typedNoneForNull(valueExpr.t, valueExpr.pos);
						} else {
							compiledVal = maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr);
						}
						innerStmts.push(RSemi(ECall(EField(EPath("__b"), "set"), [ELitString(f.name), compiledVal])));
					}
					stmts.push(RSemi(EBlock({stmts: innerStmts, tail: null})));

					return EBlock({stmts: stmts, tail: EPath(objName)});
				}

			default:
				unsupported(e, "expr");
		}
	}

	function compileTypeExpr(mt:ModuleType, fullExpr:TypedExpr):RustExpr {
		return switch (mt) {
			case TClassDecl(clsRef): {
					var cls = clsRef.get();
					if (cls == null)
						return unsupported(fullExpr, "type expr (missing class)");
					// Type expressions like `String`, `Array`, user classes, etc.
					//
					// Important: many of these are `extern` and are intentionally NOT emitted as Rust modules.
					// Use a literal stable id instead of a `crate::<mod>::__HX_TYPE_ID` path so we can refer to
					// extern/core types without requiring module emission.
					typeIdExprForClass(cls);
				}
			case TEnumDecl(enRef): {
					var en = enRef.get();
					if (en == null)
						return unsupported(fullExpr, "type expr (missing enum)");
					typeIdExprForEnum(en);
				}
			case _: unsupported(fullExpr, "type expr");
		}
	}

	function compileSwitch(switchExpr:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, edef:Null<TypedExpr>, expectedReturn:Type):RustExpr {
		// Haxe may lower enum switches to `switch (@:enumIndex e)` with int case values.
		// When detected, re-expand to a Rust `match` on the enum itself.
		var underlying = unwrapMetaParen(switchExpr);
		return switch (underlying.expr) {
			case TEnumIndex(enumExpr):
				compileEnumIndexSwitch(enumExpr, cases, edef, expectedReturn);
			case _:
				compileGenericSwitch(switchExpr, cases, edef, expectedReturn);
		}
	}

	function compileExprToBlock(e:TypedExpr, expectedReturn:Type):RustBlock {
		var allowTail = !TypeHelper.isVoid(expectedReturn);
		return switch (e.expr) {
			case TBlock(exprs):
				compileBlock(exprs, allowTail);
			case _:
				if (allowTail && !isStmtOnlyExpr(e)) {
					{stmts: [], tail: compileExpr(e)};
				} else {
					{stmts: [compileStmt(e)], tail: null};
				}
		}
	}

	function compileThrow(thrown:TypedExpr, pos:haxe.macro.Expr.Position):RustExpr {
		var compiled = compileExpr(thrown);
		var payload = mapsToRustDynamic(thrown.t, pos) ? compiled : boxThrownDynamicPayload(compiled, thrown.t, pos);
		return ECall(EPath("hxrt::exception::throw"), [payload]);
	}

	/**
		Boxes a thrown value into `hxrt::dynamic::Dynamic` while preserving subtype-dispatch metadata.

		Why
		- Exact `Dynamic.downcast::<T>()` is not enough for `catch (base:Base)` when the thrown value was
		  a concrete subclass like `Dog`.
		- The exception runtime already carries optional type-id metadata. Throw lowering needs to populate
		  that metadata so catch dispatch can check subclass chains without abandoning typed downcasts.

		What
		- Values that already map to Rust `Dynamic` bypass this helper.
		- Class/enum values get boxed with either a static type id or a runtime-provided concrete type id.
		- Reference-backed values use the `from_ref*` constructors so ownership stays aligned with the
		  existing dynamic runtime contract.

		How
		- For polymorphic/interface class values, read `__hx_type_id` from the concrete boxed value at runtime.
		- For concrete class/enum values, attach the literal emitted type id.
		- For anything outside the subtype-aware catch path, fall back to plain `hxrt::dynamic::from*`.
	**/
	function boxThrownDynamicPayload(value:RustExpr, valueType:Type, pos:haxe.macro.Expr.Position):RustExpr {
		var byRef = isArrayType(valueType) || isRcBackedType(valueType);
		var ft = followType(valueType);
		var runtimeTypeId:Null<RustExpr> = switch (ft) {
			case TInst(clsRef, _): {
					var cls = clsRef.get();
					if (cls != null && !cls.isExtern && (cls.isInterface || isPolymorphicClassType(valueType)))
						ECall(EField(EPath("__hx_box"), "__hx_type_id"), [])
					else
						null;
				}
			case _:
				null;
		};

		if (runtimeTypeId != null) {
			var boxFn = byRef ? "hxrt::dynamic::from_ref_with_type_id" : "hxrt::dynamic::from_with_type_id";
			return EBlock({
				stmts: [
					RLet("__hx_box", false, null, value),
					RLet("__hx_box_type_id", false, null, runtimeTypeId)
				],
				tail: ECall(EPath(boxFn), [EPath("__hx_box"), EPath("__hx_box_type_id")])
			});
		}

		var staticTypeId:Null<RustExpr> = switch (ft) {
			case TInst(clsRef, _): {
					var cls = clsRef.get();
					(cls != null && !cls.isExtern) ? typeIdExprForClass(cls) : null;
				}
			case TEnum(enumRef, _): {
					var en = enumRef.get();
					en != null ? typeIdExprForEnum(en) : null;
				}
			case _:
				null;
		};
		if (staticTypeId != null) {
			var typedBoxFn = byRef ? "hxrt::dynamic::from_ref_with_type_id" : "hxrt::dynamic::from_with_type_id";
			return ECall(EPath(typedBoxFn), [value, staticTypeId]);
		}

		var plainBoxFn = byRef ? "hxrt::dynamic::from_ref" : "hxrt::dynamic::from";
		return ECall(EPath(plainBoxFn), [value]);
	}

	function compileTry(tryExpr:TypedExpr, catches:Array<{v:TVar, expr:TypedExpr}>, fullExpr:TypedExpr):RustExpr {
		var expectedReturn = fullExpr.t;
		var tryBlock = compileExprToBlock(tryExpr, expectedReturn);
		var attempt = ECall(EPath("hxrt::exception::catch_unwind"), [EClosure([], tryBlock, false)]);

		var okName = "__hx_ok";
		var exName = "__hx_ex";

		var arms:Array<RustMatchArm> = [
			{pat: PTupleStruct("Ok", [PBind(okName)]), expr: EPath(okName)},
			{pat: PTupleStruct("Err", [PBind(exName)]), expr: compileCatchDispatch(exName, catches, expectedReturn)}
		];

		return EMatch(attempt, arms);
	}

	function localIdUsedInExpr(localId:Int, expr:TypedExpr):Bool {
		var used = false;
		function scan(e:TypedExpr):Void {
			if (used)
				return;
			switch (e.expr) {
				case TLocal(v) if (v.id == localId):
					used = true;
					return;
				case _:
			}
			TypedExprTools.iter(e, scan);
		}
		scan(expr);
		return used;
	}

	function compileCatchDispatch(exVarName:String, catches:Array<{v:TVar, expr:TypedExpr}>, expectedReturn:Type):RustExpr {
		if (catches.length == 0) {
			return ECall(EPath("hxrt::exception::rethrow"), [EPath(exVarName)]);
		}

		var c = catches[0];
		var rest = catches.slice(1);

		if (isDynamicType(c.v.t)) {
			var body = compileExprToBlock(c.expr, expectedReturn);
			var stmts = body.stmts.copy();
			var needsVar = localIdUsedInExpr(c.v.id, c.expr);
			if (needsVar) {
				var name = rustLocalDeclIdent(c.v);
				var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(c.v.id);
				stmts.unshift(RLet(name, mutable, toRustType(c.v.t, c.expr.pos), EPath(exVarName)));
			} else {
				// Ensure we "use" the bound exception variable to avoid an unused-variable warning.
				stmts.unshift(RLet("_", false, null, EPath(exVarName)));
			}
			return EBlock({stmts: stmts, tail: body.tail});
		}

		var expectedClass:Null<ClassType> = switch (followType(c.v.t)) {
			case TInst(clsRef, _): clsRef.get();
			case _: null;
		};
		if (expectedClass != null) {
			var subtypeAware = compileSubtypeAwareClassCatchDispatch(exVarName, c, rest, expectedReturn, expectedClass);
			if (subtypeAware != null)
				return subtypeAware;
		}

		var rustTy = toRustType(c.v.t, c.expr.pos);
		var downcast = ECall(EField(EPath(exVarName), "downcast::<" + rustTypeToString(rustTy) + ">"), []);

		var okBody = compileExprToBlock(c.expr, expectedReturn);
		var okStmts = okBody.stmts.copy();
		var needsVar = localIdUsedInExpr(c.v.id, c.expr);
		var boxedPat:RustPattern = needsVar ? PBind("__hx_box") : PWildcard;
		if (needsVar) {
			var name = rustLocalDeclIdent(c.v);
			var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(c.v.id);
			okStmts.unshift(RLet(name, mutable, rustTy, EUnary("*", EPath("__hx_box"))));
		}
		var okExpr:RustExpr = EBlock({stmts: okStmts, tail: okBody.tail});

		var errExpr = compileCatchDispatch(exVarName, rest, expectedReturn);

		return EMatch(downcast, [
			{pat: PTupleStruct("Ok", [boxedPat]), expr: okExpr},
			{pat: PTupleStruct("Err", [PBind(exVarName)]), expr: errExpr}
		]);
	}

	/**
		Upcasts a concrete `HxRef<Sub>` into the base/interface Rust type expected by a typed catch binding.

		Why
		- Subclass-aware catch dispatch first downcasts the dynamic payload to its concrete emitted class.
		- The catch variable may still be typed as a base class or interface, so the bound value must match
		  the original Haxe catch annotation instead of leaking the concrete subtype into generated Rust.

		How
		- Non-polymorphic concrete catches return the original expression unchanged.
		- Polymorphic/interface catches reuse the existing `as_arc_opt()` trait-object upcast path so the
		  generated catch variable behaves like every other base/interface-typed class reference.
	**/
	function upcastConcreteClassRefExpr(concreteExpr:RustExpr, expectedType:Type, pos:haxe.macro.Expr.Position):RustExpr {
		var expectedRustTy = toRustType(expectedType, pos);
		if (!(isInterfaceType(expectedType) || isPolymorphicClassType(expectedType)))
			return concreteExpr;

		var opt = ECall(EField(EPath("__tmp"), "as_arc_opt"), []);
		function nullAccessThrowExpr():RustExpr {
			return ECall(EPath("hxrt::exception::throw"), [
				ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString("Null Access")])])
			]);
		}
		var arms:Array<RustMatchArm> = [
			{pat: PTupleStruct("Some", [PBind("__rc")]), expr: ECall(EField(EPath("__rc"), "clone"), [])},
			{pat: PPath("None"), expr: nullAccessThrowExpr()}
		];

		return EBlock({
			stmts: [
				RLet("__tmp", false, null, concreteExpr),
				RLet("__up", false, expectedRustTy, EMatch(opt, arms))
			],
			tail: EPath("__up")
		});
	}

	/**
		Collects emitted concrete classes that can satisfy a class- or interface-typed catch.

		Why
		- The catch dispatcher needs concrete emitted classes so it can perform a typed
		  `Dynamic.downcast::<HxRef<Concrete>>()` before re-upcasting to the requested class or interface.
		- Interface declarations are traits in Rust, not concrete payload types, so they must never become
		  downcast candidates even though the subtype registry contains their stable type ids.
		- This intentionally scopes the feature to classes we actually emit and register for runtime type ids.

		How
		- Walks the emitted type-id registry, filters to concrete subtypes/implementers of the requested
		  class or interface, and skips generic classes because their erased payload shape is not yet admitted.
	**/
	function emittedCatchSubtypeCandidates(expectedClass:ClassType):Array<ClassType> {
		var out:Array<ClassType> = [];
		for (cls in getEmittedClassesForTypeIdRegistry()) {
			if (cls.isInterface)
				continue;
			if (!isClassSubtype(cls, expectedClass))
				continue;
			if (cls.params != null && cls.params.length > 0)
				continue;
			out.push(cls);
		}
		out.sort((a, b) -> compareStrings(classKey(a), classKey(b)));
		return out;
	}

	/**
		Builds subtype-aware catch dispatch for supported class and interface hierarchies.

		Why
		- Haxe typed catch follows class and interface subtype relations: both `catch (animal:Animal)` and
		  `catch (problem:Problem)` must match a concrete emitted implementation.
		- The old Rust lowering only performed exact `Dynamic.downcast::<T>()`, which dropped subclass matches
		  into the later dynamic catch path.

		How
		- Reads the optional runtime type id from the exception payload.
		- Verifies the payload is a subtype/implementer of the requested catch class or interface.
		- Tries concrete emitted subclasses in deterministic order, downcasts to the concrete `HxRef<Sub>`,
		  then upcasts back to the annotated catch type for the bound variable.
		- Falls back to the exact typed catch path when the payload lacks subtype metadata or was already
		  boxed in its polymorphic class/interface representation instead of as the concrete `HxRef`.
	**/
	function compileSubtypeAwareClassCatchDispatch(exVarName:String, c:{v:TVar, expr:TypedExpr}, rest:Array<{v:TVar, expr:TypedExpr}>, expectedReturn:Type,
			expectedClass:ClassType):Null<RustExpr> {
		var candidates = emittedCatchSubtypeCandidates(expectedClass);
		if (candidates.length == 0 || (!expectedClass.isInterface && candidates.length <= 1))
			return null;

		if (expectedClass.params != null && expectedClass.params.length > 0)
			return null;

		var rustTy = toRustType(c.v.t, c.expr.pos);
		var errExpr = compileCatchDispatch(exVarName, rest, expectedReturn);
		var exactFallback = compileExactTypedCatchDispatch(exVarName, c, rest, expectedReturn);

		var candidateArms:Array<RustMatchArm> = [];
		for (cls in candidates) {
			var concreteRustTy = rustHxRefType(rustCrateNominalType(rustModuleSegmentsForClass(cls), rustTypeNameForClass(cls)));
			if (!rustTypeIsHxRef(concreteRustTy))
				continue;

			var downcast = ECall(EField(EPath(exVarName), "downcast::<" + rustTypeToString(concreteRustTy) + ">"), []);
			var okBody = compileExprToBlock(c.expr, expectedReturn);
			var okStmts = okBody.stmts.copy();
			var needsVar = localIdUsedInExpr(c.v.id, c.expr);
			if (needsVar) {
				var name = rustLocalDeclIdent(c.v);
				var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(c.v.id);
				var concreteValue = EUnary("*", EPath("__hx_box"));
				var boundValue = upcastConcreteClassRefExpr(concreteValue, c.v.t, c.expr.pos);
				okStmts.unshift(RLet(name, mutable, rustTy, boundValue));
			}
			var okExpr:RustExpr = EBlock({stmts: okStmts, tail: okBody.tail});
			var downcastMatch = EMatch(downcast, [
				{pat: PTupleStruct("Ok", [needsVar ? PBind("__hx_box") : PWildcard]), expr: okExpr},
				{pat: PTupleStruct("Err", [PBind(exVarName)]), expr: exactFallback}
			]);

			candidateArms.push({
				pat: PWildcard,
				expr: EIf(EBinary("==", EPath("__actual_type_id"), typeIdExprForClass(cls)), downcastMatch, null)
			});
		}

		if (candidateArms.length == 0)
			return null;

		var subtypeChain:RustExpr = errExpr;
		for (idx in 0...candidateArms.length) {
			var arm = candidateArms[candidateArms.length - 1 - idx];
			subtypeChain = switch (arm.expr) {
				case EIf(cond, thenExpr, _): EIf(cond, thenExpr, subtypeChain);
				case _: subtypeChain;
			}
		}

		return EMatch(ECall(EField(EPath(exVarName), "type_id"), []), [
			{
				pat: PTupleStruct("Some", [PBind("__actual_type_id")]),
				expr: EIf(ECall(EPath("crate::__hx_is_subtype_type_id"), [EPath("__actual_type_id"), typeIdExprForClass(expectedClass)]), subtypeChain, errExpr)
			},
			{pat: PPath("None"), expr: exactFallback}
		]);
	}

	/**
		Compiles the legacy exact-type typed catch path.

		Why
		- Subclass-aware dispatch still needs a deterministic fallback when older payloads lack runtime
		  subtype metadata.
		- Keeping the exact path factored here avoids re-encoding the same binding logic in multiple
		  exception branches.
	**/
	function compileExactTypedCatchDispatch(exVarName:String, c:{v:TVar, expr:TypedExpr}, rest:Array<{v:TVar, expr:TypedExpr}>, expectedReturn:Type):RustExpr {
		var rustTy = toRustType(c.v.t, c.expr.pos);
		var downcast = ECall(EField(EPath(exVarName), "downcast::<" + rustTypeToString(rustTy) + ">"), []);

		var okBody = compileExprToBlock(c.expr, expectedReturn);
		var okStmts = okBody.stmts.copy();
		var needsVar = localIdUsedInExpr(c.v.id, c.expr);
		var boxedPat:RustPattern = needsVar ? PBind("__hx_box") : PWildcard;
		if (needsVar) {
			var name = rustLocalDeclIdent(c.v);
			var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(c.v.id);
			okStmts.unshift(RLet(name, mutable, rustTy, EUnary("*", EPath("__hx_box"))));
		}
		var okExpr:RustExpr = EBlock({stmts: okStmts, tail: okBody.tail});

		var errExpr = compileCatchDispatch(exVarName, rest, expectedReturn);

		return EMatch(downcast, [
			{pat: PTupleStruct("Ok", [boxedPat]), expr: okExpr},
			{pat: PTupleStruct("Err", [PBind(exVarName)]), expr: errExpr}
		]);
	}

	/**
		Builds a typed AST call-chain for `dyn.downcast_ref::<T>().unwrap().clone()`.

		Why
		- This path is used by `Dynamic -> T` coercions and catch-branch dispatch.
		- Emitting it as `ERaw("...")` inflated metal fallback diagnostics despite being a stable,
		  type-directed lowering path.

		How
		- Uses structured `EField`/`ECall` nodes so the compiler keeps this expression in AST form.
		  That preserves the same runtime behavior while removing avoidable raw-expression fallback.
	**/
	function dynamicDowncastCloneExpr(dynamicVarName:String, typePath:String):RustExpr {
		var downcastRef = ECall(EField(EPath(dynamicVarName), "downcast_ref::<" + typePath + ">"), []);
		var unwrapCall = ECall(EField(downcastRef, "unwrap"), []);
		return ECall(EField(unwrapCall, "clone"), []);
	}

	function compileGenericSwitch(switchExpr:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, edef:Null<TypedExpr>,
			expectedReturn:Type):RustExpr {
		function isSimpleSwitchValue(e:TypedExpr):Bool {
			var u = unwrapMetaParen(e);
			return switch (u.expr) {
				case TConst(_): true;
				case TTypeExpr(_): true;
				case TCast(e1, _): isSimpleSwitchValue(e1);
				case _: false;
			}
		}

		function compileSwitchAsIfElse():RustExpr {
			var scrutinee = compileMatchScrutinee(switchExpr);
			var stmts:Array<RustStmt> = [];
			stmts.push(RLet("__s", false, null, scrutinee));

			var elseExpr:RustExpr = edef != null ? compileSwitchArmExpr(edef, expectedReturn) : defaultSwitchArmExpr(expectedReturn, switchExpr.pos);

			// Build nested `if/else` from bottom-up so evaluation order matches switch semantics.
			for (idx in 0...cases.length) {
				var c = cases[cases.length - 1 - idx];
				if (c.values == null || c.values.length == 0)
					continue;

				var cond:Null<RustExpr> = null;
				for (v in c.values) {
					var eq = EBinary("==", EPath("__s"), compileMatchScrutinee(v));
					cond = cond == null ? eq : EBinary("||", cond, eq);
				}
				if (cond == null)
					continue;

				var thenExpr = compileSwitchArmExpr(c.expr, expectedReturn);
				elseExpr = EIf(cond, thenExpr, elseExpr);
			}

			return EBlock({stmts: stmts, tail: elseExpr});
		}

		var scrutinee = compileMatchScrutinee(switchExpr);
		function switchScrutineeUsesRustOption():Bool {
			if (isNullOptionType(switchExpr.t, switchExpr.pos))
				return true;
			return switch (unwrapMetaParen(switchExpr).expr) {
				case TLocal(v):
					isNullOptionType(v.t, switchExpr.pos);
				case _:
					false;
			}
		}
		var scrutineeIsRustOption = switchScrutineeUsesRustOption();
		var arms:Array<RustMatchArm> = [];
		var scrutineeLocalId:Null<Int> = switch (unwrapMetaParen(switchExpr).expr) {
			case TLocal(v): v.id;
			case _: null;
		};
		var scrutineeRustPathName:Null<String> = switch (unwrapMetaParen(switchExpr).expr) {
			case TLocal(v): rustLocalRefIdent(v);
			case _: null;
		};

		function enumParamKey(localId:Int, variant:String, index:Int):String {
			return localId + ":" + variant + ":" + index;
		}

		function withEnumParamBinds<T>(binds:Null<Map<String, String>>, fn:() -> T):T {
			var prev = currentEnumParamBinds;
			currentEnumParamBinds = binds;
			var out = fn();
			currentEnumParamBinds = prev;
			return out;
		}

		function aliasWholeScrutineeArmExpr(armExpr:RustExpr, pathName:String, aliasName:String):Null<RustExpr> {
			return switch (armExpr) {
				case EPath(path) if (path == pathName):
					EPath(aliasName);
				case EBlock(block):
					switch (block.tail) {
						case EPath(path) if (path == pathName):
							EPath(aliasName);
						case _:
							null;
					}
				case _:
					null;
			}
		}

		function erasePatternBindings(pattern:RustPattern):RustPattern {
			return switch (pattern) {
				case PBind(_):
					PWildcard;
				case PTupleStruct(path, fields):
					PTupleStruct(path, [for (field in fields) erasePatternBindings(field)]);
				case POr(patterns):
					POr([for (p in patterns) erasePatternBindings(p)]);
				case PAlias(name, inner):
					PAlias(name, erasePatternBindings(inner));
				case PWildcard | PPath(_) | PLitInt(_) | PLitBool(_) | PLitString(_):
					pattern;
			}
		}

		/**
			Why
			- Haxe `Null<T>` lowers to Rust `Option<T>` for types without an inline null sentinel.
			- The typed AST may still present non-null switch cases as plain inner patterns after it has
			  separated `case null` into an outer `is_none()` guard.
			- Without this wrapper, `switch (maybeValue:Null<MyEnum>) case MyCtor(...)` emits a Rust
			  `match Option<MyEnum> { MyEnum::MyCtor(...) => ... }`, which is a type mismatch.

			What
			- Wrap non-wildcard case patterns as `Some(<inner>)` when the scrutinee is represented as
			  Rust `Option<T>`.
			- Preserve wildcard/default behavior so missing/null values can still flow to the default arm
			  when Haxe did not handle them earlier.

			How
			- Distribute over OR-patterns because Rust requires each alternative to have the same outer
			  shape for an `Option<T>` scrutinee.
		**/
		function optionWrapNullableCasePattern(pattern:RustPattern):RustPattern {
			if (!scrutineeIsRustOption)
				return pattern;
			return switch (pattern) {
				case PWildcard:
					pattern;
				case POr(patterns):
					POr([for (p in patterns) optionWrapNullableCasePattern(p)]);
				case _:
					PTupleStruct("Some", [pattern]);
			}
		}

		function enumParamBindsForCase(values:Array<TypedExpr>):Null<Map<String, String>> {
			var scrutLocalId = scrutineeLocalId;
			if (scrutLocalId == null)
				return null;
			if (values == null || values.length != 1)
				return null;

			var v0 = unwrapMetaParen(values[0]);
			return switch (v0.expr) {
				case TCall(callExpr, args): switch (unwrapMetaParen(callExpr).expr) {
						case TField(_, FEnum(enumRef, ef)): {
								var argc = args != null ? args.length : 0;
								if (argc == 0)
									return null;

								var m:Map<String, String> = [];
								var any = false;
								for (i in 0...argc) {
									var a = unwrapMetaParen(args[i]);
									switch (a.expr) {
										case TLocal(local) if (local != null && local.name != "_"): {
												var bindName = argc == 1 ? "__p" : "__p" + i;
												m.set(enumParamKey(scrutLocalId, ef.name, i), bindName);
												any = true;
											}
										case _:
									}
								}
								any ? m : null;
							}
						case _:
							null;
					}
				case _:
					null;
			}
		}

		var needsFallback = false;
		for (c in cases) {
			for (v in c.values) {
				if (compilePattern(v) == null) {
					if (!isSimpleSwitchValue(v))
						return unsupported(c.expr, "switch pattern");
					needsFallback = true;
				}
			}
		}

		if (needsFallback) {
			return compileSwitchAsIfElse();
		}

		for (c in cases) {
			var patterns:Array<RustPattern> = [];
			for (v in c.values) {
				var p = compilePattern(v);
				if (p == null)
					return unsupported(c.expr, "switch pattern");
				patterns.push(optionWrapNullableCasePattern(p));
			}

			if (patterns.length == 0)
				continue;
			var pat = patterns.length == 1 ? patterns[0] : POr(patterns);
			var binds = enumParamBindsForCase(c.values);
			var armExpr = withEnumParamBinds(binds, () -> compileSwitchArmExpr(c.expr, expectedReturn));
			if (scrutineeRustPathName != null && patterns.length == 1) {
				var aliased = aliasWholeScrutineeArmExpr(armExpr, scrutineeRustPathName, "__hx_match_value");
				if (aliased != null) {
					pat = PAlias("__hx_match_value", erasePatternBindings(pat));
					armExpr = aliased;
				}
			}
			arms.push({pat: pat, expr: armExpr});
		}

		arms.push({
			pat: PWildcard,
			expr: edef != null ? compileSwitchArmExpr(edef, expectedReturn) : defaultSwitchArmExpr(expectedReturn, switchExpr.pos)
		});
		return EMatch(scrutinee, arms);
	}

	function compileEnumIndexSwitch(enumExpr:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, edef:Null<TypedExpr>,
			expectedReturn:Type):RustExpr {
		var en = enumTypeFromType(enumExpr.t);
		if (en == null)
			return unsupported(enumExpr, "enum switch");

		var scrutinee = compileMatchScrutinee(enumExpr);
		function enumSwitchScrutineeUsesRustOption():Bool {
			if (isNullOptionType(enumExpr.t, enumExpr.pos))
				return true;
			return switch (unwrapMetaParen(enumExpr).expr) {
				case TLocal(v):
					isNullOptionType(v.t, enumExpr.pos);
				case _:
					false;
			}
		}
		var scrutineeIsRustOption = enumSwitchScrutineeUsesRustOption();
		var arms:Array<RustMatchArm> = [];
		var matchedVariants = new Map<String, Bool>();
		var scrutineeRustPathName:Null<String> = switch (unwrapMetaParen(enumExpr).expr) {
			case TLocal(v): rustLocalRefIdent(v);
			case _: null;
		};

		function enumParamKey(localId:Int, variant:String, index:Int):String {
			return localId + ":" + variant + ":" + index;
		}

		function withEnumParamBinds<T>(binds:Null<Map<String, String>>, fn:() -> T):T {
			var prev = currentEnumParamBinds;
			currentEnumParamBinds = binds;
			var out = fn();
			currentEnumParamBinds = prev;
			return out;
		}

		function aliasWholeScrutineeArmExpr(armExpr:RustExpr, pathName:String, aliasName:String):Null<RustExpr> {
			return switch (armExpr) {
				case EPath(path) if (path == pathName):
					EPath(aliasName);
				case EBlock(block):
					switch (block.tail) {
						case EPath(path) if (path == pathName):
							EPath(aliasName);
						case _:
							null;
					}
				case _:
					null;
			}
		}

		function erasePatternBindings(pattern:RustPattern):RustPattern {
			return switch (pattern) {
				case PBind(_):
					PWildcard;
				case PTupleStruct(path, fields):
					PTupleStruct(path, [for (field in fields) erasePatternBindings(field)]);
				case POr(patterns):
					POr([for (p in patterns) erasePatternBindings(p)]);
				case PAlias(name, inner):
					PAlias(name, erasePatternBindings(inner));
				case PWildcard | PPath(_) | PLitInt(_) | PLitBool(_) | PLitString(_):
					pattern;
			}
		}

		/**
			Why
			- Haxe enum switches may compile through `TEnumIndex` even when the matched value is a
			  nullable local represented as Rust `Option<Enum>`.
			- Rust then requires constructor arms to match `Some(Enum::Variant(...))`, not the bare
			  `Enum::Variant(...)` pattern.

			What / How
			- Wrap concrete enum variant patterns with `Some(...)` for nullable scrutinees while leaving
			  wildcard/default arms alone.
		**/
		function optionWrapNullableEnumIndexPattern(pattern:RustPattern):RustPattern {
			if (!scrutineeIsRustOption)
				return pattern;
			return switch (pattern) {
				case PWildcard:
					pattern;
				case POr(patterns):
					POr([for (p in patterns) optionWrapNullableEnumIndexPattern(p)]);
				case _:
					PTupleStruct("Some", [pattern]);
			}
		}

		function enumParamBindsForSingleVariant(ef:EnumField):Null<Map<String, String>> {
			var scrutLocalId:Null<Int> = null;
			switch (unwrapMetaParen(enumExpr).expr) {
				case TLocal(v):
					scrutLocalId = v.id;
				case _:
			}
			if (scrutLocalId == null)
				return null;

			var argc = enumFieldArgCount(ef);
			if (argc == 0)
				return null;

			var m:Map<String, String> = [];
			for (i in 0...argc) {
				var bindName = argc == 1 ? "__p" : "__p" + i;
				m.set(enumParamKey(scrutLocalId, ef.name, i), bindName);
			}
			return m;
		}

		for (c in cases) {
			var patterns:Array<RustPattern> = [];
			var singleEf:Null<EnumField> = null;
			for (v in c.values) {
				var idx = switchValueToInt(v);
				if (idx == null)
					return unsupported(v, "enum switch value");

				var ef = enumFieldByIndex(en, idx);
				if (ef == null)
					return unsupported(v, "enum switch index");

				if (c.values.length == 1)
					singleEf = ef;
				matchedVariants.set(ef.name, true);
				var pat = enumFieldToPattern(en, ef);
				patterns.push(optionWrapNullableEnumIndexPattern(pat));
			}

			if (patterns.length == 0)
				continue;
			var pat = patterns.length == 1 ? patterns[0] : POr(patterns);
			var binds = singleEf != null ? enumParamBindsForSingleVariant(singleEf) : null;
			var armExpr = withEnumParamBinds(binds, () -> compileSwitchArmExpr(c.expr, expectedReturn));
			if (scrutineeRustPathName != null && patterns.length == 1) {
				var aliased = aliasWholeScrutineeArmExpr(armExpr, scrutineeRustPathName, "__hx_match_value");
				if (aliased != null) {
					pat = PAlias("__hx_match_value", erasePatternBindings(pat));
					armExpr = aliased;
				}
			}
			arms.push({pat: pat, expr: armExpr});
		}

		// If there's no default branch and we covered every enum constructor, the match is exhaustive.
		// In that case, omit the wildcard arm to avoid unreachable_patterns warnings and keep output idiomatic.
		var isExhaustive = true;
		for (name in en.constructs.keys()) {
			if (!matchedVariants.exists(name)) {
				isExhaustive = false;
				break;
			}
		}

		if (edef != null || !isExhaustive) {
			arms.push({
				pat: PWildcard,
				expr: edef != null ? compileSwitchArmExpr(edef, expectedReturn) : defaultSwitchArmExpr(expectedReturn, enumExpr.pos)
			});
		}
		return EMatch(scrutinee, arms);
	}

	function compileSwitchArmExpr(expr:TypedExpr, expectedReturn:Type):RustExpr {
		if (TypeHelper.isVoid(expectedReturn)) {
			return EBlock(compileVoidBody(expr));
		}

		return switch (expr.expr) {
			case TBlock(_):
				EBlock(compileFunctionBody(expr, expectedReturn));
			case TThrow(_):
				compileExpr(expr);
			case TReturn(_) | TBreak | TContinue:
				EBlock(compileVoidBody(expr));
			case _:
				coerceExprToExpected(compileExpr(expr), expr, expectedReturn);
		}
	}

	function defaultSwitchArmExpr(expectedReturn:Type, pos:haxe.macro.Expr.Position):RustExpr {
		return if (TypeHelper.isVoid(expectedReturn)) {
			EBlock({stmts: [], tail: null});
		} else {
			ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, pos));
		}
	}

	function compilePattern(value:TypedExpr):Null<RustPattern> {
		var v = unwrapMetaParen(value);
		function localPattern(local:TVar, bindName:String):RustPattern {
			return (local != null && local.name == "_") ? PWildcard : PBind(bindName);
		}
		return switch (v.expr) {
			case TConst(c): switch (c) {
					case TInt(i): PLitInt(i);
					case TBool(b): PLitBool(b);
					case TString(s): PLitString(s);
					case _: null;
				}
			case TField(_, FEnum(enumRef, ef)):
				var en = enumRef.get();
				PPath(rustEnumVariantPath(en, ef.name));
			case TCall(callExpr, args): {
					switch (callExpr.expr) {
						case TField(_, FEnum(enumRef, ef)): {
								var en = enumRef.get();
								var argc = args != null ? args.length : 0;
								var fields:Array<RustPattern> = [];
								for (i in 0...argc) {
									var a = unwrapMetaParen(args[i]);
									fields.push(switch (a.expr) {
										case TConst(c): switch (c) {
												case TInt(ii): PLitInt(ii);
												case TBool(b): PLitBool(b);
												case TString(s): PLitString(s);
												case _: PWildcard;
											}
										case TLocal(local):
											var bindName = argc == 1 ? "__p" : "__p" + i;
											localPattern(local, bindName);
										case _:
											PWildcard;
									});
								}
								PTupleStruct(rustEnumVariantPath(en, ef.name), fields);
							}
						case _: null;
					}
				}
			case _: null;
		}
	}

	function compileMatchScrutinee(e:TypedExpr):RustExpr {
		var ft = followType(e.t);
		if (isStringType(ft)) {
			return ECall(EField(compileExpr(e), "as_str"), []);
		}
		if (isCopyType(ft)) {
			return compileExpr(e);
		}
		return ECall(EField(compileExpr(e), "clone"), []);
	}

	function unwrapMetaParen(e:TypedExpr):TypedExpr {
		return switch (e.expr) {
			case TParenthesis(e1): unwrapMetaParen(e1);
			case TMeta(_, e1): unwrapMetaParen(e1);
			case _: e;
		}
	}

	function isSuperExpr(e:TypedExpr):Bool {
		return switch (unwrapMetaParen(e).expr) {
			case TConst(TSuper): true;
			case _: false;
		};
	}

	function superThunkKey(owner:ClassType, cf:ClassField):String {
		var argc = switch (followType(cf.type)) {
			case TFun(args, _): args.length;
			case _: 0;
		};
		return classKey(owner) + ":" + cf.getHaxeName() + "/" + argc;
	}

	function superThunkName(owner:ClassType, cf:ClassField):String {
		// The name must be stable, avoid collisions across base-chain methods, and be unlikely to
		// clash with user code.
		return "__hx_super_" + rustModuleNameForClass(owner) + "_" + rustMethodName(owner, cf);
	}

	function noteSuperThunk(owner:ClassType, cf:ClassField):String {
		if (currentNeededSuperThunks == null)
			currentNeededSuperThunks = [];
		var key = superThunkKey(owner, cf);
		if (!currentNeededSuperThunks.exists(key))
			currentNeededSuperThunks.set(key, {owner: owner, field: cf});
		return superThunkName(owner, cf);
	}

	function isNullConstExpr(e:TypedExpr):Bool {
		return switch (unwrapMetaParen(e).expr) {
			case TConst(TNull): true;
			case _: false;
		}
	}

	function nullInnerType(t:Type):Null<Type> {
		switch (t) {
			case TAbstract(absRef, params):
				{
					var abs = absRef.get();
					if (abs != null && abs.module == "StdTypes" && abs.name == "Null" && params.length == 1) {
						return params[0];
					}
				}
			case TLazy(f):
				return nullInnerType(f());
			case TType(typeRef, params):
				{
					var tt = typeRef.get();
					if (tt != null) {
						var under:Type = tt.type;
						if (tt.params != null && tt.params.length > 0 && params != null && params.length == tt.params.length) {
							under = TypeTools.applyTypeParameters(under, tt.params, params);
						}
						return nullInnerType(under);
					}
				}
			case _:
		}

		return null;
	}

	function isNullType(t:Type):Bool {
		return nullInnerType(t) != null;
	}

	function isCoreClassOrEnumHandleType(t:Type):Bool {
		function check(t:Type):Bool {
			return switch (t) {
				case TAbstract(absRef, _): {
						var abs = absRef.get();
						if (abs == null)
							return false;
						// Some contexts expose these as `StdTypes.Class/Enum`.
						if (abs.module == "StdTypes" && (abs.name == "Class" || abs.name == "Enum"))
							return true;
						// In other contexts they appear as `@:coreType abstract Class/Enum`.
						if (abs.meta != null && abs.meta.has(":coreType")) {
							var key = abs.pack.join(".") + "." + abs.name;
							return key == ".Class" || key == ".Enum";
						}
						false;
					}
				case TLazy(f):
					check(f());
				case TType(typeRef, params): {
						var tt = typeRef.get();
						if (tt == null)
							return false;
						var under:Type = tt.type;
						if (tt.params != null && tt.params.length > 0 && params != null && params.length == tt.params.length) {
							under = TypeTools.applyTypeParameters(under, tt.params, params);
						}
						check(under);
					}
				case _:
					false;
			}
		}
		return check(t);
	}

	function nullOptionInnerType(t:Type, pos:haxe.macro.Expr.Position):Null<Type> {
		var inner = nullInnerType(t);
		if (inner == null)
			return null;

		// Collapse nested nullability (`Null<Null<T>>`).
		var innerType:Type = inner;
		while (true) {
			var n = nullInnerType(innerType);
			if (n == null)
				break;
			innerType = n;
		}

		// Some Rust representations already have an explicit null value (no extra `Option<...>` needed).
		var innerRust = toRustType(innerType, pos);
		// `Dynamic` already carries its own null sentinel (`Dynamic::null()`).
		if (rustTypeIsDynamicCarrier(innerRust))
			return null;
		// Portable `String` uses `HxString` with an internal null sentinel.
		if (rustTypeIsNullableStringCarrier(innerRust))
			return null;

		// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
		if (isCoreClassOrEnumHandleType(innerType))
			return null;

		// Nullable interface / polymorphic class values lower to `HxDynRef<dyn Trait>`, which carries
		// its own null sentinel.
		if (traitObjectRustType(innerType, pos) != null)
			return null;

		if (rustTypeIsHxRef(innerRust) || rustTypeIsArrayCarrier(innerRust) || rustTypeIsDynRefCarrier(innerRust))
			return null;
		return innerType;
	}

	function isNullOptionType(t:Type, pos:haxe.macro.Expr.Position):Bool {
		return nullOptionInnerType(t, pos) != null;
	}

	inline function isStrictNonNullableStringType(t:Type, pos:haxe.macro.Expr.Position):Bool {
		return enforceMetalNonNullStringContract() && isStringType(t) && !isNullType(t) && !isNullOptionType(t, pos);
	}

	function maybeCloneForReuse(expr:RustExpr, valueExpr:TypedExpr):RustExpr {
		if (inCodeInjectionArg)
			return expr;
		if (isCopyType(valueExpr.t))
			return expr;
		if (isStringLiteralExpr(valueExpr) || isArrayLiteralExpr(valueExpr) || isNewExpr(valueExpr))
			return expr;
		if (isLocalExpr(valueExpr) && !isObviousTemporaryExpr(valueExpr)) {
			return ECall(EField(expr, "clone"), []);
		}
		return expr;
	}

	/**
		Returns whether a structural type is Haxe's method-shaped iterator protocol.

		Why
		- `Iterator<T>` is structurally `{ function hasNext():Bool; function next():T; }`.
		- An ordinary anonymous record may instead contain mutable function-valued fields with the same
		  names. That record is still a shared Haxe object; treating names alone as an iterator erases
		  field mutation, reference equality, and literal representation.

		What
		- Accepts only the exact two-field protocol when both fields are typed as methods.
		- Rejects `FVar` function fields even when their signatures and names resemble an iterator.

		How
		- Haxe preserves the distinction in `ClassField.kind`: `StdTypes.Iterator` exposes `FMethod`,
		  while mutable record function fields expose `FVar`.
		- Type mapping and anonymous-object lowering share this predicate so they cannot select
		  incompatible Rust representations for the same typed value.
	**/
	function isIteratorStructType(t:Type):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TAnonymous(anonRef): {
					var anon = anonRef.get();
					if (anon == null || anon.fields == null || anon.fields.length != 2)
						return false;
					var hasNext = false;
					var next = false;
					for (cf in anon.fields) {
						var isMethod = switch (cf.kind) {
							case FMethod(_): true;
							case _: false;
						};
						if (isMethod) {
							switch (cf.getHaxeName()) {
								case "hasNext": hasNext = true;
								case "next": next = true;
								case _:
							}
						}
					}
					hasNext && next
					;
				}
			case _:
				false;
		}
	}

	function isAnonObjectType(t:Type):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TAnonymous(_): !isIteratorStructType(t);
			case _:
				false;
		}
	}

	/**
		Returns whether the Haxe type is a function value.

		Why:
		- Haxe function values are reusable shared values from the source language point of view.
		- On Rust they lower to `HxDynRef<dyn Fn(...) -> ...>`, which means plain local assignment or
		  by-value passing must preserve the original binding instead of moving it away.

		What:
		- Detects `TFun` after following typedef/abstract wrappers.

		How:
		- Centralize the policy here so both reusable-value cloning and other ref-backed checks can
		  treat function values consistently.
	 */
	function isFunctionValueType(t:Type):Bool {
		return switch (followType(t)) {
			case TFun(_, _): true;
			case _: false;
		}
	}

	function isEnumValueType(t:Type):Bool {
		return switch (followType(t)) {
			case TEnum(_, _): true;
			case _: false;
		}
	}

	function isHaxeReusableValueType(t:Type):Bool {
		// Types that behave like Haxe reference values (must not be "moved" by Rust assignments).
		// - `Array<T>` is `hxrt::array::Array<T>` backed by `HxRef<Vec<T>>`.
		// - class instances / Bytes are shared `HxRef<T>` handles.
		// - `String` is immutable and reusable in Haxe (needs clone in Rust when re-used).
		// - Haxe enum values are reusable values; generated Rust enums derive `Clone`.
		// - structural `Iterator<T>` maps to `hxrt::iter::Iter<T>` with shared runtime storage.
		// - general anonymous objects map to `crate::HxRef<hxrt::anon::Anon>`.
		// - function values lower to shared `HxDynRef<dyn Fn...>` handles and must remain reusable.
		return isArrayType(t) || isHaxeArrayBackedIteratorType(t) || isHxRefValueType(t) || isRustHxRefType(t) || isStringType(t) || isIteratorStructType(t) || isAnonObjectType(t)
			|| isDynamicType(t) || isFunctionValueType(t) || isEnumValueType(t);
	}

	/**
		Detects local declarations that must clone their initializer to preserve aliasing semantics.

		Why:
		- Inline expansion can introduce bindings equivalent to `var divisor = divisor` inside nested
		  expression scopes.
		- For reference-like Haxe values, emitting `let divisor = divisor;` moves the outer Rust
		  binding and makes later reads invalid, even though Haxe expects both bindings to remain usable.

		What:
		- Matches declarations where the source expression unwraps to a local/argument whose emitted
		  Rust identifier is the same as the destination local's identifier.

		How:
		- If the initializer is a non-`Copy`, Haxe-reusable value and the source/destination Rust
		  identifiers collide, the declaration path forces a `.clone()` before any coercion.
	 */
	function needsForcedAliasCloneForLocalDecl(target:TVar, init:TypedExpr, targetName:String):Bool {
		if (target == null || init == null || isCopyType(init.t) || !isHaxeReusableValueType(init.t))
			return false;

		function unwrapToLocal(e:TypedExpr):Null<TVar> {
			var cur = unwrapMetaParen(e);
			while (true) {
				switch (cur.expr) {
					case TCast(inner, _):
						cur = unwrapMetaParen(inner);
						continue;
					case _:
				}
				break;
			}
			return switch (cur.expr) {
				case TLocal(v): v;
				case _: null;
			}
		}

		var src = unwrapToLocal(init);
		if (src == null)
			return false;

		return rustLocalRefIdent(src) == targetName;
	}

	function maybeCloneForReuseValue(expr:RustExpr, valueExpr:TypedExpr):RustExpr {
		if (inCodeInjectionArg)
			return expr;
		if (isCopyType(valueExpr.t))
			return expr;
		if (isStringLiteralExpr(valueExpr) || isArrayLiteralExpr(valueExpr) || isNewExpr(valueExpr))
			return expr;
		function isAlreadyClone(e:RustExpr):Bool {
			return switch (e) {
				case ECall(EField(_, "clone"), []): true;
				case _: false;
			}
		}
		if (isAlreadyClone(expr))
			return expr;

		function unwrapToLocalId(e:TypedExpr):Null<Int> {
			var cur = unwrapMetaParen(e);
			while (true) {
				switch (cur.expr) {
					case TCast(inner, _):
						cur = unwrapMetaParen(inner);
						continue;
					case _:
				}
				break;
			}
			return switch (cur.expr) {
				case TLocal(v): v.id;
				case _: null;
			}
		}

		var localId = unwrapToLocalId(valueExpr);
		var remaining = localId == null ? null : remainingLocalReads(localId);
		if (localId != null && isClosureCapturedReusableLocalId(localId)) {
			// `Fn` closures can be called repeatedly, so a captured reusable value cannot be
			// consumed even when this is the last syntactic read in the closure body.
		} else if (remaining != null) {
			if (remaining <= 0)
				return expr;
		} else if (localId != null && currentLocalReadCounts != null && currentLocalReadCounts.exists(localId)) {
			// If read-position tracking is unavailable, fall back to the conservative function-level count.
			var reads = currentLocalReadCounts.get(localId);
			if (reads <= 1)
				return expr;
		}

		var castWrappedThis = isCastWrappedThisExpr(valueExpr);
		if (castWrappedThis && currentClosureCapturedReusableLocals == null) {
			var remainingThis = remainingThisReads();
			if (remainingThis != null && remainingThis <= 0)
				return expr;
		}

		if ((isLocalExpr(valueExpr) || isOwnershipLocalExpr(valueExpr) || castWrappedThis)
			&& !isObviousTemporaryExpr(valueExpr)
			&& isHaxeReusableValueType(valueExpr.t)) {
			return ECall(EField(expr, "clone"), []);
		}
		return expr;
	}

	function maybeCloneForBranchReuseValue(expr:RustExpr, valueExpr:TypedExpr):RustExpr {
		if (inCodeInjectionArg)
			return expr;
		if (isCopyType(valueExpr.t))
			return expr;
		if (isStringLiteralExpr(valueExpr) || isArrayLiteralExpr(valueExpr) || isNewExpr(valueExpr))
			return expr;
		var castWrappedThis = isCastWrappedThisExpr(valueExpr);
		if ((isLocalExpr(valueExpr) || isOwnershipLocalExpr(valueExpr) || castWrappedThis)
			&& !isObviousTemporaryExpr(valueExpr)
			&& isHaxeReusableValueType(valueExpr.t)) {
			function unwrapToLocalId(e:TypedExpr):Null<Int> {
				var cur = unwrapMetaParen(e);
				while (true) {
					switch (cur.expr) {
						case TCast(inner, _):
							cur = unwrapMetaParen(inner);
							continue;
						case _:
					}
					break;
				}
				return switch (cur.expr) {
					case TLocal(v): v.id;
					case _: null;
				}
			}
			var localId = unwrapToLocalId(valueExpr);
			var remaining = localId == null ? null : remainingLocalReads(localId);
			if (localId != null && isClosureCapturedReusableLocalId(localId))
				return ECall(EField(expr, "clone"), []);
			if (remaining != null && remaining > 0)
				return ECall(EField(expr, "clone"), []);
			if (remaining == null && localId != null && currentLocalReadCounts != null && currentLocalReadCounts.exists(localId)) {
				var reads = currentLocalReadCounts.get(localId);
				if (reads > 1)
					return ECall(EField(expr, "clone"), []);
			}
			if (castWrappedThis) {
				var remainingThis = remainingThisReads();
				if (currentClosureCapturedReusableLocals != null || remainingThis == null || remainingThis > 0)
					return ECall(EField(expr, "clone"), []);
			}
		}
		return expr;
	}

	/**
		Removes typed-expression wrappers that do not change a structural source value.

		Why / What / How
		- Haxe may wrap a concrete class in metadata, parentheses, or an implicit structural cast.
		- Structural adapters still need the original expression shape to recover the emitted class.
		- Peel only those compile-time wrappers; runtime expressions remain unchanged.
	**/
	function unwrapStructuralSourceExpr(expr:TypedExpr):TypedExpr {
		var current = unwrapMetaParen(expr);
		while (true) {
			switch (current.expr) {
				case TCast(inner, _):
					current = unwrapMetaParen(inner);
					continue;
				case _:
			}
			break;
		}
		return current;
	}

	/**
		Finds the concrete emitted class behind a structural source expression.

		Why / What / How
		- The Haxe typer may report an expected anonymous type even when `new Concrete()` is the source.
		- Prefer the unwrapped constructor identity, then fall back to the followed static type.
		- Returns `null` for genuinely anonymous, abstract, or otherwise non-class values.
	**/
	function concreteStructuralSourceClass(expr:TypedExpr):Null<ClassType> {
		var source = unwrapStructuralSourceExpr(expr);
		return switch (source.expr) {
			case TNew(clsRef, _, _): clsRef.get();
			case _:
				switch (followType(source.t)) {
					case TInst(clsRef, _): clsRef.get();
					case _: null;
				}
		}
	}

	/**
		Resolves a concrete instance method across the Haxe superclass chain.

		Why / What / How
		- Structural conformance can be satisfied by an inherited method.
		- Search by the stable Haxe-facing name and accept only declared methods, never mutable fields.
	**/
	function findInstanceMethodInChain(start:ClassType, haxeName:String):Null<ClassField> {
		var current:Null<ClassType> = start;
		while (current != null) {
			for (field in current.fields.get()) {
				if (field.getHaxeName() != haxeName)
					continue;
				switch (field.kind) {
					case FMethod(_):
						return field;
					case _:
				}
			}
			current = current.superClass != null ? current.superClass.t.get() : null;
		}
		return null;
	}

	/**
		Adapts an emitted nominal Haxe iterator to the structural iterator ABI.

		Why
		- Haxe classes satisfy `Iterator<T>` structurally through `hasNext()` and `next()`.
		- The Rust backend represents structural iterators as `hxrt::iter::Iter<T>`, while an emitted
		  class instance uses `HxRef<Concrete>`.
		- Eagerly collecting the class would change iterators that read mutable source state lazily.

		What
		- Returns a callback-backed `Iter<T>` only when the expected type is the canonical method-shaped
		  iterator protocol and the concrete Rust representation differs from that ABI.
		- Leaves existing `Iter<T>` values, ordinary anonymous records, externs, and trait objects alone.

		How
		- Resolves both methods from typed class metadata, captures two handles to the same source object,
		  and emits move closures that call the normal generated methods.
		- `Iter::from_callbacks` owns the minimal runtime state required to preserve lazy evaluation and
		  shared cursor aliases; no Dynamic payload or iterator-specific native helper is introduced.
	**/
	function coerceNominalIteratorToStructural(compiled:RustExpr, valueExpr:TypedExpr, expected:Type):Null<RustExpr> {
		if (!isIteratorStructType(expected) || isIteratorStructType(valueExpr.t))
			return null;

		var expectedRust = toRustType(expected, valueExpr.pos);
		var actualRust = toRustType(valueExpr.t, valueExpr.pos);
		if (rustTypesEqual(expectedRust, actualRust))
			return null;

		var actualClass = concreteStructuralSourceClass(valueExpr);
		if (actualClass == null || actualClass.isExtern || actualClass.isInterface)
			return null;

		var hasNext = findInstanceMethodInChain(actualClass, "hasNext");
		var next = findInstanceMethodInChain(actualClass, "next");
		if (hasNext == null || next == null)
			return null;

		var expectedAnon = switch (followType(expected)) {
			case TAnonymous(anonRef): anonRef.get();
			case _: null;
		}
		if (expectedAnon == null || expectedAnon.fields == null)
			return null;

		var expectedNext:Null<ClassField> = null;
		for (field in expectedAnon.fields) {
			if (field.getHaxeName() == "next") {
				expectedNext = field;
				break;
			}
		}
		if (expectedNext == null)
			return null;

		var itemType = switch (followType(expectedNext.type)) {
			case TFun(_, result): result;
			case _: expectedNext.type;
		}
		var itemRust = rustTypeToString(toRustType(itemType, valueExpr.pos));

		function callMethod(receiver:String, field:ClassField):RustExpr {
			var path = "crate::" + rustModulePathForClass(actualClass) + "::" + rustTypeNameForClass(actualClass) + "::"
				+ rustMethodName(actualClass, field);
			return ECall(EPath(path), [EUnary("&", EUnary("*", EPath(receiver)))]);
		}

		return EBlock({
			stmts: [
				RLet("__hx_iterator_src", false, null, maybeCloneForReuseValue(compiled, valueExpr)),
				RLet("__hx_has_next_src", false, null, ECall(EField(EPath("__hx_iterator_src"), "clone"), [])),
				RLet("__hx_next_src", false, null, EPath("__hx_iterator_src"))
			],
			tail: ECall(EPath("hxrt::iter::Iter::<" + itemRust + ">::from_callbacks"), [
				EClosure([], {stmts: [], tail: callMethod("__hx_has_next_src", hasNext)}, true),
				EClosure([], {stmts: [], tail: callMethod("__hx_next_src", next)}, true)
			])
		});
	}

	function coerceExprToExpected(compiled:RustExpr, valueExpr:TypedExpr, expected:Null<Type>):RustExpr {
		if (expected == null)
			return compiled;
		if (rustExprAlwaysDiverges(compiled))
			return compiled;

		function nullAccessThrow():RustExpr {
			return ECall(EPath("hxrt::exception::throw"), [
				ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString("Null Access")])])
			]);
		}

		function isDefaultDefaultCall(expr:RustExpr):Bool {
			return switch (expr) {
				case ECall(EPath("Default::default"), []): true;
				case _: false;
			}
		}

		function isAlreadyHxStringExpr(expr:RustExpr):Bool {
			return switch (expr) {
				case ECall(EPath("hxrt::string::HxString::null"), []): true;
				case ECall(EPath("hxrt::string::HxString::from"), [_]): true;
				case _: false;
			}
		}

		function isSpecializedInheritedHxStringExpr(expr:RustExpr, sourceType:Type):Bool {
			if (currentClassType == null
				|| currentMethodOwnerType == null
				|| classKey(currentClassType) == classKey(currentMethodOwnerType))
				return false;
			var specialized = specializeAncestorType(currentClassType, currentMethodOwnerType, sourceType);
			if (TypeTools.toString(specialized) == TypeTools.toString(sourceType))
				return false;
			return switch (expr) {
				// Inherited typed locals and field reads have already been declared/lowered as HxString
				// after ancestor substitution. Literal/format/native String expressions are deliberately
				// excluded because they still need the ordinary representation bridge.
				case EPath(_): true;
				case ECall(EField(_, "clone"), []): true;
				case EBlock(block) if (block.tail != null): isSpecializedInheritedHxStringExpr(block.tail, sourceType);
				case _: false;
			}
		}

		// `Null<T>` (Option<T>) expects `Some(value)` for non-null values.
		//
		// IMPORTANT: if the inner type needs coercion (notably `HxRef<Sub>` -> `HxRc<dyn BaseTrait>`),
		// we must coerce the value to `T` first, then wrap it into `Some(...)`.
		var expectedNullInner = nullOptionInnerType(expected, valueExpr.pos);
		if (expectedNullInner != null) {
			var innerType:Type = expectedNullInner;

			if (!isNullType(valueExpr.t) && !isNullConstExpr(valueExpr)) {
				var innerCoerced = coerceExprToExpected(compiled, valueExpr, innerType);
				return ECall(EPath("Some"), [innerCoerced]);
			}
			return compiled;
		}

		var expectedRust = toRustType(expected, valueExpr.pos);
		var actualRust = toRustType(valueExpr.t, valueExpr.pos);

		var expectedIsDyn = mapsToRustDynamic(expected, valueExpr.pos);
		var actualIsDyn = mapsToRustDynamic(valueExpr.t, valueExpr.pos);

		// Haxe often types a null-checked `Null<Interface>` value as still carrying the nullable
		// trait-object wrapper (`HxDynRef<dyn Trait>`). When a callee expects the non-null
		// `HxRc<dyn Trait>` representation, unwrap once at the typed call boundary and keep the
		// callee body non-null.
		if (rustTypeIsRcTraitObject(expectedRust)
			&& rustTypeIsDynRefCarrier(actualRust)
			&& rustTypeContainsTraitObject(actualRust)) {
			return EBlock({
				stmts: [RLet("__hx_dyn_ref", false, null, maybeCloneForReuseValue(compiled, valueExpr))],
				tail: EMatch(ECall(EField(EPath("__hx_dyn_ref"), "as_arc_opt"), []), [
					{
						pat: PTupleStruct("Some", [PBind("__rc")]),
						expr: ECall(EField(EPath("__rc"), "clone"), [])
					},
					{pat: PPath("None"), expr: nullAccessThrow()}
				])
			});
		}

		// `Null<T>` (Option<T>) used where a non-null `T` is expected.
		//
		// Haxe allows this implicitly in many places (especially in upstream stdlib for "dynamic-ish"
		// targets). In Rust we must unwrap the `Option<T>`.
		//
		// Semantics: `None` is a "Null Access" error (catchable via hxrt exception machinery).
		var actualNullInner = nullOptionInnerType(valueExpr.t, valueExpr.pos);
		if (!expectedIsDyn && actualNullInner != null) {
			var innerIsCopy = isCopyType(actualNullInner);
			// Avoid moving a reusable local `Option` by cloning it first.
			var optExpr = if (!innerIsCopy && isLocalExpr(valueExpr) && !isObviousTemporaryExpr(valueExpr)) {
				ECall(EField(compiled, "clone"), []);
			} else {
				compiled;
			}

			var unwrapped = EBlock({
				stmts: [RLet("__hx_opt", false, null, optExpr)],
				tail: EMatch(innerIsCopy ? EPath("__hx_opt") : EUnary("&", EPath("__hx_opt")), [
					{pat: PTupleStruct("Some", [PBind("__v")]), expr: innerIsCopy ? EPath("__v") : ECall(EField(EPath("__v"), "clone"), [])},
					{
						pat: PPath("None"),
						expr: isStringType(expected) ? (useNullableStringRepresentation() ? stringNullExpr() : nullAccessThrow()) : nullAccessThrow()
					}
				])
			});
			if (TypeHelper.isFloat(followType(expected)) && TypeHelper.isInt(followType(actualNullInner))) {
				return ECast(unwrapped, "f64");
			}
			return unwrapped;
		}

		// Numeric widening: Haxe allows `Int` values where `Float` is expected.
		// Rust requires an explicit cast.
		if (TypeHelper.isFloat(followType(expected)) && TypeHelper.isInt(followType(valueExpr.t))) {
			return ECast(compiled, "f64");
		}

		// String representation bridge (`String` <-> `HxString`) for nullable-string mode.
		//
		// We intentionally do this after `Null<T>` unwrapping so `Option<String>` can unwrap first.
		if (rustTypeIsNullableStringCarrier(expectedRust) && !actualIsDyn) {
			// Preserve already-wrapped HxString values to avoid noisy `HxString::from(HxString::null())`
			// output while still bridging plain `String`/`&str` expressions.
			if (isDefaultDefaultCall(compiled)
				|| isAlreadyHxStringExpr(compiled)
				|| isSpecializedInheritedHxStringExpr(compiled, valueExpr.t))
				return compiled;
			return wrapRustStringExpr(compiled);
		}
		if (rustTypesEqual(expectedRust, RString) && rustTypeIsNullableStringCarrier(actualRust)) {
			return ECall(EField(compiled, "to_haxe_string"), []);
		}

		/**
			Returns a compile-time-stable type id expression for `Dynamic` boxing when available.

			Why
			- `Std.isOfType(value:Dynamic, TClass/TEnum)` needs runtime type ids when values cross dynamic boundaries.
			- For concrete class/enum values, the compiler already knows the stable target id at compile time.

			What
			- `Some(idExpr)` for non-polymorphic concrete classes and enums.
			- `null` for values without a stable compile-time id (or unsupported boundaries).
		**/
		function staticDynamicBoundaryTypeIdExpr(valueType:Type):Null<RustExpr> {
			var ft = followType(valueType);
			return switch (ft) {
				case TInst(clsRef, _): {
						var cls = clsRef.get();
						if (cls == null || cls.isExtern || cls.isInterface || isPolymorphicClassType(valueType))
							null
						else
							typeIdExprForClass(cls);
					}
				case TEnum(enumRef, _): {
						var en = enumRef.get();
						en != null ? typeIdExprForEnum(en) : null;
					}
				case _:
					null;
			}
		}

		/**
			Returns a runtime type id expression for values whose concrete class is only known at runtime.

			Why
			- Polymorphic class references (`HxRc<dyn BaseTrait>`) can point to subclass instances.
			- Interface-typed values (`HxRc<dyn IFace>`) also erase the concrete class at the static type level.
			- Dynamic boxing must preserve the *actual* runtime class id, not just the static base type.

			What
			- `Some(expr)` for polymorphic-class or interface-typed values (calls `__hx_type_id()` on the receiver).
			- `null` for non-polymorphic or unsupported value kinds.
		**/
		function runtimeDynamicBoundaryTypeIdExpr(value:RustExpr, valueType:Type):Null<RustExpr> {
			var ft = followType(valueType);
			return switch (ft) {
				case TInst(clsRef, _): {
						var cls = clsRef.get();
						if (cls != null && !cls.isExtern && (cls.isInterface || isPolymorphicClassType(valueType)))
							ECall(EField(value, "__hx_type_id"), [])
						else
							null;
					}
				case _:
					null;
			}
		}

		/**
			Boxes a typed value into `hxrt::dynamic::Dynamic`, attaching type-id metadata when available.

			Why
			- Plain `Dynamic::from(...)`/`from_ref(...)` preserves payload identity but loses class/enum subtype
			  information needed by `Std.isOfType` for dynamic values.

			What
			- Preserves existing by-ref vs by-value boxing semantics.
			- Uses `*_with_type_id(...)` constructors whenever a stable or runtime type id exists.

			How
			- Prefers runtime id (`__hx_type_id`) for polymorphic class values.
			- Falls back to compile-time literal ids for concrete class/enum values.
		**/
		function boxDynamicBoundaryValue(value:RustExpr, valueType:Type):RustExpr {
			var byRef = isArrayType(valueType) || isRcBackedType(valueType);
			var runtimeTypeId = runtimeDynamicBoundaryTypeIdExpr(EPath("__hx_box"), valueType);
			if (runtimeTypeId != null) {
				var boxFn = byRef ? "hxrt::dynamic::from_ref_with_type_id" : "hxrt::dynamic::from_with_type_id";
				return EBlock({
					stmts: [
						RLet("__hx_box", false, null, value),
						RLet("__hx_box_type_id", false, null, runtimeTypeId)
					],
					tail: ECall(EPath(boxFn), [EPath("__hx_box"), EPath("__hx_box_type_id")])
				});
			}

			var staticTypeId = staticDynamicBoundaryTypeIdExpr(valueType);
			if (staticTypeId != null) {
				var typedBoxFn = byRef ? "hxrt::dynamic::from_ref_with_type_id" : "hxrt::dynamic::from_with_type_id";
				return ECall(EPath(typedBoxFn), [value, staticTypeId]);
			}

			var plainBoxFn = byRef ? "hxrt::dynamic::from_ref" : "hxrt::dynamic::from";
			return ECall(EPath(plainBoxFn), [value]);
		}

		// Boxing to `Dynamic`.
		if (expectedIsDyn && !actualIsDyn) {
			if (isNullConstExpr(valueExpr)) {
				return rustDynamicNullExpr();
			}

			var valueNullInner = nullOptionInnerType(valueExpr.t, valueExpr.pos);
			if (valueNullInner != null) {
				// `Option<T>` -> `Dynamic`: `None` becomes `Dynamic::null()`.
				var innerType:Type = valueNullInner;

				var optExpr = maybeCloneForReuseValue(compiled, valueExpr);
				var someExpr:RustExpr;
				if (mapsToRustDynamic(innerType, valueExpr.pos)) {
					someExpr = EPath("__v");
				} else {
					someExpr = boxDynamicBoundaryValue(EPath("__v"), innerType);
				}

				return EBlock({
					stmts: [RLet("__hx_opt", false, null, optExpr)],
					tail: EMatch(EPath("__hx_opt"), [
						{pat: PTupleStruct("Some", [PBind("__v")]), expr: someExpr},
						{pat: PPath("None"), expr: rustDynamicNullExpr()}
					])
				});
			}

			var boxed = maybeCloneForReuseValue(compiled, valueExpr);
			return boxDynamicBoundaryValue(boxed, valueExpr.t);
		}

		// Downcast from `Dynamic` to a concrete expected type.
		if (!expectedIsDyn && actualIsDyn) {
			// `Dynamic -> String` must also accept `HxString` (nullable-string wrapper) when boxed.
			if (isStringType(expected)) {
				var stmts:Array<RustStmt> = [RLet("__hx_dyn", false, null, compiled)];
				var isNull = ECall(EField(EPath("__hx_dyn"), "is_null"), []);

				var downStr = ECall(EField(EPath("__hx_dyn"), "downcast_ref::<String>"), []);
				var hasStr = ECall(EField(downStr, "is_some"), []);
				var strExpr = wrapRustStringExpr(ECall(EField(ECall(EField(downStr, "unwrap"), []), "clone"), []));

				var downHxStr = ECall(EField(EPath("__hx_dyn"), "downcast_ref::<hxrt::string::HxString>"), []);
				var hasHxStr = ECall(EField(downHxStr, "is_some"), []);
				var hxStrExpr = useNullableStringRepresentation() ? ECall(EField(ECall(EField(downHxStr, "unwrap"), []), "clone"),
					[]) : ECall(EField(ECall(EField(downHxStr, "unwrap"), []), "to_haxe_string"), []);

				return EBlock({
					stmts: stmts,
					tail: EIf(isNull, useNullableStringRepresentation() ? stringNullExpr() : nullAccessThrow(),
						EIf(hasStr, strExpr, EIf(hasHxStr, hxStrExpr, nullAccessThrow())))
				});
			}

			var tyStr = rustTypeToString(toRustType(expected, valueExpr.pos));
			return EBlock({
				stmts: [RLet("__hx_dyn", false, null, compiled)],
				tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []), nullAccessThrow(), dynamicDowncastCloneExpr("__hx_dyn", tyStr))
			});
		}

		var iteratorAdapter = coerceNominalIteratorToStructural(compiled, valueExpr, expected);
		if (iteratorAdapter != null)
			return iteratorAdapter;

		// Structural typing: allow assigning class instances to anonymous record typedefs
		// by building an `hxrt::anon::Anon` adapter object.
		//
		// Upstream stdlib uses this heavily (e.g. `haxe.Unserializer.TypeResolver`).
		if (!isNullConstExpr(valueExpr) && isAnonObjectType(expected)) {
			var expectedAnon = switch (followType(expected)) {
				case TAnonymous(anonRef): anonRef.get();
				case _: null;
			};

			// Important: the Haxe typer may unify `new DefaultResolver()` to the expected typedef type,
			// so recover the concrete class from the unwrapped source expression when possible.
			var actualCls = concreteStructuralSourceClass(valueExpr);

			if (expectedAnon != null && expectedAnon.fields != null && actualCls != null) {
				var stmts:Array<RustStmt> = [];
				stmts.push(RLet("__hx_src", false, null, maybeCloneForReuseValue(compiled, valueExpr)));
				stmts.push(RLet("__hx_o", false, null, ECall(EPath("crate::HxRef::new"), [ECall(EPath("hxrt::anon::Anon::new"), [])])));
				stmts.push(RLet("__b", true, null, ECall(EField(EPath("__hx_o"), "borrow_mut"), [])));

				for (req in expectedAnon.fields) {
					var haxeName = req.getHaxeName();
					var actualMethod = findInstanceMethodInChain(actualCls, haxeName);
					if (actualMethod == null) {
						#if eval
						Context.error("Structural coercion failed: missing method `" + haxeName + "` on " + classKey(actualCls), valueExpr.pos);
						#end
						continue;
					}

					var sig = switch (TypeTools.follow(req.type)) {
						case TFun(params, ret): {params: params, ret: ret};
						case _: null;
					};
					if (sig == null) {
						#if eval
						Context.error("Structural coercion requires function fields for now: `" + haxeName + "`", valueExpr.pos);
						#end
						continue;
					}

					var recvName = "__recv";
					var recvExpr = ECall(EField(EPath("__hx_src"), "clone"), []);

					var argParts:Array<String> = [];
					var callArgs:Array<RustExpr> = [];
					for (i in 0...sig.params.length) {
						var p = sig.params[i];
						var name = "a" + i;
						argParts.push(name + ": " + rustTypeToString(toRustType(p.t, valueExpr.pos)));
						callArgs.push(EPath(name));
					}

					var call:RustExpr = if (isExternInstanceType(valueExpr.t)) {
						ECall(EField(EPath(recvName), rustExternFieldName(actualMethod)), callArgs);
					} else if (isInterfaceType(valueExpr.t) || isPolymorphicClassType(valueExpr.t)) {
						ECall(EField(EPath(recvName), rustMethodName(actualCls, actualMethod)), callArgs);
					} else {
						var modName = rustModulePathForClass(actualCls);
						var path = "crate::" + modName + "::" + rustTypeNameForClass(actualCls) + "::" + rustMethodName(actualCls, actualMethod);
						ECall(EPath(path), [EUnary("&", EUnary("*", EPath(recvName)))].concat(callArgs));
					};

					var isVoid = TypeHelper.isVoid(sig.ret);
					var body:RustBlock = isVoid ? {stmts: [RSemi(call)], tail: null} : {stmts: [], tail: call};

					var fnTraitType = rustFunctionTraitObjectType([for (p in sig.params) toRustType(p.t, valueExpr.pos)],
						TypeHelper.isVoid(sig.ret) ? null : toRustType(sig.ret, valueExpr.pos));

					var rcTy:RustType = rustRcType(fnTraitType);
					var rcExpr:RustExpr = ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, body, true)]);
					var fnVal:RustExpr = EBlock({
						stmts: [RLet(recvName, false, null, recvExpr), RLet("__rc", false, rcTy, rcExpr)],
						tail: ECall(EPath(dynRefBasePath() + "::new"), [EPath("__rc")])
					});

					var setCall = ECall(EField(EPath("__b"), "set"), [ELitString(haxeName), fnVal]);
					stmts.push(RSemi(setCall));
				}

				// Drop the borrow before returning the wrapper.
				stmts.push(RSemi(ECall(EPath("drop"), [EPath("__b")])));
				return EBlock({stmts: stmts, tail: EPath("__hx_o")});
			}
		}

		// Upcast concrete class references (`HxRef<T>`) into trait-object references when the
		// surrounding context expects an interface / polymorphic base type. Plain interface/base
		// values use `HxRc<dyn Trait>`; nullable interface/base values use `HxDynRef<dyn Trait>`.
		//
		// This primarily matters for upstream stdlib code where concrete values are returned as
		// interface types (e.g. `Sys.stdin(): Input` returning `new Stdin()`).
		var expectedNullableTraitObjectInner = nullableTraitObjectInnerType(expected, valueExpr.pos);
		var expectedTraitObjectType = expectedNullableTraitObjectInner != null ? expectedNullableTraitObjectInner : expected;
		if (!isNullConstExpr(valueExpr) && (isInterfaceType(expectedTraitObjectType) || isPolymorphicClassType(expectedTraitObjectType))) {
			function unwrapMetaParenCast(e:TypedExpr):TypedExpr {
				var cur = unwrapMetaParen(e);
				while (true) {
					switch (cur.expr) {
						case TCast(inner, _):
							cur = unwrapMetaParen(inner);
							continue;
						case _:
					}
					break;
				}
				return cur;
			}

			// `new Class()` always constructs a concrete `HxRef<Concrete>` even when the Haxe type is
			// a polymorphic base class (represented as `HxRc<dyn Trait>`).
			var actualExpr = unwrapMetaParenCast(valueExpr);
			var actualRustTy = toRustType(actualExpr.t, actualExpr.pos);
			var actualIsFreshNew = switch (actualExpr.expr) {
				case TNew(_, _, _): true;
				case _: false;
			}
			var actualIsHxRef = rustTypeIsHxRef(actualRustTy) || switch (actualExpr.expr) {
				case TNew(_, _, _): true;
				case _: false;
			};

			if (!actualIsHxRef)
				return compiled;

			var expectedRustTy = toRustType(expected, valueExpr.pos);
			var expectedIsDynRef = rustTypeIsDynRefCarrier(expectedRustTy);
			if (actualIsFreshNew) {
				// A syntactic `new Concrete()` cannot be null, so do not emit a per-site nullable
				// match/throw branch for its trait-object upcast. The unwrap documents the compiler
				// invariant while keeping non-fresh HxRef values on the null-preserving path below.
				var unwrappedFresh = ECall(EField(ECall(EField(EPath("__tmp"), "as_arc_opt"), []), "unwrap"), []);
				var freshClone = ECall(EField(unwrappedFresh, "clone"), []);
				var freshUp:RustExpr = expectedIsDynRef ? ECall(EPath(dynRefBasePath() + "::new"), [freshClone]) : freshClone;
				return EBlock({
					stmts: [
						RLet("__tmp", false, null, compiled),
						RLet("__up", false, expectedRustTy, freshUp)
					],
					tail: EPath("__up")
				});
			}

			var someExpr:RustExpr = expectedIsDynRef ? ECall(EPath(dynRefBasePath() + "::new"),
				[ECall(EField(EPath("__rc"), "clone"), [])]) : ECall(EField(EPath("__rc"), "clone"), []);
			var noneExpr:RustExpr = if (expectedIsDynRef) {
				var nullExpr = dynRefNullExprForTraitObject(expectedTraitObjectType, valueExpr.pos);
				nullExpr != null ? nullExpr : nullAccessThrow();
			} else {
				nullAccessThrow();
			}

			var opt = ECall(EField(EPath("__tmp"), "as_arc_opt"), []);
			var arms:Array<RustMatchArm> = [
				{pat: PTupleStruct("Some", [PBind("__rc")]), expr: someExpr},
				{pat: PPath("None"), expr: noneExpr}
			];

			return EBlock({
				stmts: [
					RLet("__tmp", false, null, compiled),
					RLet("__up", false, expectedRustTy, EMatch(opt, arms))
				],
				tail: EPath("__up")
			});
		}
		return compiled;
	}

	function isStringLiteralExpr(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TConst(TString(_)): true;
			case _: false;
		}
	}

	function isArrayLiteralExpr(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TArrayDecl(_): true;
			case _: false;
		}
	}

	function isNewExpr(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TNew(_, _, _): true;
			case _: false;
		}
	}

	function isLocalExpr(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TLocal(_): true;
			case TConst(TThis): true;
			case _: false;
		}
	}

	/**
		Recognizes source locals through Haxe's transparent typed casts for Rust ownership decisions.

		Why
		- Abstract access and implicit conversions frequently wrap an existing local in `TCast`.
		- The resulting Rust expression still reads the same named source binding. Treating it as a
		  fresh temporary can move a shared Haxe handle and invalidate a later legal source read.
		- Other shape checks use `isLocalExpr` deliberately and should not inherit ownership-specific
		  behavior or add unrelated clones.

		What
		- Returns true for a named local with any number of metadata, parenthesis, or cast wrappers.
		- Deliberately excludes cast-wrapped `this`: unlike `TLocal`, it has no tracked local-read
		  identity, so conservatively cloning it would add noise to every inlined abstract last-use
		  call (for example `Int64.toString()`). Direct, uncast `this` keeps the established
		  `isLocalExpr` policy at call sites.

		How
		- Peels only transparent typed wrappers. Callers still apply copy/reference/read-count policy,
		  so `this`, conversion results, calls, fields, and constructed temporaries remain non-local.
	**/
	function isOwnershipLocalExpr(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		while (true) {
			switch (u.expr) {
				case TCast(inner, _):
					u = unwrapMetaParen(inner);
					continue;
				case _:
			}
			break;
		}
		return switch (u.expr) {
			case TLocal(_): true;
			case _: false;
		}
	}

	/**
		Recognizes `this` only when a transparent typed cast hides it from `isLocalExpr`.

		Why / What / How
		- Direct `this` already follows the backend's established conservative clone policy.
		- Inlined abstracts can produce `TCast(TThis)`, which still names the same reusable receiver.
		- Require at least one actual cast wrapper, then let receiver read accounting distinguish a
		  final ownership transfer from a read that must preserve the receiver for later use.
	**/
	function isCastWrappedThisExpr(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		var sawCast = false;
		while (true) {
			switch (u.expr) {
				case TCast(inner, _):
					sawCast = true;
					u = unwrapMetaParen(inner);
					continue;
				case _:
			}
			break;
		}
		return sawCast && switch (u.expr) {
			case TConst(TThis): true;
			case _: false;
		};
	}

	function isObviousTemporaryExpr(e:TypedExpr):Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TConst(TThis): false;
			case TConst(TSuper): false;
			case TConst(_): true;
			case TArrayDecl(_): true;
			case TObjectDecl(_): true;
			case TNew(_, _, _): true;
			case _: false;
		}
	}

	function switchValueToInt(e:TypedExpr):Null<Int> {
		var v = unwrapMetaParen(e);
		return switch (v.expr) {
			case TConst(TInt(i)): i;
			case _: null;
		}
	}

	function enumKey(en:EnumType):String {
		return en.pack.join(".") + "." + en.name;
	}

	function isBuiltinEnum(en:EnumType):Bool {
		// Enums that are represented by Rust built-ins and should not be emitted as Rust enums.
		return switch (enumKey(en)) {
			case "haxe.ds.Option" | "reflaxe.std.Option" | "haxe.functional.Result" | "reflaxe.std.Result" | "rust.Option" | "rust.Result" | "haxe.io.Error": true;
			case _: false;
		}
	}

	function rustEnumVariantPath(en:EnumType, variant:String):String {
		return switch (enumKey(en)) {
			case "haxe.ds.Option" | "reflaxe.std.Option" | "rust.Option":
				"Option::" + variant;
			case "reflaxe.std.Result" | "rust.Result":
				"Result::" + variant;
			// Map Haxe's `Result.Error` to Rust's `Result.Err`.
			case "haxe.functional.Result":
				"Result::" + (variant == "Error" ? "Err" : variant);
			case "haxe.io.Error":
				"hxrt::io::Error::" + variant;
			case _:
				"crate::" + rustModulePathForEnum(en) + "::" + rustTypeNameForEnum(en) + "::" + variant;
		}
	}

	function enumTypeFromType(t:Type):Null<EnumType> {
		var ft = followType(t);
		return switch (ft) {
			case TEnum(enumRef, _): enumRef.get();
			case _: null;
		}
	}

	function enumFieldByIndex(en:EnumType, idx:Int):Null<EnumField> {
		for (name in en.constructs.keys()) {
			var ef = en.constructs.get(name);
			if (ef != null && ef.index == idx)
				return ef;
		}
		return null;
	}

	function enumFieldArgCount(ef:EnumField):Int {
		var ft = followType(ef.type);
		return switch (ft) {
			case TFun(args, _): args.length;
			case _: 0;
		}
	}

	function enumFieldToPattern(en:EnumType, ef:EnumField):RustPattern {
		var n = enumFieldArgCount(ef);
		var path = rustEnumVariantPath(en, ef.name);
		if (n == 0)
			return PPath(path);
		if (n == 1)
			return PTupleStruct(path, [PBind("__p")]);
		var fields:Array<RustPattern> = [];
		for (i in 0...n)
			fields.push(PBind("__p" + i));
		return PTupleStruct(path, fields);
	}

	function compileEnumIndex(e1:TypedExpr, pos:haxe.macro.Expr.Position):RustExpr {
		var en = enumTypeFromType(e1.t);
		if (en == null) {
			#if eval
			Context.error("TEnumIndex on non-enum type: " + Std.string(e1.t), pos);
			#end
			return ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, pos));
		}

		var scrutinee = ECall(EField(compileExpr(e1), "clone"), []);
		var arms:Array<RustMatchArm> = [];

		for (name in en.constructs.keys()) {
			var ef = en.constructs.get(name);
			if (ef == null)
				continue;
			arms.push({
				pat: enumFieldToPattern(en, ef),
				expr: ELitInt(ef.index)
			});
		}

		// This match is exhaustive because we emit an arm for every enum constructor.
		// A wildcard arm would be statically unreachable and triggers Rust `unreachable_patterns` warnings.
		return EMatch(scrutinee, arms);
	}

	function compileEnumParameter(e1:TypedExpr, ef:EnumField, index:Int, valueType:Type, pos:haxe.macro.Expr.Position):RustExpr {
		switch (unwrapMetaParen(e1).expr) {
			case TLocal(v) if (currentEnumParamBinds != null):
				{
					var key = v.id + ":" + ef.name + ":" + index;
					if (currentEnumParamBinds.exists(key)) {
						return EPath(currentEnumParamBinds.get(key));
					}
				}
			case _:
		}

		var en = enumTypeFromType(e1.t);
		if (en == null) {
			#if eval
			Context.error("TEnumParameter on non-enum type: " + Std.string(e1.t), pos);
			#end
			return ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, pos));
		}

		var argc = enumFieldArgCount(ef);
		if (index < 0 || index >= argc) {
			#if eval
			Context.error("TEnumParameter index out of bounds: " + index, pos);
			#end
			return ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, pos));
		}

		var bindName = "__p";
		var fields:Array<RustPattern> = [];
		for (i in 0...argc) {
			fields.push(i == index ? PBind(bindName) : PWildcard);
		}

		var scrutinee = ECall(EField(compileExpr(e1), "clone"), []);
		var pat = PTupleStruct(rustEnumVariantPath(en, ef.name), fields);

		var arms:Array<RustMatchArm> = [{pat: pat, expr: EPath(bindName)}];

		// If the enum only has a single constructor, this match is exhaustive and we should not emit a
		// wildcard arm (it becomes statically unreachable and triggers `unreachable_patterns` warnings).
		var ctorCount = 0;
		for (_ in en.constructs.keys())
			ctorCount++;
		if (ctorCount != 1) {
			arms.push({pat: PWildcard, expr: EMacroCall("unreachable", [])});
		}

		return EMatch(scrutinee, arms);
	}

	function compileBranchExpr(e:TypedExpr):RustExpr {
		return switch (e.expr) {
			case TBlock(_):
				EBlock(compileFunctionBody(e));
			case TReturn(_) | TBreak | TContinue | TThrow(_):
				EBlock(compileVoidBody(e));
			case _:
				// Conditional branches can move a reusable Haxe value even though later Haxe code
				// still expects the original binding to be usable. Reuse-count cloning here mirrors
				// call/local assignment lowering and prevents branch-only fallback moves.
				maybeCloneForBranchReuseValue(compileExpr(e), e);
		}
	}

	/**
		Checks whether one function type parameter disappears from every lowered Rust argument type.

		Why
		- Rust infers function generics from argument types, but a valid Haxe structural boundary may
		  deliberately erase a source parameter from its Rust representation.
		- Looking for a type-parameter name in printed Rust is ambiguous and would turn typed lowering
		  into a string heuristic.

		What
		- Returns `true` only when changing the selected Haxe type parameter between two distinct
		  concrete types leaves every lowered Rust argument type unchanged.

		How
		- Applies Haxe's declaration-owned type parameters twice, using `Int` and `String` as typed
		  probes, then compares the canonical structural Rust types. Other function parameters stay
		  symbolic, so the check isolates exactly one parameter and introduces no runtime representation.
	**/
	function isFunctionTypeParameterErasedFromRustArguments(field:ClassField, parameterIndex:Int,
		arguments:Array<{name:String, t:Type, opt:Bool}>, pos:Position):Bool {
		if (field == null
			|| field.params == null
			|| parameterIndex < 0
			|| parameterIndex >= field.params.length)
			return false;

		var intProbe = Context.getType("Int");
		var stringProbe = Context.getType("String");
		var intTypes:Array<Type> = [];
		var stringTypes:Array<Type> = [];
		for (i in 0...field.params.length) {
			intTypes.push(i == parameterIndex ? intProbe : field.params[i].t);
			stringTypes.push(i == parameterIndex ? stringProbe : field.params[i].t);
		}

		for (argument in arguments) {
			var withInt = TypeTools.applyTypeParameters(argument.t, field.params, intTypes);
			var withString = TypeTools.applyTypeParameters(argument.t, field.params, stringTypes);
			if (!rustTypesEqual(toRustType(withInt, pos), toRustType(withString, pos)))
				return false;
		}
		return true;
	}

	/**
		Recovers concrete Haxe type arguments from an already-specialized function call type.

		Why
		- Haxe resolves generic calls before backend lowering, so `callExpr.t` contains concrete types.
		- Some valid public shapes intentionally erase a source generic from their Rust representation;
		  for example, `KeyValueIterator<K,V>` yields shared anonymous records and therefore lowers to
		  `Iter<HxRef<Anon>>` without mentioning `K` or `V`.
		- Rust cannot infer a function type parameter that disappeared from every argument type.

		What
		- Matches the function declaration type against the specialized call-expression type and returns
		  one concrete type for every declared function type parameter.

		How
		- Instantiates the declaration with fresh Haxe compiler monomorphs and asks Haxe's own typed
		  unifier to match the specialized call expression. Unresolved or incompatible inference fails
		  closed so ordinary Rust inference remains the fallback; no parallel type matcher, runtime type
		  carrier, or generated phantom value is introduced.
	**/
	function inferAppliedFunctionTypeArguments(field:ClassField, appliedType:Type):Null<Array<Type>> {
		if (field == null || field.params == null || field.params.length == 0)
			return [];

		var monomorphs:Array<Type> = [for (_ in field.params) Context.makeMonomorph()];
		var declaration = TypeTools.applyTypeParameters(field.type, field.params, monomorphs);
		if (!Context.unify(declaration, appliedType))
			return null;

		var result:Array<Type> = [];
		for (monomorph in monomorphs) {
			var resolved = TypeTools.follow(monomorph);
			switch (resolved) {
				case TMono(ref) if (ref.get() == null):
				return null;
				case _:
					result.push(resolved);
			}
		}
		return result;
	}

	function compileCall(callExpr:TypedExpr, args:Array<TypedExpr>, fullExpr:TypedExpr):RustExpr {
		function compilePositionalArgsFor(params:Null<Array<{name:String, t:Type, opt:Bool}>>):Array<RustExpr> {
			var out:Array<RustExpr> = [];
			var effectiveParams = params;

			// Apply class type parameters for instance methods so generic params like `Array<T>.push(x:T)`
			// get specialized to `Array<Dynamic>.push(x:Dynamic)` instead of leaking a free `T`.
			if (effectiveParams != null) {
				switch (callExpr.expr) {
					case TField(obj, FInstance(clsRef, _, _)):
						{
							var owner = clsRef.get();
							if (owner != null && owner.params != null && owner.params.length > 0) {
								switch (followType(obj.t)) {
									case TInst(cls2Ref, actualParams): {
											var cls2 = cls2Ref.get();
											if (cls2 != null
												&& classKey(cls2) == classKey(owner)
												&& actualParams.length == owner.params.length) {
												effectiveParams = [];
												for (p in params) {
													effectiveParams.push({
														name: p.name,
														opt: p.opt,
														t: TypeTools.applyTypeParameters(p.t, owner.params, actualParams)
													});
												}
											}
										}
									case _:
								}
							}
						}
					case _:
				}
			}

			for (i in 0...args.length) {
				var arg = args[i];
				var compiled = compileExpr(arg);
				if (effectiveParams != null && i < effectiveParams.length) {
					compiled = coerceArgForParam(compiled, arg, effectiveParams[i].t);
				}
				out.push(compiled);
			}

			// Fill omitted optional args (`null` => `None` for `Null<T>`).
			if (effectiveParams != null && args.length < effectiveParams.length) {
				for (i in args.length...effectiveParams.length) {
					if (!effectiveParams[i].opt)
						break;
					out.push(nullFillExprForType(effectiveParams[i].t, fullExpr.pos));
				}
			}

			return out;
		}

		function explicitNullExprForExpected(t:Type, pos:haxe.macro.Expr.Position):Null<RustExpr> {
			var rust = toRustType(t, pos);
			if (rustTypeIsDynamicCarrier(rust))
				return rustDynamicNullExpr();
			if (isCoreClassOrEnumHandleType(t))
				return ECast(ELitInt(0), "u32");
			if (rustTypeIsHxRef(rust))
				return ECall(EPath("crate::HxRef::null"), []);
			if (rustTypeIsArrayCarrier(rust))
				return ECall(EPath("hxrt::array::Array::null"), []);
			if (rustTypeIsDynRefCarrier(rust))
				return ECall(EPath(dynRefBasePath() + "::null"), []);
			return null;
		}

		function applyReceiverTypeParameters(ret:Type, owner:Null<ClassType>, receiverType:Type):Type {
			if (owner != null && owner.params != null && owner.params.length > 0) {
				switch (followType(receiverType)) {
					case TInst(_, actualParams) if (actualParams != null && actualParams.length == owner.params.length):
						return TypeTools.applyTypeParameters(ret, owner.params, actualParams);
					case _:
				}
			}
			return ret;
		}

		function coerceGenericNullReturnToExplicitNull(call:RustExpr, declaredReturn:Null<Type>, owner:Null<ClassType>, receiverType:Type):RustExpr {
			// Generic `Null<T>` return values:
			//
			// Some upstream/std helpers are declared as returning `Null<T>` where `T` is a type
			// parameter (e.g. `Array<T>.shift(): Null<T>` or `Deque<T>.pop(): Null<T>`). In Rust we
			// must represent that as `Option<T>` because `T` can be a non-nullable value type (like
			// `i32`).
			//
			// However, when the generic type parameter is instantiated to a Rust type that already has
			// an explicit null sentinel (notably `HxRef<T>`, `Array<T>`, and `HxDynRef<dyn Fn...>`),
			// Haxe will often treat `Null<T>` as just `T` and the typed call expression will be `T`.
			// In that case we must coerce `Option<T>` -> `T` by mapping `None` to the type's explicit
			// null value. This must apply to both generated Haxe methods and direct extern methods.
			if (mapsToRustDynamic(fullExpr.t, fullExpr.pos))
				return call;
			if (declaredReturn == null || nullOptionInnerType(declaredReturn, fullExpr.pos) == null)
				return call;

			var retApplied = applyReceiverTypeParameters(declaredReturn, owner, receiverType);
			if (nullOptionInnerType(retApplied, fullExpr.pos) != null)
				return call;

			var nullExpr = explicitNullExprForExpected(fullExpr.t, fullExpr.pos);
			if (nullExpr == null)
				return call;

			return EBlock({
				stmts: [RLet("__hx_opt", false, null, call)],
				tail: EMatch(EPath("__hx_opt"), [
					{pat: PTupleStruct("Some", [PBind("__v")]), expr: EPath("__v")},
					{pat: PPath("None"), expr: nullExpr}
				])
			});
		}

		function funParamDefsForCall(t:Type):Null<Array<{name:String, t:Type, opt:Bool}>> {
			return switch (t) {
				case TLazy(f):
					funParamDefsForCall(f());
				case TType(typeRef, params): {
						var tt = typeRef.get();
						if (tt != null) {
							var under:Type = tt.type;
							if (tt.params != null && tt.params.length > 0 && params != null && params.length == tt.params.length) {
								under = TypeTools.applyTypeParameters(under, tt.params, params);
							}
							funParamDefsForCall(under);
						} else {
							null;
						}
					}
				case TFun(params, _):
					params;
				case _:
					null;
			};
		}

		// Special-case: super(...) in constructors.
		// Current behavior: support `super()` as a no-op (base init semantics will be expanded later).
		switch (callExpr.expr) {
			case TConst(TSuper):
				if (args.length > 0)
					return unsupported(fullExpr, "super(args)");
				return EBlock({stmts: [], tail: null});
			case _:
		}

		// Special-case: rust.async.Async.*
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (isRustAsyncClass(cls)) {
					ensureAsyncAllowed(fullExpr.pos);
					var fieldName = field.getHaxeName();
					switch (fieldName) {
						case "await": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.await args");
								if (!currentFunctionIsAsync) {
									#if eval
									RustDiagnostic.error(RustDiagnosticId.AsyncAwaitContext,
										"`Async.await(...)` / `@:await` is only allowed inside `@:async` / `@:rustAsync` functions.", fullExpr.pos);
									#end
								}
								return EAwait(compileExpr(args[0]));
							}
						case "blockOn": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.blockOn args");
								if (currentFunctionIsAsync) {
									#if eval
									RustDiagnostic.error(RustDiagnosticId.AsyncBlockOnContext,
										"`Async.blockOn(...)` is not allowed inside async functions. Use `await` instead.", fullExpr.pos);
									#end
								}
								return ECall(EPath("hxrt::async_::block_on"), [compileExpr(args[0])]);
							}
						case "ready": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.ready args");
								var v = maybeCloneForReuseValue(compileExpr(args[0]), args[0]);
								return ECall(EPath("hxrt::async_::ready"), [v]);
							}
						case "sleepMs": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.sleepMs args");
								return ECall(EPath("hxrt::async_::sleep_ms"), [compileExpr(args[0])]);
							}
						case "sleep": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.sleep args");
								return ECall(EPath("hxrt::async_::sleep"), [compileExpr(args[0])]);
							}
						case "await_haxe": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.await args");
								if (!currentFunctionIsAsync) {
									#if eval
									RustDiagnostic.error(RustDiagnosticId.AsyncAwaitContext,
										"`Async.await(...)` / `@:await` is only allowed inside `@:async` / `@:rustAsync` functions.", fullExpr.pos);
									#end
								}
								return EAwait(compileExpr(args[0]));
							}
						case "block_on": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.blockOn args");
								if (currentFunctionIsAsync) {
									#if eval
									RustDiagnostic.error(RustDiagnosticId.AsyncBlockOnContext,
										"`Async.blockOn(...)` is not allowed inside async functions. Use `await` instead.", fullExpr.pos);
									#end
								}
								return ECall(EPath("hxrt::async_::block_on"), [compileExpr(args[0])]);
							}
						case "sleep_ms": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.sleepMs args");
								return ECall(EPath("hxrt::async_::sleep_ms"), [compileExpr(args[0])]);
							}
						case _:
					}
				}
			case _:
		}

		// Special-case: rust.net.SocketAddr pure constructors.
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (isRustNetSocketAddrClass(cls)) {
					switch (field.getHaxeName()) {
						case "localhost":
							if (args.length != 1)
								return unsupported(fullExpr, "SocketAddr.localhost args");
							return compileRustSocketAddrLocalhostCall(args[0], false);
						case "localhostDetailed":
							if (args.length != 1)
								return unsupported(fullExpr, "SocketAddr.localhostDetailed args");
							return compileRustSocketAddrLocalhostCall(args[0], true);
						case _:
					}
				}
			case _:
		}

		// Special-case: Std.*
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.length == 0 && cls.name == "Std") {
					switch (field.name) {
						case "int": {
								// Haxe `Std.int` truncates toward zero (and returns 0 for NaN).
								// Rust float-to-int casts do exactly that.
								if (args.length != 1)
									return unsupported(fullExpr, "Std.int args");
								return ECast(compileExpr(args[0]), "i32");
							}

						case "isOfType": {
								if (args.length != 2)
									return unsupported(fullExpr, "Std.isOfType args");

								var valueExpr = args[0];
								var typeExpr = args[1];

								var expectedClass:Null<ClassType> = switch (typeExpr.expr) {
									case TTypeExpr(TClassDecl(cls2Ref)): cls2Ref.get();
									case _: null;
								};
								var expectedEnum:Null<EnumType> = switch (typeExpr.expr) {
									case TTypeExpr(TEnumDecl(enumRef)): enumRef.get();
									case _: null;
								};
								var expectedPrimitive:Null<String> = switch (typeExpr.expr) {
									case TTypeExpr(TAbstract(absRef)): {
											var abs = absRef.get();
											if (abs != null && abs.module == "StdTypes") {
												switch (abs.name) {
													case "Bool", "Int", "Float":
														abs.name;
													case _:
														null;
												}
											} else {
												null;
											}
										}
									case _:
										null;
								};

								var actualClass:Null<ClassType> = switch (followType(valueExpr.t)) {
									case TInst(cls2Ref, _): cls2Ref.get();
									case _: null;
								};
								var actualEnum:Null<EnumType> = switch (followType(valueExpr.t)) {
									case TEnum(enumRef, _): enumRef.get();
									case _: null;
								};

								if (expectedClass != null && actualClass != null && isClassSubtype(actualClass, expectedClass)) {
									return ELitBool(true);
								}
								if (expectedEnum != null && actualEnum != null && enumKey(expectedEnum) == enumKey(actualEnum)) {
									return ELitBool(true);
								}

								// Dynamic values need runtime downcast checks.
								//
								// Upstream stdlib relies on this for e.g. `haxe.Unserializer` validating object keys
								// (`Std.isOfType(k, String)` where `k` is a `Dynamic` returned from `unserialize()`).
								if ((expectedClass != null || expectedEnum != null || expectedPrimitive != null)
									&& isDynamicType(valueExpr.t)) {
									var stmts:Array<RustStmt> = [];
									stmts.push(RLet("__dyn", false, null, maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr)));

									function dynamicTypeIdPredicate(expectedTypeId:RustExpr, allowSubtypes:Bool):RustExpr {
										return EMatch(ECall(EField(EPath("__dyn"), "type_id"), []), [
											{
												pat: PTupleStruct("Some", [PBind("__actual_type_id")]),
												expr: allowSubtypes ? ECall(EPath("crate::__hx_is_subtype_type_id"),
													[EPath("__actual_type_id"), expectedTypeId]) : EBinary("==", EPath("__actual_type_id"), expectedTypeId)
											},
											{pat: PPath("None"), expr: ELitBool(false)}
										]);
									}

									// `String` is a core API with multiple runtime representations (`String` and `HxString`).
									if (expectedClass != null && expectedClass.pack.length == 0 && expectedClass.name == "String") {
										var isString = ECall(EField(ECall(EField(EPath("__dyn"), "downcast_ref::<String>"), []), "is_some"), []);
										var isHxString = ECall(EField(ECall(EField(EPath("__dyn"), "downcast_ref::<hxrt::string::HxString>"), []), "is_some"),
											[]);
										return EBlock({stmts: stmts, tail: EBinary("||", isString, isHxString)});
									}

									if (expectedPrimitive != null) {
										switch (expectedPrimitive) {
											case "Bool": {
													var isBool = ECall(EField(ECall(EField(EPath("__dyn"), "downcast_ref::<bool>"), []), "is_some"), []);
													return EBlock({stmts: stmts, tail: isBool});
												}
											case "Int": {
													var isInt = ECall(EField(ECall(EField(EPath("__dyn"), "downcast_ref::<i32>"), []), "is_some"), []);
													return EBlock({stmts: stmts, tail: isInt});
												}
											case "Float": {
													var isFloat = ECall(EField(ECall(EField(EPath("__dyn"), "downcast_ref::<f64>"), []), "is_some"), []);
													return EBlock({stmts: stmts, tail: isFloat});
												}
											case _:
										}
									}

									// For class/enum dynamic boundaries we rely on stable type-id metadata captured
									// when the value is boxed into `Dynamic`.
									if (expectedClass != null) {
										return EBlock({stmts: stmts, tail: dynamicTypeIdPredicate(compileExpr(typeExpr), true)});
									}
									if (expectedEnum != null) {
										return EBlock({stmts: stmts, tail: dynamicTypeIdPredicate(compileExpr(typeExpr), false)});
									}

									return EBlock({stmts: stmts, tail: ELitBool(false)});
								}

								// Trait-object values (`HxRc<dyn BaseTrait>` and `HxRc<dyn IFace>`) only expose runtime ids.
								// Route class/interface checks through the same subtype helper used by Dynamic boundaries.
								if (expectedClass != null && (isPolymorphicClassType(valueExpr.t) || isInterfaceType(valueExpr.t))) {
									var actualId = ECall(EField(compileExpr(valueExpr), "__hx_type_id"), []);
									return ECall(EPath("crate::__hx_is_subtype_type_id"), [actualId, compileExpr(typeExpr)]);
								}

								return ELitBool(false);
							}

						case "string": {
								if (args.length != 1)
									return unsupported(fullExpr, "Std.string args");
								var value = args[0];
								var ft = followType(value.t);

								function typeHasTypeParameter(t:Type):Bool {
									var cur = followType(t);
									return switch (cur) {
										case TInst(clsRef, params): {
												var cls = clsRef.get();
												if (cls != null) {
													switch (cls.kind) {
														case KTypeParameter(_):
															true;
														case _:
															for (p in params)
																if (typeHasTypeParameter(p))
																	return true;
															false;
													}
												} else {
													false;
												}
											}
										case TAbstract(_, params): {
												for (p in params)
													if (typeHasTypeParameter(p))
														return true;
												false;
											}
										case TEnum(_, params): {
												for (p in params)
													if (typeHasTypeParameter(p))
														return true;
												false;
											}
										case TFun(params, ret): {
												for (p in params)
													if (typeHasTypeParameter(p.t))
														return true;
												typeHasTypeParameter(ret);
											}
										case TAnonymous(anonRef): {
												var anon = anonRef.get();
												if (anon != null && anon.fields != null) {
													for (cf in anon.fields)
														if (typeHasTypeParameter(cf.type))
															return true;
												}
												false;
											}
										case _:
											false;
									}
								}

								if (isStringType(ft)) {
									return ECall(EField(compileExpr(value), "clone"), []);
								} else if (isDynamicType(ft)) {
									return wrapRustStringExpr(ECall(EField(compileExpr(value), "to_haxe_string"), []));
								} else if (isCopyType(ft)) {
									return wrapRustStringExpr(ECall(EField(compileExpr(value), "to_string"), []));
								} else if (typeHasTypeParameter(ft)) {
									// `hxrt::dynamic::from(...)` requires `T: Any + 'static`, which generic type parameters
									// don't necessarily satisfy. Fall back to `Debug` formatting for generic types.
									return wrapRustStringExpr(EMacroCall("format", [ELitString("{:?}"), compileExpr(value)]));
								} else {
									var compiled = compileExpr(value);
									var needsClone = !isCopyType(value.t);
									// Avoid cloning obvious temporaries (literals) that won't be re-used after stringification.
									if (needsClone && isStringLiteralExpr(value))
										needsClone = false;
									if (needsClone && isArrayLiteralExpr(value))
										needsClone = false;
									if (needsClone) {
										compiled = ECall(EField(compiled, "clone"), []);
									}
									// Route through the runtime so `Std.string`, `trace`, and `Sys.println`
									// converge on the same formatting rules.
									return wrapRustStringExpr(ECall(EField(ECall(EPath("hxrt::dynamic::from"), [compiled]), "to_haxe_string"), []));
								}
							}

						case "parseFloat": {
								if (args.length != 1)
									return unsupported(fullExpr, "Std.parseFloat args");
								var s = args[0];
								var asStr = ECall(EField(compileExpr(s), "as_str"), []);
								return ECall(EPath("hxrt::string::parse_float"), [asStr]);
							}

						case "parseInt": {
								if (args.length != 1)
									return unsupported(fullExpr, "Std.parseInt args");
								var s = args[0];
								var asStr = ECall(EField(compileExpr(s), "as_str"), []);
								return ECall(EPath("hxrt::string::parse_int"), [asStr]);
							}

						case _:
					}
				}
			case _:
		}

		// Special-case: `String.fromCharCode(code)` -> `hxrt::string::from_char_code(code)`.
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.length == 0 && cls.name == "String" && field.name == "fromCharCode") {
					if (args.length != 1)
						return unsupported(fullExpr, "String.fromCharCode args");
					return wrapRustStringExpr(ECall(EPath("hxrt::string::from_char_code"), [compileExpr(args[0])]));
				}
			case _:
		}

		// Special-case: String instance methods -> `hxrt::string::*` helpers.
		switch (callExpr.expr) {
			case TField(obj, FInstance(_, _, cfRef)) if (isStringType(obj.t)):
				{
					var cf = cfRef.get();
					if (cf == null) {
						return unsupported(fullExpr, "string call (missing field)");
					}
					var name = cf.getHaxeName();
					var recv = compileExpr(obj);
					var asStr = ECall(EField(recv, "as_str"), []);
					var params = funParamDefsForCall(cf.type);
					var compiledArgs = compilePositionalArgsFor(params);

					function argAsStr(i:Int):RustExpr {
						return ECall(EField(compiledArgs[i], "as_str"), []);
					}

					function compileSubstringCall():RustExpr {
						var s = EPath("__hx_s");
						function sAsStr():RustExpr {
							return ECall(EField(s, "as_str"), []);
						}
						function assign(name:String, value:RustExpr):RustStmt {
							return RSemi(EAssign(EPath(name), value));
						}
						function ifStmt(cond:RustExpr, stmt:RustStmt):RustStmt {
							return RExpr(EIf(cond, EBlock({stmts: [stmt], tail: null}), null), false);
						}

						var stmts:Array<RustStmt> = [];
						var recvForBlock = isLocalExpr(obj) ? ECall(EField(recv, "clone"), []) : maybeCloneForReuseValue(recv, obj);
						stmts.push(RLet("__hx_s", false, null, recvForBlock));
						stmts.push(RLet("__hx_total", false, RI32, ECall(EPath("hxrt::string::len"), [sAsStr()])));
						stmts.push(RLet("__hx_start", true, RI32, compiledArgs[0]));
						stmts.push(RLet("__hx_end", true, RI32, ECall(EField(compiledArgs[1], "unwrap_or"), [EPath("__hx_total")])));
						stmts.push(ifStmt(EBinary("<", EPath("__hx_start"), ELitInt(0)), assign("__hx_start", ELitInt(0))));
						stmts.push(ifStmt(EBinary("<", EPath("__hx_end"), ELitInt(0)), assign("__hx_end", ELitInt(0))));
						stmts.push(ifStmt(EBinary(">", EPath("__hx_start"), EPath("__hx_total")), assign("__hx_start", EPath("__hx_total"))));
						stmts.push(ifStmt(EBinary(">", EPath("__hx_end"), EPath("__hx_total")), assign("__hx_end", EPath("__hx_total"))));
						stmts.push(ifStmt(EBinary(">", EPath("__hx_start"), EPath("__hx_end")),
							RSemi(ECall(EPath("std::mem::swap"), [EUnary("&mut ", EPath("__hx_start")), EUnary("&mut ", EPath("__hx_end"))]))));

						var lenExpr = EBinary("-", EPath("__hx_end"), EPath("__hx_start"));
						return EBlock({
							stmts: stmts,
							tail: wrapRustStringExpr(ECall(EPath("hxrt::string::substr"), [sAsStr(), EPath("__hx_start"), ECall(EPath("Some"), [lenExpr])]))
						});
					}

					switch (name) {
						case "toLowerCase":
							if (compiledArgs.length != 0)
								return unsupported(fullExpr, "String.toLowerCase args");
							return wrapRustStringExpr(ECall(EPath("hxrt::string::to_lower_case"), [asStr]));
						case "charCodeAt":
							if (compiledArgs.length != 1)
								return unsupported(fullExpr, "String.charCodeAt args");
							return ECall(EPath("hxrt::string::char_code_at"), [asStr, compiledArgs[0]]);
						case "charAt":
							if (compiledArgs.length != 1)
								return unsupported(fullExpr, "String.charAt args");
							return wrapRustStringExpr(ECall(EPath("hxrt::string::char_at"), [asStr, compiledArgs[0]]));
						case "substr":
							if (compiledArgs.length != 2)
								return unsupported(fullExpr, "String.substr args");
							return wrapRustStringExpr(ECall(EPath("hxrt::string::substr"), [asStr, compiledArgs[0], compiledArgs[1]]));
						case "substring":
							if (compiledArgs.length != 2)
								return unsupported(fullExpr, "String.substring args");
							return compileSubstringCall();
						case "indexOf":
							if (compiledArgs.length != 2)
								return unsupported(fullExpr, "String.indexOf args");
							return ECall(EPath("hxrt::string::index_of"), [asStr, argAsStr(0), compiledArgs[1]]);
						case "lastIndexOf":
							if (compiledArgs.length != 2)
								return unsupported(fullExpr, "String.lastIndexOf args");
							return ECall(EPath("hxrt::string::last_index_of"), [asStr, argAsStr(0), compiledArgs[1]]);
						case "split":
							if (compiledArgs.length != 1)
								return unsupported(fullExpr, "String.split args");
							return useNullableStringRepresentation() ? ECall(EPath("hxrt::string::split_hx"),
								[asStr, argAsStr(0)]) : ECall(EPath("hxrt::string::split"), [asStr, argAsStr(0)]);
						case _:
					}
				}
			case _:
		}

		// Special-case: haxe.io.Path static helpers.
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.join(".") == "haxe.io" && cls.name == "Path") {
					switch (field.name) {
						case "directory": {
								if (args.length != 1)
									return unsupported(fullExpr, "Path.directory args");
								var asStr = ECall(EField(compileExpr(args[0]), "as_str"), []);
								return wrapRustStringExpr(ECall(EPath("hxrt::path::directory"), [asStr]));
							}
						case _:
					}
				}
			case _:
		}

		// Special-case: `Math.*` (core numeric helpers).
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.length == 0 && cls.name == "Math") {
					switch (field.name) {
						case "isNaN": {
								if (args.length != 1)
									return unsupported(fullExpr, "Math.isNaN args");
								return ECall(EField(compileExpr(args[0]), "is_nan"), []);
							}
						case "isFinite": {
								if (args.length != 1)
									return unsupported(fullExpr, "Math.isFinite args");
								return ECall(EField(compileExpr(args[0]), "is_finite"), []);
							}
						case "ceil": {
								if (args.length != 1)
									return unsupported(fullExpr, "Math.ceil args");
								return ECall(EField(compileExpr(args[0]), "ceil"), []);
							}
						case "floor": {
								if (args.length != 1)
									return unsupported(fullExpr, "Math.floor args");
								return ECast(ECall(EField(compileExpr(args[0]), "floor"), []), "i32");
							}
						case _:
					}
				}
			case _:
		}

		// Special-case: Type.* (minimal reflection helpers)
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.length == 0 && cls.name == "Type") {
					switch (field.name) {
						case "typeof": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.typeof args");

								var valueExpr = args[0];
								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("__v", false, null, maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr)));

								var dynRecv:RustExpr = isDynamicType(valueExpr.t) ? EPath("__v") : ECall(EPath("hxrt::dynamic::from"), [EPath("__v")]);
								stmts.push(RLet("__dyn", false, null, dynRecv));

								function dynIs(rustTy:String):RustExpr {
									var down = ECall(EField(EPath("__dyn"), "downcast_ref::<" + rustTy + ">"), []);
									return ECall(EField(down, "is_some"), []);
								}

								var isNull = ECall(EField(EPath("__dyn"), "is_null"), []);
								var isInt = dynIs("i32");
								var isFloat = dynIs("f64");
								var isBool = dynIs("bool");
								var isString = dynIs("String");
								var isHxString = dynIs("hxrt::string::HxString");
								var isAnyString = EBinary("||", isString, isHxString);

								var stringClassId = typeIdExprForKey(".String");

								var out:RustExpr = EIf(isNull, EPath("crate::value_type::ValueType::TNull"),
									EIf(isInt, EPath("crate::value_type::ValueType::TInt"),
										EIf(isFloat, EPath("crate::value_type::ValueType::TFloat"),
											EIf(isBool, EPath("crate::value_type::ValueType::TBool"),
												EIf(isAnyString, ECall(EPath("crate::value_type::ValueType::TClass"), [stringClassId]),
													EPath("crate::value_type::ValueType::TObject"))))));

								return EBlock({stmts: stmts, tail: out});
							}

						case "getClassName": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.getClassName args");
								var t = args[0];
								var name = switch (t.expr) {
									case TTypeExpr(TClassDecl(cls2Ref)): {
											var c = cls2Ref.get();
											haxeRuntimeTypeName(c.pack, c.name);
										}
									case _: null;
								};
								if (name != null)
									return stringLiteralExpr(name);
								return ECall(EPath("crate::__hx_class_name"), [reflectionHandleExpr(t, "Type.getClassName")]);
							}

						case "getEnumName": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.getEnumName args");
								var t = args[0];
								var name = switch (t.expr) {
									case TTypeExpr(TEnumDecl(enRef)): {
											var en = enRef.get();
											haxeRuntimeTypeName(en.pack, en.name);
										}
									case _: null;
								};
								if (name != null)
									return stringLiteralExpr(name);
								return ECall(EPath("crate::__hx_enum_name"), [reflectionHandleExpr(t, "Type.getEnumName")]);
							}

						case "resolveClass": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.resolveClass args");
								var name = compileExpr(args[0]);
								return ECall(EPath("crate::__hx_resolve_class_name"), [ECall(EField(name, "as_str"), [])]);
							}

						case "resolveEnum": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.resolveEnum args");
								var name = compileExpr(args[0]);
								return ECall(EPath("crate::__hx_resolve_enum_name"), [ECall(EField(name, "as_str"), [])]);
							}

						case "createEmptyInstance": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.createEmptyInstance args");
								rejectApplicationReflectionOperation("Type.createEmptyInstance", fullExpr);
								// Upstream `haxe.Unserializer` types this result as `{}` while the runtime value must
								// retain the requested concrete class identity. Returning an empty `Anon` here would
								// therefore be a silent semantic substitution, not a partial implementation.
								return unsupportedReflectionRuntimeExpr("Type.createEmptyInstance", args, fullExpr);
							}

						case "getEnumConstructs": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.getEnumConstructs args");
								return switch (unwrapMetaParen(args[0]).expr) {
									case TTypeExpr(TEnumDecl(enumRef)):
										reflectionStringArrayExpr(enumConstructorNames(enumRef.get()));
									case _:
										ECall(EPath("crate::__hx_enum_constructs"), [reflectionHandleExpr(args[0], "Type.getEnumConstructs")]);
								};
							}

						case "createEnum": {
								if (args.length < 2 || args.length > 3)
									return unsupported(fullExpr, "Type.createEnum args");
								rejectApplicationReflectionOperation("Type.createEnum", fullExpr);
								return unsupportedReflectionRuntimeExpr("Type.createEnum", args, fullExpr);
							}

						case _:
					}
				}
			case _:
		}

		// Special-case: Reflect.* (minimal field get/set for constant field names)
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.length == 0 && cls.name == "Reflect") {
					switch (field.name) {
						case "fields": {
								if (args.length != 1)
									return unsupported(fullExpr, "Reflect.fields args");

								var obj = args[0];
								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));
								var dynRecv:RustExpr = mapsToRustDynamic(obj.t,
									obj.pos) ? EPath("__obj") : ECall(EPath("hxrt::dynamic::from"), [EPath("__obj")]);
								stmts.push(RLet("__dyn", false, null, dynRecv));
								var keys = ECall(EPath("hxrt::dynamic::field_names"), [EUnary("&", EPath("__dyn"))]);
								return EBlock({stmts: stmts, tail: keys});
							}

						case "field": {
								if (args.length != 2)
									return unsupported(fullExpr, "Reflect.field args");

								var obj = args[0];
								var nameExpr = args[1];
								var fieldName:Null<String> = switch (nameExpr.expr) {
									case TConst(TString(s)): s;
									case _: null;
								};
								if (fieldName == null) {
									// Runtime field name: route through `hxrt::dynamic::field_get`.
									// This supports dynamic objects (DynObject) and runtime anon objects.
									var stmts:Array<RustStmt> = [];
									var recvExpr = maybeCloneForReuseValue(compileExpr(obj), obj);
									stmts.push(RLet("__obj", false, null, recvExpr));
									stmts.push(RLet("__name", false, null, maybeCloneForReuseValue(compileExpr(nameExpr), nameExpr)));
									var dynRecv:RustExpr = mapsToRustDynamic(obj.t,
										obj.pos) ? EPath("__obj") : ECall(EPath("hxrt::dynamic::from"), [EPath("__obj")]);
									stmts.push(RLet("__dyn", false, null, dynRecv));
									var asStr = ECall(EField(EPath("__name"), "as_str"), []);
									var getCall = ECall(EPath("hxrt::dynamic::field_get"), [EUnary("&", EPath("__dyn")), asStr]);
									return EBlock({stmts: stmts, tail: getCall});
								}

								// Classes: compile to a concrete field read and box into Dynamic.
								switch (followType(obj.t)) {
									case TInst(cls2Ref, _): {
											var owner = cls2Ref.get();
											if (owner != null) {
												var cf:Null<ClassField> = null;
												for (f in owner.fields.get()) {
													if (f.name == fieldName || f.getHaxeName() == fieldName) {
														cf = f;
														break;
													}
												}
												if (cf != null) {
													switch (cf.kind) {
														case FVar(_, _): {
																var value = compileInstanceFieldRead(obj, owner, cf, fullExpr);
																return ECall(EPath("hxrt::dynamic::from"), [value]);
															}
														case _:
													}
												}
											}
										}
									case _:
								}

								// Anonymous objects: lower to `hxrt::anon::Anon` access when applicable.
								switch (followType(obj.t)) {
									case TAnonymous(anonRef): {
											var anon = anonRef.get();
											if (anon != null && anon.fields != null) {
												var cf:Null<ClassField> = null;
												for (f in anon.fields) {
													if (f.name == fieldName || f.getHaxeName() == fieldName) {
														cf = f;
														break;
													}
												}
												if (cf != null) {
													var value:RustExpr;
													if (isAnonObjectType(obj.t)) {
														var recv = compileExpr(obj);
														var borrowed = ECall(EField(recv, "borrow"), []);
														value = compileAnonObjectBorrowedFieldRead(borrowed, cf, fullExpr.pos);
													} else {
														// Iterator protocol structs remain direct field values.
														value = EField(compileExpr(obj), cf.getHaxeName());
														if (!isCopyType(cf.type)) {
															value = ECall(EField(value, "clone"), []);
														}
													}
													return ECall(EPath("hxrt::dynamic::from"), [value]);
												}
											}
										}
									case _:
								}

								// Dynamic receivers: route through runtime dynamic field access.
								// This covers e.g. `Reflect.field(Json.parse(...), "a")`.
								if (isDynamicType(obj.t)) {
									var stmts:Array<RustStmt> = [];
									var recvExpr = maybeCloneForReuseValue(compileExpr(obj), obj);
									stmts.push(RLet("__obj", false, null, recvExpr));
									var getCall = ECall(EPath("hxrt::dynamic::field_get"), [EUnary("&", EPath("__obj")), ELitString(fieldName)]);
									return EBlock({stmts: stmts, tail: getCall});
								}

								return unsupported(fullExpr, "Reflect.field (unsupported receiver/field)");
							}

						case "setField": {
								if (args.length != 3)
									return unsupported(fullExpr, "Reflect.setField args");

								var obj = args[0];
								var nameExpr = args[1];
								var valueExpr = args[2];
								var fieldName:Null<String> = switch (nameExpr.expr) {
									case TConst(TString(s)): s;
									case _: null;
								};
								if (fieldName == null) {
									// Runtime field name: route through `hxrt::dynamic::field_set`.
									var stmts:Array<RustStmt> = [];
									stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));
									var nameRust = maybeCloneForReuseValue(compileExpr(nameExpr), nameExpr);
									nameRust = coerceExprToExpected(nameRust, nameExpr, Context.getType("String"));
									stmts.push(RLet("__name", false, null, nameRust));
									var dynRecv:RustExpr = mapsToRustDynamic(obj.t,
										obj.pos) ? EPath("__obj") : ECall(EPath("hxrt::dynamic::from"), [EPath("__obj")]);
									stmts.push(RLet("__dyn", false, null, dynRecv));

									var rhsExpr = maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr);
									var dynVal:RustExpr = mapsToRustDynamic(valueExpr.t,
										valueExpr.pos) ? rhsExpr : ECall(EPath("hxrt::dynamic::from"), [rhsExpr]);
									stmts.push(RLet("__val", false, null, dynVal));

									var asStr = ECall(EField(EPath("__name"), "as_str"), []);
									var setCall = ECall(EPath("hxrt::dynamic::field_set"), [EUnary("&", EPath("__dyn")), asStr, EPath("__val")]);
									stmts.push(RSemi(setCall));
									return EBlock({stmts: stmts, tail: null});
								}

								// Haxe signature is `setField(o:Dynamic, field:String, value:Dynamic):Void`,
								// so typed AST generally coerces `value` to Dynamic. Convert back via runtime downcast.
								function dynamicToConcrete(dynVar:String, target:Type, pos:haxe.macro.Expr.Position):RustExpr {
									var nullInner = nullInnerType(target);
									if (nullInner != null) {
										var innerRust = rustTypeToString(toRustType(nullInner, pos));
										var optTyStr = "Option<" + innerRust + ">";
										var optTry = "__opt";
										var stmts:Array<RustStmt> = [];
										stmts.push(RLet(optTry, false, null, ECall(EField(EPath(dynVar), "downcast_ref::<" + optTyStr + ">"), [])));
										var hasOpt = ECall(EField(EPath(optTry), "is_some"), []);
										var thenExpr = ECall(EField(ECall(EField(EPath(optTry), "unwrap"), []), "clone"), []);
										var innerExpr = ECall(EField(ECall(EField(EPath(dynVar), "downcast_ref::<" + innerRust + ">"), []), "unwrap"), []);
										var elseExpr = ECall(EPath("Some"), [ECall(EField(innerExpr, "clone"), [])]);
										return EBlock({stmts: stmts, tail: EIf(hasOpt, thenExpr, elseExpr)});
									}

									var tyStr = rustTypeToString(toRustType(target, pos));
									var down = ECall(EField(EPath(dynVar), "downcast_ref::<" + tyStr + ">"), []);
									var unwrapped = ECall(EField(down, "unwrap"), []);
									return ECall(EField(unwrapped, "clone"), []);
								}

								// Class instance field assignment.
								switch (followType(obj.t)) {
									case TInst(cls2Ref, _): {
											var owner = cls2Ref.get();
											if (owner != null) {
												var cf:Null<ClassField> = null;
												for (f in owner.fields.get()) {
													if (f.name == fieldName || f.getHaxeName() == fieldName) {
														cf = f;
														break;
													}
												}
												if (cf != null) {
													switch (cf.kind) {
														case FVar(_, _): {
																if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
																	return unsupported(fullExpr, "Reflect.setField (polymorphic receiver)");
																}

																var stmts:Array<RustStmt> = [];
																stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));
																var rhsExpr = maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr);
																if (isDynamicType(valueExpr.t)) {
																	stmts.push(RLet("__v", false, null, rhsExpr));
																	stmts.push(RLet("__val", false, null, dynamicToConcrete("__v", cf.type, fullExpr.pos)));
																} else {
																	stmts.push(RLet("__val", false, null, coerceExprToExpected(rhsExpr, valueExpr, cf.type)));
																}

																var access = EField(ECall(EField(EPath("__obj"), "borrow_mut"), []), rustFieldName(owner, cf));
																stmts.push(RSemi(EAssign(access, EPath("__val"))));
																return EBlock({stmts: stmts, tail: null});
															}
														case _:
													}
												}
											}
										}
									case _:
								}

								// Anonymous object field assignment (general `hxrt::anon::Anon` only).
								switch (followType(obj.t)) {
									case TAnonymous(anonRef): {
											var anon = anonRef.get();
											if (anon != null && anon.fields != null) {
												var cf:Null<ClassField> = null;
												for (f in anon.fields) {
													if (f.name == fieldName || f.getHaxeName() == fieldName) {
														cf = f;
														break;
													}
												}
												if (cf != null && isAnonObjectType(obj.t)) {
													var stmts:Array<RustStmt> = [];
													stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));
													var rhsExpr = maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr);
													if (isDynamicType(valueExpr.t)) {
														stmts.push(RLet("__v", false, null, rhsExpr));
														stmts.push(RLet("__val", false, null, dynamicToConcrete("__v", cf.type, fullExpr.pos)));
													} else {
														stmts.push(RLet("__val", false, null, coerceExprToExpected(rhsExpr, valueExpr, cf.type)));
													}
													var setCall = ECall(EField(ECall(EField(EPath("__obj"), "borrow_mut"), []), "set"),
														[ELitString(cf.getHaxeName()), EPath("__val")]);
													stmts.push(RSemi(setCall));
													return EBlock({stmts: stmts, tail: null});
												}
											}
										}
									case _:
								}

								// Dynamic receivers: route through runtime dynamic field access.
								// This covers e.g. JsonPrinter building objects via `Reflect.setField(o, k, v)`.
								if (isDynamicType(obj.t)) {
									var stmts:Array<RustStmt> = [];
									stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));

									var rhsExpr = maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr);
									var dynVal:RustExpr = mapsToRustDynamic(valueExpr.t,
										valueExpr.pos) ? rhsExpr : ECall(EPath("hxrt::dynamic::from"), [rhsExpr]);
									stmts.push(RLet("__val", false, null, dynVal));

									var setCall = ECall(EPath("hxrt::dynamic::field_set"),
										[EUnary("&", EPath("__obj")), ELitString(fieldName), EPath("__val")]);
									stmts.push(RSemi(setCall));
									return EBlock({stmts: stmts, tail: null});
								}

								return unsupported(fullExpr, "Reflect.setField (unsupported receiver/field)");
							}

						case "hasField": {
								if (args.length != 2)
									return unsupported(fullExpr, "Reflect.hasField args");

								var obj = args[0];
								var nameExpr = args[1];
								var fieldName:Null<String> = switch (nameExpr.expr) {
									case TConst(TString(s)): s;
									case _: null;
								};
								if (fieldName == null)
									return unsupported(fullExpr, "Reflect.hasField non-const");

								// Classes: check declared fields (vars and methods).
								switch (followType(obj.t)) {
									case TInst(cls2Ref, _): {
											var owner = cls2Ref.get();
											if (owner != null) {
												for (f in owner.fields.get()) {
													if (f.name == fieldName || f.getHaxeName() == fieldName) {
														return ELitBool(true);
													}
												}
												return ELitBool(false);
											}
										}
									case _:
								}

								// Anonymous objects: check structural fields.
								switch (followType(obj.t)) {
									case TAnonymous(anonRef): {
											var anon = anonRef.get();
											if (anon != null && anon.fields != null) {
												for (f in anon.fields) {
													if (f.name == fieldName || f.getHaxeName() == fieldName) {
														return ELitBool(true);
													}
												}
												return ELitBool(false);
											}
										}
									case _:
								}

								// Dynamic receivers: route through runtime dynamic field existence.
								if (isDynamicType(obj.t)) {
									var stmts:Array<RustStmt> = [];
									var recvExpr = maybeCloneForReuseValue(compileExpr(obj), obj);
									stmts.push(RLet("__obj", false, null, recvExpr));
									var hasCall = ECall(EPath("hxrt::dynamic::field_has"), [EUnary("&", EPath("__obj")), ELitString(fieldName)]);
									return EBlock({stmts: stmts, tail: hasCall});
								}

								return unsupported(fullExpr, "Reflect.hasField (unsupported receiver)");
							}

						case "compare": {
								if (args.length != 2)
									return unsupported(fullExpr, "Reflect.compare args");

								var lhsType = followType(args[0].t);
								var rhsType = followType(args[1].t);
								var lhsNumeric = TypeHelper.isInt(lhsType) || TypeHelper.isFloat(lhsType);
								var rhsNumeric = TypeHelper.isInt(rhsType) || TypeHelper.isFloat(rhsType);
								var supported = (lhsNumeric && rhsNumeric) || (isStringType(lhsType) && isStringType(rhsType));
								if (!supported)
									return unsupported(fullExpr, "Reflect.compare unsupported types");

								var lhs = maybeCloneForReuseValue(compileExpr(args[0]), args[0]);
								var rhs = maybeCloneForReuseValue(compileExpr(args[1]), args[1]);
								if (lhsNumeric && rhsNumeric && (TypeHelper.isFloat(lhsType) || TypeHelper.isFloat(rhsType))) {
									var floatTy = Context.getType("Float");
									lhs = coerceExprToExpected(lhs, args[0], floatTy);
									rhs = coerceExprToExpected(rhs, args[1], floatTy);
								}

								var equal = EBinary("==", EPath("__lhs"), EPath("__rhs"));
								var greater = EBinary(">", EPath("__lhs"), EPath("__rhs"));
								return EBlock({
									stmts: [RLet("__lhs", false, null, lhs), RLet("__rhs", false, null, rhs)],
									tail: EIf(equal, ELitInt(0), EIf(greater, ELitInt(1), ELitInt(-1)))
								});
							}

						case _:
					}
				}
			case _:
		}

		// Special-case: haxe.io.Bytes (runtime-backed)
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (isBytesClass(cls)) {
					switch (field.name) {
						case "alloc": {
								if (args.length != 1)
									return unsupported(fullExpr, "Bytes.alloc args");
								var size = ECast(compileExpr(args[0]), "usize");
								var inner = ECall(EPath("hxrt::bytes::Bytes::alloc"), [size]);
								return ECall(EPath("crate::HxRef::new"), [inner]);
							}
						case "ofString": {
								// Ignore optional encoding arg for now (must be null / omitted).
								if (args.length != 1 && args.length != 2)
									return unsupported(fullExpr, "Bytes.ofString args");
								var s = args[0];
								// Preserve evaluation order/side-effects for the encoding expression (even though we
								// currently treat encodings the same at runtime).
								if (args.length == 2) {
									var enc = compileExpr(args[1]);
									// `{ let _ = enc; HxRef::new(Bytes::of_string(...)) }`
									var asStr = ECall(EField(compileExpr(s), "as_str"), []);
									var inner = ECall(EPath("hxrt::bytes::Bytes::of_string"), [asStr]);
									var wrapped = ECall(EPath("crate::HxRef::new"), [inner]);
									return EBlock({stmts: [RLet("_", false, null, enc)], tail: wrapped});
								}
								var asStr = ECall(EField(compileExpr(s), "as_str"), []);
								var inner = ECall(EPath("hxrt::bytes::Bytes::of_string"), [asStr]);
								return ECall(EPath("crate::HxRef::new"), [inner]);
							}
						case "ofHex": {
								if (args.length != 1)
									return unsupported(fullExpr, "Bytes.ofHex args");
								var asStr = ECall(EField(compileExpr(args[0]), "as_str"), []);
								var inner = ECall(EPath("hxrt::bytes::of_hex"), [asStr]);
								return ECall(EPath("crate::HxRef::new"), [inner]);
							}
						case _:
					}
				}
			case _:
		}

		// Special-case: haxe.Log.trace(value, posInfos)
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.join(".") == "haxe" && cls.name == "Log" && field.name == "trace") {
					if (args.length == 0) {
						return EMacroCall("println", [ELitString("")]);
					}
					return compileTrace(args[0]);
				}
			case _:
		}

		// Special-case: Reflect.compareMethods(f1, f2)
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.length == 0 && cls.name == "Reflect" && field.name == "compareMethods") {
					if (args.length != 2)
						return unsupported(fullExpr, "Reflect.compareMethods args");
					var lhs = maybeCloneForReuseValue(compileExpr(args[0]), args[0]);
					var rhs = maybeCloneForReuseValue(compileExpr(args[1]), args[1]);
					return ECall(EField(lhs, "ptr_eq"), [EUnary("&", rhs)]);
				}
			case _:
		}

		// Instance method call: obj.method(args...) => Class::method(&obj, args...)
		switch (callExpr.expr) {
			case TField(obj, FInstance(clsRef, _, cfRef)):
				{
					var owner = clsRef.get();
					var cf = cfRef.get();
					if (owner == null || cf == null)
						return unsupported(fullExpr, "instance method call");
					// `super.method(...)` calls compile to a synthesized "super thunk" on the current class.
					// This avoids trying to call `Base::method(&RefCell<Base>)` with a `&RefCell<Sub>` receiver.
					if (isSuperExpr(obj)) {
						if (currentClassType == null)
							return unsupported(fullExpr, "super method call (no class context)");
						var thunk = noteSuperThunk(owner, cf);

						var clsName = classNameFromClass(currentClassType);
						var callArgs:Array<RustExpr> = [EUnary("&", EUnary("*", EPath("self_")))];
						var paramDefs:Null<Array<{name:String, t:Type, opt:Bool}>> = switch (TypeTools.follow(cf.type)) {
							case TFun(params, _): params;
							case _: null;
						};
						for (x in compilePositionalArgsFor(paramDefs))
							callArgs.push(x);
						return ECall(EPath(clsName + "::" + thunk), callArgs);
					}
					if (isBytesType(obj.t)) {
						switch (cf.getHaxeName()) {
							case "get": {
									if (args.length != 1)
										return unsupported(fullExpr, "Bytes.get args");
									var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
									return ECall(EField(borrowed, "get"), [compileExpr(args[0])]);
								}
							case "set": {
									if (args.length != 2)
										return unsupported(fullExpr, "Bytes.set args");
									var borrowed = ECall(EField(compileExpr(obj), "borrow_mut"), []);
									return ECall(EField(borrowed, "set"), [compileExpr(args[0]), compileExpr(args[1])]);
								}
							case "blit": {
									if (args.length != 4)
										return unsupported(fullExpr, "Bytes.blit args");
									var dst = compileExpr(obj);
									var src = compileExpr(args[1]);
									var pos = compileExpr(args[0]);
									var srcpos = compileExpr(args[2]);
									var len = compileExpr(args[3]);
									return ECall(EPath("hxrt::bytes::blit"), [EUnary("&", dst), pos, EUnary("&", src), srcpos, len]);
								}
							case "fill": {
									if (args.length != 3)
										return unsupported(fullExpr, "Bytes.fill args");
									return ECall(EPath("hxrt::bytes::fill"), [
										EUnary("&", compileExpr(obj)),
										compileExpr(args[0]),
										compileExpr(args[1]),
										compileExpr(args[2])
									]);
								}
							case "compare": {
									if (args.length != 1)
										return unsupported(fullExpr, "Bytes.compare args");
									return ECall(EPath("hxrt::bytes::compare"), [EUnary("&", compileExpr(obj)), EUnary("&", compileExpr(args[0]))]);
								}
							case "sub": {
									if (args.length != 2)
										return unsupported(fullExpr, "Bytes.sub args");
									var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
									var inner = ECall(EField(borrowed, "sub"), [compileExpr(args[0]), compileExpr(args[1])]);
									return ECall(EPath("crate::HxRef::new"), [inner]);
								}
							case "getString": {
									// Ignore optional encoding arg for now (must be null / omitted).
									if (args.length != 2 && args.length != 3)
										return unsupported(fullExpr, "Bytes.getString args");
									var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
									var call = ECall(EField(borrowed, "get_string"), [compileExpr(args[0]), compileExpr(args[1])]);
									if (args.length == 3) {
										var enc = compileExpr(args[2]);
										return EBlock({stmts: [RLet("_", false, null, enc)], tail: call});
									}
									return call;
								}
							case "toString": {
									if (args.length != 0)
										return unsupported(fullExpr, "Bytes.toString args");
									var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
									return ECall(EField(borrowed, "to_string"), []);
								}
							case "toHex": {
									if (args.length != 0)
										return unsupported(fullExpr, "Bytes.toHex args");
									return ECall(EPath("hxrt::bytes::to_hex"), [EUnary("&", compileExpr(obj))]);
								}
							case "getUInt16": {
									if (args.length != 1)
										return unsupported(fullExpr, "Bytes.getUInt16 args");
									return ECall(EPath("hxrt::bytes::get_u16"), [EUnary("&", compileExpr(obj)), compileExpr(args[0])]);
								}
							case "setUInt16": {
									if (args.length != 2)
										return unsupported(fullExpr, "Bytes.setUInt16 args");
									return ECall(EPath("hxrt::bytes::set_u16"), [EUnary("&", compileExpr(obj)), compileExpr(args[0]), compileExpr(args[1])]);
								}
							case "getInt32": {
									if (args.length != 1)
										return unsupported(fullExpr, "Bytes.getInt32 args");
									return ECall(EPath("hxrt::bytes::get_i32"), [EUnary("&", compileExpr(obj)), compileExpr(args[0])]);
								}
							case "setInt32": {
									if (args.length != 2)
										return unsupported(fullExpr, "Bytes.setInt32 args");
									return ECall(EPath("hxrt::bytes::set_i32"), [EUnary("&", compileExpr(obj)), compileExpr(args[0]), compileExpr(args[1])]);
								}
							case "getFloat": {
									if (args.length != 1)
										return unsupported(fullExpr, "Bytes.getFloat args");
									return ECall(EPath("hxrt::bytes::get_float"), [EUnary("&", compileExpr(obj)), compileExpr(args[0])]);
								}
							case "setFloat": {
									if (args.length != 2)
										return unsupported(fullExpr, "Bytes.setFloat args");
									return ECall(EPath("hxrt::bytes::set_float"), [EUnary("&", compileExpr(obj)), compileExpr(args[0]), compileExpr(args[1])]);
								}
							case "getDouble": {
									if (args.length != 1)
										return unsupported(fullExpr, "Bytes.getDouble args");
									return ECall(EPath("hxrt::bytes::get_double"), [EUnary("&", compileExpr(obj)), compileExpr(args[0])]);
								}
							case "setDouble": {
									if (args.length != 2)
										return unsupported(fullExpr, "Bytes.setDouble args");
									return ECall(EPath("hxrt::bytes::set_double"), [EUnary("&", compileExpr(obj)), compileExpr(args[0]), compileExpr(args[1])]);
								}
							case "getInt64": {
									if (args.length != 1)
										return unsupported(fullExpr, "Bytes.getInt64 args");
									var bytesExpr = compileExpr(obj);
									var posExpr = compileExpr(args[0]);
									return EBlock({
										stmts: [
											RLet("__bytes", false, null, bytesExpr),
											RLet("__pos", false, null, posExpr),
											RLet("__low", false, null, ECall(EPath("hxrt::bytes::get_i32"), [EUnary("&", EPath("__bytes")), EPath("__pos")])),
											RLet("__high", false, null,
												ECall(EPath("hxrt::bytes::get_i32"), [EUnary("&", EPath("__bytes")), EBinary("+", EPath("__pos"), ELitInt(4))]))
										],
										tail: ECall(EPath("crate::haxe_int64_int64::Int64::new"), [EPath("__high"), EPath("__low")])
									});
								}
							case "setInt64": {
									if (args.length != 2)
										return unsupported(fullExpr, "Bytes.setInt64 args");
									var bytesExpr = compileExpr(obj);
									var posExpr = compileExpr(args[0]);
									var valueExpr = compileExpr(args[1]);
									return EBlock({
										stmts: [
											RLet("__bytes", false, null, bytesExpr),
											RLet("__pos", false, null, posExpr),
											RLet("__value", false, null, valueExpr),
											RLet("__value_b", false, null, ECall(EField(EPath("__value"), "borrow"), [])),
											RExpr(ECall(EPath("hxrt::bytes::set_i32"),
												[EUnary("&", EPath("__bytes")), EPath("__pos"), EField(EPath("__value_b"), "low")]),
												true)
										],
										tail: ECall(EPath("hxrt::bytes::set_i32"), [
											EUnary("&", EPath("__bytes")),
											EBinary("+", EPath("__pos"), ELitInt(4)),
											EField(EPath("__value_b"), "high")
										])
									});
								}
							case _:
						}
					}
					if (isRustNetSocketAddrClass(owner) && cf.getHaxeName() == "port") {
						if (args.length != 0)
							return unsupported(fullExpr, "SocketAddr.port args");
						return compileRustSocketAddrPortCall(obj);
					}
					switch (cf.kind) {
						case FMethod(_): {
								// Extern instances compile as direct Rust method calls: `recv.method(args...)`.
								if (isExternInstanceType(obj.t)) {
									var recv = compileExpr(obj);
									var paramDefs:Null<Array<{name:String, t:Type, opt:Bool}>> = switch (TypeTools.follow(cf.type)) {
										case TFun(params, _): params;
										case _: null;
									};
									var rustName = rustExternFieldName(cf);
									// Haxe object arrays require identity-based search semantics.
									if (isArrayType(obj.t)) {
										var elem = arrayElementType(obj.t);
										if (isRcBackedType(elem)) {
											rustName = switch (rustName) {
												case "contains": "containsRef";
												case "remove": "removeRef";
												case "indexOf": "indexOfRef";
												case "lastIndexOf": "lastIndexOfRef";
												case _: rustName;
											};
										}
									}
									var externCall = ECall(EField(recv, rustName), compilePositionalArgsFor(paramDefs));
									var ret:Null<Type> = switch (TypeTools.follow(cf.type)) {
										case TFun(_, r): r;
										case _: null;
									};
									externCall = coerceGenericNullReturnToExplicitNull(externCall, ret, owner, obj.t);
									if (useNullableStringRepresentation() && isStringType(fullExpr.t)) {
										return wrapRustStringExpr(externCall);
									}
									return externCall;
								}

								// `this` inside concrete methods is always `&RefCell<Concrete>`; keep static dispatch.
								if (!isThisExpr(obj) && (isInterfaceType(obj.t) || isPolymorphicClassType(obj.t))) {
									// Interface/base-typed receiver: dynamic dispatch via trait method call.
									var recv = compileExpr(obj);
									var paramDefs:Null<Array<{name:String, t:Type, opt:Bool}>> = switch (TypeTools.follow(cf.type)) {
										case TFun(params, _): params;
										case _: null;
									};
									return ECall(EField(recv, rustMethodName(owner, cf)), compilePositionalArgsFor(paramDefs));
								}

								var clsName = classNameFromType(obj.t);
								var objCls:Null<ClassType> = switch (followType(obj.t)) {
									case TInst(objClsRef, _): objClsRef.get();
									case _: null;
								}
								// `this` calls inside inherited-method shims must dispatch as the concrete subclass,
								// not as the base class that originally owned the method body.
								//
								// Example:
								//   class A { function speak() return this.sound(); function sound() return "a"; }
								//   class B extends A { override function sound() return "b"; }
								//
								// When compiling `B.speak` as a shim for `A.speak`, we still need `this.sound()` to
								// call `B::sound`, and we must avoid attempting `A::sound(&self_: &RefCell<B>)`.
								if (isThisExpr(obj) && currentClassType != null) {
									clsName = classNameFromClass(currentClassType);
									objCls = currentClassType;
								}
								if (clsName == null)
									return unsupported(fullExpr, "instance method call");
								var recvExpr = compileExpr(obj);
								var callArgs:Array<RustExpr> = [EUnary("&", EUnary("*", recvExpr))];
								var paramDefs:Null<Array<{name:String, t:Type, opt:Bool}>> = switch (TypeTools.follow(cf.type)) {
									case TFun(params, _): params;
									case _: null;
								};
								for (x in compilePositionalArgsFor(paramDefs))
									callArgs.push(x);
								var rustName = rustMethodName(objCls != null ? objCls : owner, cf);
								var call = ECall(EPath(clsName + "::" + rustName), callArgs);

								// Haxe often treats `Null<Dynamic>` (and similar reference-nullable values) as `Dynamic`
								// at use sites. When an instance method returns `Null<Dynamic>` (lowered to
								// `Option<Dynamic>` in Rust) but the typed call expression is `Dynamic`, coerce the
								// `Option<Dynamic>` into a `Dynamic` value (mapping `None` to `Dynamic::null()`).
								//
								// This is required for upstream stdlib code like `Serializer.serialize(map.get(k))`
								// where `Map.get` returns `Null<Dynamic>` but `serialize` expects `Dynamic`.
								if (mapsToRustDynamic(fullExpr.t, fullExpr.pos)) {
									var ret:Null<Type> = switch (followType(cf.type)) {
										case TFun(_, r): r;
										case _: null;
									};
									if (ret != null && owner != null) {
										// Apply the receiver's type parameters to the return type (`Null<T>` -> `Null<Dynamic>`).
										if (owner.params != null && owner.params.length > 0) {
											switch (followType(obj.t)) {
												case TInst(_, actualParams) if (actualParams != null
													&& actualParams.length == owner.params.length):
													ret = TypeTools.applyTypeParameters(ret, owner.params, actualParams);
												case _:
											}
										}

										var inner = nullInnerType(ret);
										if (inner != null && mapsToRustDynamic(inner, fullExpr.pos)) {
											call = EBlock({
												stmts: [RLet("__hx_opt", false, null, call)],
												tail: EMatch(EPath("__hx_opt"), [
													{pat: PTupleStruct("Some", [PBind("__v")]), expr: EPath("__v")},
													{pat: PPath("None"), expr: rustDynamicNullExpr()}
												])
											});
										}
									}
								}

								var coercedReturnType:Null<Type> = switch (followType(cf.type)) {
									case TFun(_, r): r;
									case _: null;
								};
								call = coerceGenericNullReturnToExplicitNull(call, coercedReturnType, owner, obj.t);

								return call;
							}
						case _:
					}
				}
			case _:
		}

		var overrideArrayFn:Null<RustExpr> = null;
		switch (callExpr.expr) {
			case TField(obj, fa) if (isArrayType(obj.t)):
				{
					var elem = arrayElementType(obj.t);
					if (isRcBackedType(elem)) {
						var fieldName:Null<String> = switch (fa) {
							case FDynamic(name): name;
							case FAnon(cfRef): {
									var cf = cfRef.get();
									cf != null ? cf.getHaxeName() : null;
								}
							case FInstance(_, _, cfRef): {
									var cf = cfRef.get();
									cf != null ? cf.getHaxeName() : null;
								}
							case _: null;
						};

						if (fieldName != null) {
							var refName:Null<String> = switch (fieldName) {
								case "contains": "containsRef";
								case "remove": "removeRef";
								case "indexOf": "indexOfRef";
								case "lastIndexOf": "lastIndexOfRef";
								case _: null;
							};
							if (refName != null) {
								overrideArrayFn = EField(compileExpr(obj), refName);
							}
						}
					}
				}
			case _:
		}

		var f = overrideArrayFn != null ? overrideArrayFn : compileExpr(callExpr);

		// Haxe has already specialized generic call expressions. Preserve those type arguments explicitly
		// only when at least one function generic disappeared from every lowered Rust argument type; in
		// ordinary inferable calls we retain the existing compact Rust output.
		switch (callExpr.expr) {
			case TField(_, FStatic(classRef, fieldRef)):
				var owner = classRef.get();
				var field = fieldRef.get();
				if (owner != null && field != null && !owner.isExtern && field.params != null && field.params.length > 0) {
					var declaredArgs:Null<Array<{name:String, t:Type, opt:Bool}>> = switch (followType(field.type)) {
						case TFun(params, _): params;
						case _: null;
					}
					var needsExplicit = false;
					if (declaredArgs != null) {
						for (i in 0...field.params.length) {
							if (isFunctionTypeParameterErasedFromRustArguments(field, i, declaredArgs, fullExpr.pos)) {
								needsExplicit = true;
								break;
							}
						}
					}
					if (needsExplicit) {
						var applied = inferAppliedFunctionTypeArguments(field, callExpr.t);
						if (applied != null && applied.length == field.params.length) {
							var suffix = "::<" + [for (typeArg in applied) rustTypeToString(toRustType(typeArg, fullExpr.pos))].join(", ") + ">";
							f = switch (f) {
								case EPath(path): EPath(path + suffix);
								case EField(receiver, name): EField(receiver, name + suffix);
								case _: f;
							}
						}
					}
				}
			case _:
		}

		var nullableFnInner = nullInnerType(callExpr.t);
		var fnTypeForParams:Type = (nullableFnInner != null ? nullableFnInner : callExpr.t);
		// Prefer the declared field type when available so we don't lose Rust-first ref-wrapper types
		// (e.g. `rust.Ref<T>`) via aggressive type following.
		//
		// This is especially important for stdlib helpers like `rust.VecTools.len(get)` which take
		// `Ref<Vec<T>>` and must lower to `&Vec<T>` at call sites.
		if (nullableFnInner == null) {
			switch (callExpr.expr) {
				case TField(_, FStatic(_, fieldRef)):
					{
						var cf = fieldRef.get();
						if (cf != null) {
							var specialized = cf.type;
							// Why: generic Haxe calls are already specialized in `callExpr.t`, but the
							// declaration preserves its method-owned type parameters. Argument coercion must
							// see the same concrete types used by explicit Rust generic emission.
							// What: apply the Haxe-unifier result to the declared parameter/return shape.
							// How: reuse the fail-closed typed inference helper; unresolved calls retain the
							// declaration and ordinary Rust inference behavior.
							if (cf.params != null && cf.params.length > 0) {
								var applied = inferAppliedFunctionTypeArguments(cf, callExpr.t);
								if (applied != null && applied.length == cf.params.length) {
									specialized = TypeTools.applyTypeParameters(specialized, cf.params, applied);
								}
							}
							fnTypeForParams = specialized;
						}
					}
				case TField(_, FAnon(cfRef)):
					{
						var cf = cfRef.get();
						if (cf != null)
							fnTypeForParams = cf.type;
					}
				case TField(_, FInstance(clsRef, typeParams, cfRef)):
					{
						var owner = clsRef.get();
						var cf = cfRef.get();
						if (cf != null) {
							var under = cf.type;
							// Apply the receiver's type parameters so generic method signatures (like `Array<T>.sort`)
							// are specialized at call sites (`T` -> `i32`), avoiding invalid emitted Rust like `a: T`.
							if (owner != null
								&& owner.params != null
								&& owner.params.length > 0
								&& typeParams != null
								&& typeParams.length == owner.params.length) {
								under = TypeTools.applyTypeParameters(under, owner.params, typeParams);
							}
							fnTypeForParams = under;
						}
					}
				case _:
			}
		}
		function funParamDefs(t:Type):Null<Array<{name:String, t:Type, opt:Bool}>> {
			return switch (t) {
				case TLazy(f):
					funParamDefs(f());
				case TType(typeRef, params): {
						var tt = typeRef.get();
						if (tt != null) {
							var under:Type = tt.type;
							if (tt.params != null && tt.params.length > 0 && params != null && params.length == tt.params.length) {
								under = TypeTools.applyTypeParameters(under, tt.params, params);
							}
							funParamDefs(under);
						} else {
							null;
						}
					}
				case TFun(params, _):
					params;
				case _:
					null;
			};
		}

		var paramDefs:Null<Array<{name:String, t:Type, opt:Bool}>> = funParamDefs(fnTypeForParams);
		var paramDefaultExprs:Null<Array<Null<TypedExpr>>> = null;

		// If this call targets a known class field, attempt to retrieve default-arg expressions.
		//
		// This is needed for Haxe default parameters (`x = <expr>`), where `opt=true` but the
		// parameter type is not `Null<T>`. In those cases, omitted args must lower to the
		// default expression (not to `None`).
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				{
					var cls = clsRef.get();
					var cf = fieldRef.get();
					if (cls != null && cf != null) {
						switch (cf.kind) {
							case FMethod(_): {
									var fd = cf.findFuncData(cls, true);
									if (fd != null && fd.args != null) {
										paramDefaultExprs = [for (a in fd.args) a.expr];
									}
								}
							case _:
						}
					}
				}
			case TField(_, FAnon(cfRef)):
				{
					var cf = cfRef.get();
					if (cf != null) {
						// Anonymous function fields do not retain default values in a stable way today.
					}
				}
			case TField(obj, FInstance(clsRef, _, cfRef)):
				{
					var owner = clsRef.get();
					var cf = cfRef.get();
					if (owner != null && cf != null) {
						switch (cf.kind) {
							case FMethod(_): {
									var fd = cf.findFuncData(owner, false);
									if (fd != null && fd.args != null) {
										paramDefaultExprs = [for (a in fd.args) a.expr];
									}
								}
							case _:
						}
					}
				}
			case _:
		}

		// Calling `Null<Fn>` values:
		//
		// - Some `Null<T>` values lower to `Option<T>` in Rust, which requires unwrapping at call sites.
		// - Function values on this backend lower to `HxDynRef<dyn Fn...>`, which is directly callable
		//   via `Deref` (and throws `Null Access` on null), so no unwrap is needed.
		//
		// Keep the unwrap only for the legacy/rare case where a nullable function is represented as
		// `Option<...>` (i.e. when `nullOptionInnerType` says it needs an `Option` wrapper).
		if (nullableFnInner != null && nullOptionInnerType(callExpr.t, callExpr.pos) != null) {
			switch (TypeTools.follow(nullableFnInner)) {
				case TFun(_, _):
					f = ECall(EField(ECall(EField(f, "as_ref"), []), "unwrap"), []);
				case _:
			}
		}

		var a:Array<RustExpr> = [];
		for (i in 0...args.length) {
			var arg = args[i];
			var compiled = compileExpr(arg);

			if (paramDefs != null && i < paramDefs.length) {
				compiled = coerceArgForParam(compiled, arg, paramDefs[i].t);
			}

			a.push(compiled);
		}

		// Fill omitted optional arguments:
		// - `?x:T` (typed as `Null<T>`) => `None`
		// - `x = <expr>` => default expression (best-effort)
		if (paramDefs != null && args.length < paramDefs.length) {
			for (i in args.length...paramDefs.length) {
				if (!paramDefs[i].opt)
					break;
				var def:Null<TypedExpr> = (paramDefaultExprs != null && i < paramDefaultExprs.length) ? paramDefaultExprs[i] : null;
				if (def != null && defaultArgExprIsCallsiteSafe(def)) {
					var compiled = compileExpr(def);
					compiled = coerceArgForParam(compiled, def, paramDefs[i].t);
					a.push(compiled);
					continue;
				}

				// Optional-without-default: implicit `null`.
				a.push(nullFillExprForType(paramDefs[i].t, fullExpr.pos));
			}
		}

		// Dynamic callsites: `f(args...)` where `f:Dynamic`.
		//
		// This occurs in upstream stdlib (Serializer/Unserializer custom hooks) and in user code.
		// Lower to a runtime downcast to our function-value representation (`HxDynRef<dyn Fn...>`).
		if (mapsToRustDynamic(callExpr.t, fullExpr.pos)) {
			function throwMsg(msg:String):RustExpr {
				return ECall(EPath("hxrt::exception::throw"), [
					ECall(EPath("hxrt::dynamic::from"), [ECall(EPath("String::from"), [ELitString(msg)])])
				]);
			}

			var argTys = [for (arg in args) rustTypeToString(toRustType(arg.t, fullExpr.pos))];
			var fnSig = "dyn Fn(" + argTys.join(", ") + ")";
			if (!TypeHelper.isVoid(fullExpr.t)) {
				fnSig += " -> " + rustTypeToString(toRustType(fullExpr.t, fullExpr.pos));
			}
			fnSig += " + Send + Sync";
			var fnTyStr = dynRefBasePath() + "<" + fnSig + ">";

			var down = ECall(EField(EPath("__hx_dyn"), "downcast_ref::<" + fnTyStr + ">"), []);
			// Dynamic calls do not have a typed function signature at the callsite, so we can't
			// use `coerceArgForParam(...)`. Still preserve Haxe "reusable value" semantics by
			// cloning locals before passing them by value, preventing Rust moves.
			var callArgs = [for (arg in args) maybeCloneForReuseValue(compileExpr(arg), arg)];
			var call = ECall(ECall(EField(ECall(EField(EPath("__hx_f"), "unwrap"), []), "clone"), []), callArgs);

			return EBlock({
				stmts: [RLet("__hx_dyn", false, null, f), RLet("__hx_f", false, null, down),],
				tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []), throwMsg("Null Access"),
					EIf(ECall(EField(EPath("__hx_f"), "is_some"), []), call, throwMsg(dynamicBoundaryTypeName() + " call on non-function value")))
			});
		}
		return ECall(f, a);
	}

	function coerceArgForParam(compiled:RustExpr, argExpr:TypedExpr, paramType:Type):RustExpr {
		var rustParamTy = toRustType(paramType, argExpr.pos);
		function isCloneExpr(e:RustExpr):Bool {
			return switch (e) {
				case ECall(EField(_, "clone"), []): true;
				case _: false;
			}
		}

		function localReadCount(e:TypedExpr):Null<Int> {
			var u = unwrapMetaParen(e);
			while (true) {
				switch (u.expr) {
					case TCast(inner, _):
						u = unwrapMetaParen(inner);
						continue;
					case _:
				}
				break;
			}

			return switch (u.expr) {
				case TLocal(v):
					if (v != null && currentLocalReadCounts != null && currentLocalReadCounts.exists(v.id)) currentLocalReadCounts.get(v.id) else null;
				case _:
					null;
			}
		}

		// `Null<T>` (Option<T>) parameters accept either `null` (`None`) or a plain `T` (wrapped into `Some`).
		var nullInner = nullOptionInnerType(paramType, argExpr.pos);
		if (nullInner != null) {
			if (!isNullType(argExpr.t) && !isNullConstExpr(argExpr)) {
				var innerCoerced = coerceArgForParam(compiled, argExpr, nullInner);
				return wrapBorrowIfNeeded(ECall(EPath("Some"), [innerCoerced]), rustParamTy, argExpr);
			}
			return wrapBorrowIfNeeded(compiled, rustParamTy, argExpr);
		}

		// Why: Haxe Iterator values are shared cursors. Passing one to a helper must not move the
		// caller's binding when a later read remains, and cloned `hxrt::iter::Iter` values deliberately
		// share the same cursor state.
		// What: preserve the reusable-value contract for structural iterator types and both concrete
		// array-backed iterator classes exposed by Haxe's typed AST.
		// How: reuse the read-count-aware clone policy so a last-use transfer stays clone-free.
		if (isIteratorStructType(argExpr.t) || isHaxeArrayBackedIteratorType(argExpr.t)) {
			compiled = maybeCloneForReuseValue(compiled, argExpr);
		}

		if (isStringType(paramType)) {
			// Haxe Strings are immutable and commonly re-used after calls; avoid Rust moves by cloning
			// when the argument is an existing local that is used more than once.
			//
			// For non-local expressions (calls, concatenations, constructors, etc.), the expression
			// typically produces a fresh String value, so cloning it is redundant noise.
			var reads = localReadCount(argExpr);
			var shouldClone = reads == null ? true : (reads > 1);
			if (shouldClone && isLocalExpr(argExpr) && !isStringLiteralExpr(argExpr) && !isCloneExpr(compiled)) {
				compiled = ECall(EField(compiled, "clone"), []);
			}
		} else {
			// Haxe reference types are reusable references. When passed by value to Rust functions,
			// clone the `Rc` so the original local remains usable.
			var isByRef = switch (rustParamTy) {
				case RBorrow(_, _, _): true;
				case _: false;
			}

			// Haxe arrays, enums, class/interface handles, anonymous objects, functions, and Dynamic
			// values remain reusable after by-value calls.
			var reusableByValueArg = isArrayType(argExpr.t)
				|| isEnumValueType(argExpr.t)
				|| isRcBackedType(argExpr.t)
				|| mapsToRustDynamic(argExpr.t, argExpr.pos);
			if (!isByRef && reusableByValueArg && !isCloneExpr(compiled) && !isObviousTemporaryExpr(argExpr)) {
				if (isLocalExpr(argExpr)) {
					// Preserve the established conservative policy for direct source locals.
					compiled = ECall(EField(compiled, "clone"), []);
				} else if (isOwnershipLocalExpr(argExpr)) {
					// Why: an implicit Haxe cast can hide a local from the direct check above. Clone only
					// when another syntactic read exists; otherwise an unrelated last-use cast would gain
					// noisy output throughout generated std code.
					// What/How: the local-read helper already peels casts and supplies the conservative
					// fallback when tracking is unavailable.
					var reads = localReadCount(argExpr);
					if (reads == null || reads > 1)
						compiled = ECall(EField(compiled, "clone"), []);
				} else if (isCastWrappedThisExpr(argExpr)) {
					// `this` has no local id, so use the receiver-specific remaining-read tracker. A
					// function-value body remains conservative because its move closure may run repeatedly.
					var remainingThis = remainingThisReads();
					if (currentClosureCapturedReusableLocals != null || remainingThis == null || remainingThis > 0)
						compiled = ECall(EField(compiled, "clone"), []);
				}
			}
		}

		// Function values: coerce function items/paths into our function representation.
		// Baseline representation is `HxDynRef<dyn Fn(...) -> ...>` (nullable trait object).
		switch (followType(paramType)) {
			case TFun(params, ret):
				{
					function unwrapToCore(e:TypedExpr):TypedExpr {
						var u = unwrapMetaParen(e);
						while (true) {
							switch (u.expr) {
								case TCast(inner, _):
									u = unwrapMetaParen(inner);
									continue;
								case _:
							}
							break;
						}
						return u;
					}

					function isDynRefNew(e:RustExpr):Bool {
						var cur = e;
						while (true) {
							switch (cur) {
								case EBlock(b):
									if (b.tail == null)
										return false;
									cur = b.tail;
									continue;
								case _:
							}
							break;
						}
						return switch (cur) {
							case ECall(EPath(p), _) if (p == dynRefBasePath() + "::new"): true;
							case _: false;
						};
					}

					// If the argument is already a function value (lambda, local, method closure), it should
					// already be in `HxDynRef<dyn Fn...>` form. Avoid double-wrapping, which would turn it
					// into a higher-order wrapper that tries to call `HxDynRef` like a function.
					var core = unwrapToCore(argExpr);
					var isAlreadyFnValue = switch (core.expr) {
						case TFunction(_): true;
						case TLocal(_): true;
						case TCall(_, _): true;
						case TField(_, FClosure(_, _)): true;
						case TField(_, FInstance(_, _, _)) | TField(_, FAnon(_)) | TField(_, FDynamic(_)): true;
						case TConst(TNull): true;
						case _: false;
					};
					if (isAlreadyFnValue || isDynRefNew(compiled)) {
						// no-op
					} else {
						// Wrap a function item/path into our runtime function representation.
						//
						// Important: `HxDynRef<T>` does not support unsized coercion directly, so we type-annotate
						// the inner `HxRc<dyn Fn...>` and then wrap it into `HxDynRef`.
						var sig = switch (followType(core.t)) {
							case TFun(fnParams, fnRet): {params: fnParams, ret: fnRet};
							case _: {params: params, ret: ret};
						};

						var argParts:Array<String> = [];
						for (i in 0...sig.params.length) {
							var p = sig.params[i];
							var name = "a" + i;
							argParts.push(name + ": " + rustTypeToString(toRustType(p.t, argExpr.pos)));
						}

						var fnTraitType = rustFunctionTraitObjectType([for (p in sig.params) toRustType(p.t, argExpr.pos)],
							TypeHelper.isVoid(sig.ret) ? null : toRustType(sig.ret, argExpr.pos));

						var rcTy:RustType = rustRcType(fnTraitType);
						var rcExpr:RustExpr = ECall(EPath(rcBasePath() + "::new"), [compiled]);
						compiled = EBlock({
							stmts: [RLet("__rc", false, rcTy, rcExpr)],
							tail: ECall(EPath(dynRefBasePath() + "::new"), [EPath("__rc")])
						});
					}
				}
			case _:
		}

		var refInnerType = rustRefBorrowedValueType(paramType);
		if (refInnerType != null) {
			var borrowSource = unwrapRustRefIntroducer(argExpr);
			if (!isDirectRustRefValue(argExpr)) {
				if (!shouldSkipBorrowedStringInnerCoercion(compiled, borrowSource, refInnerType)) {
					compiled = coerceExprToExpected(compiled, borrowSource, refInnerType);
				}
			}
			return wrapBorrowIfNeeded(compiled, rustParamTy, argExpr);
		}

		compiled = coerceExprToExpected(compiled, argExpr, paramType);
		return wrapBorrowIfNeeded(compiled, rustParamTy, argExpr);
	}

	function wrapBorrowIfNeeded(expr:RustExpr, ty:RustType, valueExpr:TypedExpr):RustExpr {
		return switch (ty) {
			case RBorrow(_, mutable, _):
				// Avoid borrowing values that are already references, but *do* borrow when the "ref"
				// is introduced via an implicit `@:from` conversion (typically lowered to a cast).
				if (isDirectRustRefValue(valueExpr)) {
					expr;
				} else {
					EUnary(mutable ? "&mut " : "&", expr);
				}
			case _:
				expr;
		}
	}

	function rustRefKind(t:Type):Null<String> {
		return switch (followType(t)) {
			case TAbstract(absRef, _): {
					var abs = absRef.get();
					var key = abs.pack.join(".") + "." + abs.name;
					if (key == "rust.Ref")
						"ref"
					else if (key == "rust.MutRef")
						"mutref"
					else if (key == "rust.Str")
						"str"
					else if (key == "rust.Slice")
						"slice"
					else if (key == "rust.MutSlice")
						"mutslice"
					else
						null;
				}
			case _:
				null;
		}
	}

	function rustRefBorrowedValueType(t:Type):Null<Type> {
		return switch (followType(t)) {
			case TAbstract(absRef, params): {
					var abs = absRef.get();
					var key = abs.pack.join(".") + "." + abs.name;
					if ((key == "rust.Ref" || key == "rust.MutRef") && params.length == 1) {
						params[0];
					} else {
						null;
					}
				}
			case _:
				null;
		}
	}

	function unwrapRustRefIntroducer(e:TypedExpr):TypedExpr {
		var cur = unwrapMetaParen(e);
		while (true) {
			switch (cur.expr) {
				case TCast(inner, _) if (rustRefKind(cur.t) != null && rustRefKind(inner.t) == null):
					cur = unwrapMetaParen(inner);
					continue;
				case _:
			}
			break;
		}
		return cur;
	}

	function shouldSkipBorrowedStringInnerCoercion(expr:RustExpr, source:TypedExpr, expectedInner:Type):Bool {
		if (!isStringType(expectedInner) || !isStringType(source.t))
			return false;
		var sourceRust = toRustType(source.t, source.pos);
		if (!rustTypeIsNullableStringCarrier(sourceRust))
			return false;
		return switch (expr) {
			case EPath(_): true;
			case EField(_, _): true;
			case ECall(EField(_, "clone"), []): true;
			case ECall(EPath(path), _) if (path == "hxrt::string::HxString::from"): true;
			case _:
				false;
		}
	}

	function isDirectRustRefValue(e:TypedExpr):Bool {
		var cur = unwrapMetaParen(e);
		switch (cur.expr) {
			case TCast(inner, _):
				{
					// Casts are often used for implicit `@:from` conversions to `Ref/MutRef`, where we still
					// want to emit `&`/`&mut`.
					//
					// However, for Rust-first “ref-to-ref” coercions (e.g. `MutRef<Vec<T>> -> MutSlice<T>`),
					// the cast is type-level only and the value is already a Rust reference.
					//
					// Distinguish the two by checking whether both sides are already Rust ref kinds.
					var fromKind = rustRefKind(inner.t);
					var toKind = rustRefKind(cur.t);
					// If the cast introduces a Rust ref kind (e.g. `Vec<T> -> Ref<Vec<T>>`), we still need to
					// emit a borrow at the call site (`&vec` / `&mut vec`), so this is NOT a "direct ref value".
					if (toKind != null && fromKind == null)
						return false;
					return fromKind != null && toKind != null;
				}
			case _:
		}

		// `Ref<T>` / `MutRef<T>` locals and fields compile to `&T` / `&mut T` already.
		return rustRefKind(cur.t) != null;
	}

	function isClassSubtype(actual:ClassType, expected:ClassType):Bool {
		if (classKey(actual) == classKey(expected))
			return true;
		if (expected.isInterface)
			return classImplementsInterface(actual, expected);
		var cur = actual.superClass != null ? actual.superClass.t.get() : null;
		while (cur != null) {
			if (classKey(cur) == classKey(expected))
				return true;
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}
		return false;
	}

	/**
		Returns whether a class (or interface) implements/extends the expected interface.

		Why
		- `Std.isOfType(x, IFace)` should succeed for classes that implement `IFace`
		  (including implementations inherited from base classes).
		- Interface inheritance (`interface B extends A`) must also be honored.

		What
		- Walks `actual` and its superclasses, scanning implemented interfaces recursively.
		- Also works when `actual` itself is an interface type.

		How
		- Compares by stable `classKey(...)`.
		- Uses cycle guards to avoid infinite recursion on malformed graphs.
	**/
	function classImplementsInterface(actual:ClassType, expectedInterface:ClassType):Bool {
		if (actual == null || expectedInterface == null || !expectedInterface.isInterface)
			return false;

		var expectedKey = classKey(expectedInterface);

		function interfaceMatches(iface:ClassType, seen:Map<String, Bool>):Bool {
			if (iface == null)
				return false;
			var key = classKey(iface);
			if (key == expectedKey)
				return true;
			if (seen.exists(key))
				return false;
			seen.set(key, true);
			for (parent in iface.interfaces) {
				var parentIface = parent.t.get();
				if (parentIface != null && interfaceMatches(parentIface, seen))
					return true;
			}
			return false;
		}

		var cur:Null<ClassType> = actual;
		while (cur != null) {
			for (iface in cur.interfaces) {
				var ifaceType = iface.t.get();
				if (ifaceType != null && interfaceMatches(ifaceType, []))
					return true;
			}
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}
		return false;
	}

	function compileTrace(value:TypedExpr):RustExpr {
		// Haxe `trace` uses `Std.string(value)` semantics. Route through `hxrt::dynamic::Dynamic`
		// so formatting matches `Std.string` and `Sys.println`.
		var compiled = compileExpr(value);
		if (isDynamicType(followType(value.t))) {
			// Typed AST may coerce trace args to Dynamic; print that value directly.
			return EMacroCall("println", [ELitString("{}"), compiled]);
		}
		var needsClone = !isCopyType(value.t);
		if (needsClone && isStringLiteralExpr(value))
			needsClone = false;
		if (needsClone && isArrayLiteralExpr(value))
			needsClone = false;
		if (needsClone) {
			compiled = ECall(EField(compiled, "clone"), []);
		}
		return EMacroCall("println", [ELitString("{}"), ECall(EPath("hxrt::dynamic::from"), [compiled])]);
	}

	function exprUsesThis(e:TypedExpr):Bool {
		var used = false;
		function scan(x:TypedExpr):Void {
			if (used)
				return;
			switch (unwrapMetaParen(x).expr) {
				case TConst(TThis):
					used = true;
					return;
				case TConst(TSuper):
					used = true;
					return;
				case _:
			}
			TypedExprTools.iter(x, scan);
		}
		scan(e);
		return used;
	}

	function isThisExpr(e:TypedExpr):Bool {
		return switch (e.expr) {
			case TConst(TThis): true;
			case _: false;
		}
	}

	/**
		Returns whether a structural field is optional in Haxe source.

		Why
		- Anonymous records use one runtime container (`hxrt::anon::Anon`) for both required and
		  optional fields.
		- Required reads should keep failing loudly when a malformed value omits the field, but optional
		  reads must preserve Haxe's "omitted means null" contract.

		What
		- Detects Haxe's typed `@:optional` marker. The compiler usually stores it as `:optional`;
		  accepting `optional` too keeps this helper robust for metadata shape drift.

		How
		- `compileAnonObjectFieldRead` uses this to select a compiler-emitted `has_key(...)` guard
		  only for optional structural fields.
	**/
	function isOptionalAnonField(cf:ClassField):Bool {
		return cf != null && (cf.meta.has(":optional") || cf.meta.has("optional"));
	}

	/**
		Compile a typed field read from a runtime anonymous object.

		Why
		- General anonymous objects lower to `HxRef<hxrt::anon::Anon>`, not native Rust structs.
		- Field reads therefore cross a typed runtime boundary and must centralize optional-field
		  semantics instead of open-coding `get::<T>` at every callsite.

		What
		- Required fields read through `Anon::get::<T>` and still panic if missing.
		- Optional fields emit a `has_key(...)` branch and use the compiler's null-fill value for the
		  declared Haxe type when absent.
		- Function-valued fields leave the borrow scope before surrounding user code can call them.

		How
		- The caller supplies an `Anon` borrow expression so normal field reads and `Reflect.field` can
		  share this lowering while keeping their existing receiver evaluation order.
		- For function-valued fields, a block binds both the read guard and cloned result. Returning the
		  result from that block drops the guard before invocation, preventing callback-driven mutation of
		  the same record from deadlocking on its own read lock.
		- Ordinary required values retain the direct read shape; they do not execute user code after the
		  typed clone and therefore need no additional scope.
	**/
	function compileAnonObjectBorrowedFieldRead(borrowed:RustExpr, cf:ClassField, pos:haxe.macro.Expr.Position):RustExpr {
		var tyStr = rustTypeToString(toRustType(cf.type, pos));
		var getter = "get::<" + tyStr + ">";
		var fieldName = cf.getHaxeName();
		var read = ECall(EField(EPath("__b"), getter), [ELitString(fieldName)]);
		var optional = isOptionalAnonField(cf);
		var value = if (optional) {
			var hasField = ECall(EField(EPath("__b"), "has_key"), [ELitString(fieldName)]);
			EIf(hasField, read, nullFillExprForType(cf.type, pos));
		} else {
			read;
		};
		var functionValued = switch (followType(cf.type)) {
			case TFun(_, _): true;
			case _: false;
		};
		if (optional) {
			return EBlock({
				stmts: [RLet("__b", false, null, borrowed)],
				tail: value
			});
		}
		if (!functionValued)
			return ECall(EField(borrowed, getter), [ELitString(fieldName)]);
		return EBlock({
			stmts: [RLet("__b", false, null, borrowed), RLet("__hx_value", false, null, value)],
			tail: EPath("__hx_value")
		});
	}

	function compileAnonObjectFieldRead(obj:TypedExpr, cf:ClassField, pos:haxe.macro.Expr.Position):RustExpr {
		var recv = compileExpr(obj);
		var borrowed = ECall(EField(recv, "borrow"), []);
		return compileAnonObjectBorrowedFieldRead(borrowed, cf, pos);
	}

	function currentThisPathExpr():RustExpr {
		return EPath((currentFunctionIsAsync && currentThisIdent != null) ? currentThisIdent : "self_");
	}

	function compileField(obj:TypedExpr, fa:FieldAccess, fullExpr:TypedExpr):RustExpr {
		return switch (fa) {
			case FStatic(clsRef, cfRef): {
					var cls = clsRef.get();
					var cf = cfRef.get();
					var key = cls.pack.join(".") + "." + cls.name;

					// `Math.*` is an extern core API. Map constants directly to Rust `f64` constants.
					if (cls.pack.length == 0 && cls.name == "Math") {
						switch (cf.getHaxeName()) {
							case "PI":
								return EPath("std::f64::consts::PI");
							case "NEGATIVE_INFINITY":
								return EPath("f64::NEG_INFINITY");
							case "POSITIVE_INFINITY":
								return EPath("f64::INFINITY");
							case "NaN":
								return EPath("f64::NAN");
							case _:
						}
					}

					// Extern static access maps to a Rust path, optionally overridden via `@:native(...)`.
					if (cls.isExtern) {
						var base = rustExternBasePath(cls);
						return EPath((base != null ? base : cls.name) + "::" + rustExternFieldName(cf));
					}

					var inlineStatic = staticReadOnlyConstantExpr(cf);
					if (inlineStatic != null) {
						var value = compileExpr(inlineStatic);
						return coerceExprToExpected(value, inlineStatic, cf.type);
					}

					// Static vars are stored in module-level lazy cells (`__hx_static_get_*`).
					switch (cf.kind) {
						case FVar(_, _): {
								var rustName = rustMethodName(cls, cf);
								var getterFn = rustStaticVarHelperName("__hx_static_get", rustName);
								return ECall(EPath(staticVarHelperPath(cls, getterFn)), []);
							}
						case _:
					}

					if (mainClassKey != null && currentClassKey != null && key == currentClassKey && key == mainClassKey) {
						EPath(rustMethodName(cls, cf));
					} else {
						var modName = rustModulePathForClass(cls);
						EPath("crate::" + modName + "::" + rustTypeNameForClass(cls) + "::" + rustMethodName(cls, cf));
					}
				}
			case FEnum(enumRef, efRef): {
					var en = enumRef.get();
					var ef = efRef;
					EPath(rustEnumVariantPath(en, ef.name));
				}
			case FClosure(_, cfRef): {
					var cf = cfRef.get();
					var owner:Null<ClassType> = switch (followType(obj.t)) {
						case TInst(clsRef, _): clsRef.get();
						case _: null;
					};
					if (owner == null)
						return unsupported(fullExpr, "closure field (unknown owner)");
					compileInstanceMethodValue(obj, owner, cf, fullExpr);
				}
			case FInstance(clsRef, _, cfRef): {
					var owner = clsRef.get();
					var cf = cfRef.get();
					if (owner == null || cf == null)
						return unsupported(fullExpr, "instance field");

					// `super.field` reads compile to direct struct field reads on the current receiver.
					// We resolve the Rust field name against the current class so inherited-field renames are respected.
					if (isSuperExpr(obj)) {
						switch (cf.kind) {
							case FMethod(_):
								return unsupported(fullExpr, "super method value");
							case _:
						}

						// `super.prop` should call the base accessor when the property uses `get_...`.
						switch (cf.kind) {
							case FVar(read, _): {
									if (read == AccCall) {
										if (currentClassType == null)
											return unsupported(fullExpr, "super property read (no class context)");
										var propName = cf.getHaxeName();
										if (propName == null)
											return unsupported(fullExpr, "super property read (missing name)");
										var getterName = "get_" + propName;
										var getter:Null<ClassField> = null;
										var cur:Null<ClassType> = owner;
										while (cur != null && getter == null) {
											for (f in cur.fields.get()) {
												if (f.getHaxeName() == getterName) {
													switch (f.kind) {
														case FMethod(_): getter = f;
														case _:
													}
													if (getter != null)
														break;
												}
											}
											cur = cur.superClass != null ? cur.superClass.t.get() : null;
										}
										if (getter == null)
											return unsupported(fullExpr, "super property read (missing getter)");
										var thunk = noteSuperThunk(owner, getter);
										var clsName = classNameFromClass(currentClassType);
										return ECall(EPath(clsName + "::" + thunk), [EUnary("&", EUnary("*", EPath("self_")))]);
									}
								}
							case _:
						}

						var recv = EPath("self_");
						var fieldName = rustFieldName(currentClassType != null ? currentClassType : owner, cf);
						var access = EField(EPath("__b"), fieldName);
						var tail = (!TypeHelper.isBool(fullExpr.t) && !TypeHelper.isInt(fullExpr.t) && !TypeHelper.isFloat(fullExpr.t)) ? ECall(EField(access,
							"clone"), []) : access;
						return EBlock({
							stmts: [RLet("__b", false, null, ECall(EField(recv, "borrow"), []))],
							tail: tail
						});
					}

					// haxe.io.Bytes length: `b.length` -> `b.borrow().length()`
					if (isBytesType(obj.t) && cf.getHaxeName() == "length") {
						var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
						return ECall(EField(borrowed, "length"), []);
					}

					// Haxe Array length: `arr.length` -> `arr.len() as i32`
					if (isArrayType(obj.t) && cf.getHaxeName() == "length") {
						var lenCall = ECall(EField(compileExpr(obj), "len"), []);
						return ECast(lenCall, "i32");
					}

					// Haxe String length: `s.length` -> `hxrt::string::len(s.as_str())`
					if (isStringType(obj.t) && cf.getHaxeName() == "length") {
						var recv = compileExpr(obj);
						var asStr = ECall(EField(recv, "as_str"), []);
						return ECall(EPath("hxrt::string::len"), [asStr]);
					}

					switch (cf.kind) {
						case FMethod(_):
							compileInstanceMethodValue(obj, owner, cf, fullExpr);
						case _:
							compileInstanceFieldRead(obj, owner, cf, fullExpr);
					}
				}
			case FAnon(cfRef): {
					var cf = cfRef.get();
					// General anonymous objects are lowered to `hxrt::anon::Anon` and accessed via typed `get`.
					// Structural iterator protocol values remain direct field access.
					if (cf != null && isAnonObjectType(obj.t)) {
						return compileAnonObjectFieldRead(obj, cf, fullExpr.pos);
					}
					EField(compileExpr(obj), cf.getHaxeName());
				}
			case FDynamic(name): {
					// Dynamic field access (`obj.field` where `obj:Dynamic`).
					//
					// Haxe expects runtime string-keyed lookup. Lower to a runtime helper that understands
					// `Dynamic` receivers (notably `sys.db` rows).
					var recv = compileExpr(obj);
					ECall(EPath("hxrt::dynamic::field_get"), [EUnary("&", recv), ELitString(name)]);
				}
			case _: unsupported(fullExpr, "field");
		}
	}

	function compileInstanceMethodValue(obj:TypedExpr, owner:ClassType, cf:ClassField, fullExpr:TypedExpr):RustExpr {
		if (isDynamicMethodField(cf) && (isThisExpr(obj) || !isPolymorphicClassType(obj.t))) {
			var recvCls = if (isThisExpr(obj) && currentClassType != null) currentClassType else owner;
			var recvName = "__hx_dyn_recv";
			var recvExpr = maybeCloneForReuseValue(compileExpr(obj), obj);
			var fieldName = rustDynamicMethodFieldName(recvCls, cf);
			return EBlock({
				stmts: [
					RLet(recvName, false, null, recvExpr),
					RLet("__hx_dyn", false, null, ECall(EField(EField(ECall(EField(EPath(recvName), "borrow"), []), fieldName), "clone"), []))
				],
				tail: EPath("__hx_dyn")
			});
		}

		// `this.method` is materialized as an owned `HxRef<T>` receiver (`__hx_this`) in instance methods.
		// That makes it safe to capture in the generated `'static` function-value wrapper, just like
		// any other instance receiver expression.

		var sig = switch (TypeTools.follow(cf.type)) {
			case TFun(params, ret): {params: params, ret: ret};
			case _: null;
		};
		if (sig == null)
			return unsupported(fullExpr, "method value (non-function type)");

		var recvExpr = maybeCloneForReuseValue(compileExpr(obj), obj);
		var recvName = "__recv";

		var argParts:Array<String> = [];
		var callArgs:Array<RustExpr> = [];
		for (i in 0...sig.params.length) {
			var p = sig.params[i];
			var name = "a" + i;
			argParts.push(name + ": " + rustTypeToString(toRustType(p.t, fullExpr.pos)));
			callArgs.push(EPath(name));
		}

		var call:RustExpr = if (isExternInstanceType(obj.t)) {
			ECall(EField(EPath(recvName), rustExternFieldName(cf)), callArgs);
		} else if ((isInterfaceType(obj.t) || isPolymorphicClassType(obj.t)) && !isThisExpr(obj)) {
			ECall(EField(EPath(recvName), rustMethodName(owner, cf)), callArgs);
		} else {
			var recvOwner = if (isThisExpr(obj) && currentClassType != null) currentClassType else owner;
			var modName = rustModulePathForClass(recvOwner);
			var path = "crate::" + modName + "::" + rustTypeNameForClass(recvOwner) + "::" + rustMethodName(recvOwner, cf);
			ECall(EPath(path), [EUnary("&", EUnary("*", EPath(recvName)))].concat(callArgs));
		};

		var isVoid = TypeHelper.isVoid(sig.ret);
		var body:RustBlock = isVoid ? {stmts: [RSemi(call)], tail: null} : {stmts: [], tail: call};

		var fnTraitType = rustFunctionTraitObjectType([for (p in sig.params) toRustType(p.t, fullExpr.pos)],
			TypeHelper.isVoid(sig.ret) ? null : toRustType(sig.ret, fullExpr.pos));

		var rcTy:RustType = rustRcType(fnTraitType);
		var rcExpr:RustExpr = ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, body, true)]);
		return EBlock({
			stmts: [RLet(recvName, false, null, recvExpr), RLet("__rc", false, rcTy, rcExpr)],
			tail: ECall(EPath(dynRefBasePath() + "::new"), [EPath("__rc")])
		});
	}

	function compileInstanceFieldRead(obj:TypedExpr, owner:ClassType, cf:ClassField, fullExpr:TypedExpr):RustExpr {
		function receiverClassForField(obj:TypedExpr, fallback:ClassType):ClassType {
			// In inherited method shims, the typed AST may treat `this` as the base class, but codegen
			// must dispatch against the concrete class being compiled.
			if (isThisExpr(obj) && currentClassType != null)
				return currentClassType;
			return switch (followType(obj.t)) {
				case TInst(clsRef, _): {
						var cls = clsRef.get();
						cls != null ? cls : fallback;
					}
				case _: fallback;
			}
		}

		function findInstanceMethodInChain(start:ClassType, haxeName:String):Null<ClassField> {
			var cur:Null<ClassType> = start;
			while (cur != null) {
				for (f in cur.fields.get()) {
					if (f.getHaxeName() != haxeName)
						continue;
					switch (f.kind) {
						case FMethod(_):
							return f;
						case _:
					}
				}
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
			return null;
		}

		// Property reads (`var x(get, ...)`) must call `get_x()` and return its value.
		switch (cf.kind) {
			case FVar(read, _):
				{
					if (read == AccCall) {
						var recvCls = receiverClassForField(obj, owner);
						var propName = cf.getHaxeName();
						if (propName == null)
							return unsupported(fullExpr, "property read (missing name)");
						// Special-case: inside `get_x()` for a storage-backed property (e.g. `default,get`),
						// Haxe treats `x` as a direct read of the backing storage to avoid recursion.
						var skipLower = varFieldHasPhysicalStorage(owner, cf)
							&& currentMethodField != null
							&& currentMethodField.getHaxeName() == ("get_" + propName);
						if (!skipLower) {
							var getter = findInstanceMethodInChain(recvCls, "get_" + propName);
							if (getter == null)
								return unsupported(fullExpr, "property read (missing getter)");

							// Polymorphic receivers use trait-object calls.
							if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
								return ECall(EField(compileExpr(obj), rustMethodName(recvCls, getter)), []);
							}

							var modName = rustModulePathForClass(recvCls);
							var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, getter);
							return ECall(EPath(path), [EUnary("&", EUnary("*", compileExpr(obj)))]);
						}
					}
				}
			case _:
		}

		// Polymorphic field reads go through generated accessors.
		if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
			return ECall(EField(compileExpr(obj), rustGetterName(owner, cf)), []);
		}

		var recv = compileExpr(obj);
		function isStableBorrowReceiver(e:RustExpr):Bool {
			return switch (e) {
				case EPath(_): true;
				case EField(base, _): isStableBorrowReceiver(base);
				case _: false;
			}
		}

		// `RefCell::borrow()` returns a guard with a lifetime tied to the receiver.
		// If the receiver is a temporary expression (e.g. `{ ... }.borrow()`), Rust rejects it with
		// "temporary value dropped while borrowed". Keep complex receivers alive via a local binding.
		var stmts:Array<RustStmt> = [];
		var borrowRecv:RustExpr = recv;
		if (!isStableBorrowReceiver(recv)) {
			stmts.push(RLet("__hx_recv", false, null, recv));
			borrowRecv = EPath("__hx_recv");
		}

		var fieldName = rustFieldName(owner, cf);
		var access = EField(EPath("__b"), fieldName);

		// Some struct fields are stored as `Option<Rc<dyn Trait>>` for allocation/defaultability
		// reasons. Unwrap them on read to preserve the non-Option surface type.
		if (shouldOptionWrapStructFieldType(cf.type)) {
			var asRef = ECall(EField(access, "as_ref"), []);
			var unwrapped = ECall(EField(asRef, "unwrap"), []);
			var tail = ECall(EField(unwrapped, "clone"), []);
			return EBlock({
				stmts: stmts.concat([RLet("__b", false, null, ECall(EField(borrowRecv, "borrow"), []))]),
				tail: tail
			});
		}

		var tail = (!TypeHelper.isBool(fullExpr.t) && !TypeHelper.isInt(fullExpr.t) && !TypeHelper.isFloat(fullExpr.t)) ? ECall(EField(access, "clone"),
			[]) : access;

		return EBlock({
			stmts: stmts.concat([RLet("__b", false, null, ECall(EField(borrowRecv, "borrow"), []))]),
			tail: tail
		});
	}

	function compileInstanceFieldAssign(obj:TypedExpr, owner:ClassType, cf:ClassField, rhs:TypedExpr):RustExpr {
		function receiverClassForField(obj:TypedExpr, fallback:ClassType):ClassType {
			// In inherited method shims, the typed AST may treat `this` as the base class, but codegen
			// must dispatch against the concrete class being compiled.
			if (isThisExpr(obj) && currentClassType != null)
				return currentClassType;
			return switch (followType(obj.t)) {
				case TInst(clsRef, _): {
						var cls = clsRef.get();
						cls != null ? cls : fallback;
					}
				case _: fallback;
			}
		}

		function findInstanceMethodInChain(start:ClassType, haxeName:String):Null<ClassField> {
			var cur:Null<ClassType> = start;
			while (cur != null) {
				for (f in cur.fields.get()) {
					if (f.getHaxeName() != haxeName)
						continue;
					switch (f.kind) {
						case FMethod(_):
							return f;
						case _:
					}
				}
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
			return null;
		}

		// Haxe `Array.length = n` must resize the array (truncate/extend) and fill new slots with `null`.
		//
		// Upstream stdlib relies on this behavior for `haxe.ds.Vector` on "other" targets (our case),
		// which uses an `Array<T>` backend and sets `this.length = length` in its constructor.
		if (isArrayType(obj.t) && cf.getHaxeName() == "length") {
			var elem = arrayElementType(obj.t);
			var fillExpr:RustExpr = nullFillExprForType(elem, rhs.pos);

			var stmts:Array<RustStmt> = [];
			var rhsExpr = compileExpr(rhs);
			rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
			stmts.push(RLet("__tmp", false, null, rhsExpr));

			// Clamp negative lengths to 0 (Haxe behavior is "unspecified", but 0 is a safe baseline).
			var clamped = EIf(EBinary("<", EPath("__tmp"), ELitInt(0)), ELitInt(0), EPath("__tmp"));
			var lenUsize = ECast(clamped, "usize");
			var fillClosure = EClosure([], {stmts: [], tail: fillExpr}, true);

			stmts.push(RSemi(ECall(EField(compileExpr(obj), "set_length_haxe"), [lenUsize, fillClosure])));
			return EBlock({stmts: stmts, tail: EPath("__tmp")});
		}

		// Property writes (`var x(..., set)`) compile to `set_x(v)` and return the setter's return value.
		switch (cf.kind) {
			case FVar(_, write):
				{
					if (write == AccCall) {
						var recvCls = receiverClassForField(obj, owner);
						var propName = cf.getHaxeName();
						if (propName == null)
							return unsupported(rhs, "property write (missing name)");
						// Special-case: inside `set_x()` for a storage-backed property (e.g. `default,set`),
						// Haxe treats `x = v` as a direct write to backing storage to avoid recursion.
						var skipLower = varFieldHasPhysicalStorage(owner, cf)
							&& currentMethodField != null
							&& currentMethodField.getHaxeName() == ("set_" + propName);
						if (!skipLower) {
							var setter = findInstanceMethodInChain(recvCls, "set_" + propName);
							if (setter == null)
								return unsupported(rhs, "property write (missing setter)");

							var paramType:Null<Type> = switch (followType(setter.type)) {
								case TFun(params, _):
									(params != null && params.length > 0) ? params[0].t : null;
								case _:
									null;
							};
							if (paramType == null)
								return unsupported(rhs, "property write (missing setter param)");

							var rhsCompiled = coerceArgForParam(compileExpr(rhs), rhs, paramType);

							// `super.prop = rhs` must call the base setter implementation.
							if (isSuperExpr(obj)) {
								if (currentClassType == null)
									return unsupported(rhs, "super property write (no class context)");
								var thunk = noteSuperThunk(owner, setter);
								var clsName = classNameFromClass(currentClassType);
								return ECall(EPath(clsName + "::" + thunk), [EUnary("&", EUnary("*", EPath("self_"))), rhsCompiled]);
							}

							// Polymorphic receivers call through the trait object.
							if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
								return ECall(EField(compileExpr(obj), rustMethodName(recvCls, setter)), [rhsCompiled]);
							}

							var modName = rustModulePathForClass(recvCls);
							var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
							return ECall(EPath(path), [EUnary("&", EUnary("*", compileExpr(obj))), rhsCompiled]);
						}
					}
				}
			case _:
		}

		var fieldIsNullOpt = isNullOptionType(cf.type, cf.pos);
		var fieldIsOptionWrapped = shouldOptionWrapStructFieldType(cf.type);
		var rhsIsNullish = isNullType(rhs.t) || isNullConstExpr(rhs);

		if (isSuperExpr(obj)) {
			// `super.field = rhs` assigns into the inherited struct field on the current receiver.
			// `{ let __tmp = rhs; self_.borrow_mut().field = __tmp.clone(); __tmp }`
			var stmts:Array<RustStmt> = [];

			var rhsExpr = compileExpr(rhs);
			rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
			stmts.push(RLet("__tmp", false, null, rhsExpr));

			var borrowed = ECall(EField(EPath("self_"), "borrow_mut"), []);
			var access = EField(borrowed, rustFieldName(currentClassType != null ? currentClassType : owner, cf));
			var rhsVal:RustExpr = isCopyType(rhs.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
			var assigned = fieldIsOptionWrapped ? (rhsIsNullish ? EPath("None") : ECall(EPath("Some"),
				[rhsVal])) : ((fieldIsNullOpt && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal);
			stmts.push(RSemi(EAssign(access, assigned)));

			return EBlock({stmts: stmts, tail: EPath("__tmp")});
		}

		if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
			// Haxe assignment returns the RHS value.
			// `{ let __tmp = rhs; obj.__hx_set_field(__tmp.clone()); __tmp }`
			var stmts:Array<RustStmt> = [];
			var rhsExpr = compileExpr(rhs);
			rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
			stmts.push(RLet("__tmp", false, null, rhsExpr));

			var rhsVal:RustExpr = isCopyType(rhs.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
			if (!rhsIsNullish) {
				var coerceExpected:Type = cf.type;
				if (fieldIsNullOpt) {
					var inner = nullOptionInnerType(cf.type, rhs.pos);
					if (inner != null)
						coerceExpected = inner;
				}
				rhsVal = coerceExprToExpected(rhsVal, rhs, coerceExpected);
			}
			// Note: setters expose the *surface* type, not the storage type. Storage-level
			// `Option<...>` wrapping (for trait objects) is handled inside the setter impl.
			var assigned = (fieldIsNullOpt && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal;
			stmts.push(RSemi(ECall(EField(compileExpr(obj), rustSetterName(owner, cf)), [assigned])));

			return EBlock({stmts: stmts, tail: EPath("__tmp")});
		}

		// Important: evaluate RHS before taking a mutable borrow to avoid RefCell borrow panics.
		// `{ let __tmp = rhs; obj.borrow_mut().field = __tmp.clone(); __tmp }`
		var stmts:Array<RustStmt> = [];

		var rhsExpr = compileExpr(rhs);
		rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
		stmts.push(RLet("__tmp", false, null, rhsExpr));

		var recv = compileExpr(obj);
		var borrowed = ECall(EField(recv, "borrow_mut"), []);
		var access = EField(borrowed, rustFieldName(owner, cf));
		var rhsVal:RustExpr = isCopyType(rhs.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
		if (!rhsIsNullish) {
			var coerceExpected:Type = cf.type;
			if (fieldIsNullOpt) {
				var inner = nullOptionInnerType(cf.type, rhs.pos);
				if (inner != null)
					coerceExpected = inner;
			}
			rhsVal = coerceExprToExpected(rhsVal, rhs, coerceExpected);
		}
		var assigned = fieldIsOptionWrapped ? (rhsIsNullish ? EPath("None") : ECall(EPath("Some"),
			[rhsVal])) : ((fieldIsNullOpt && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal);
		stmts.push(RSemi(EAssign(access, assigned)));

		return EBlock({
			stmts: stmts,
			tail: EPath("__tmp")
		});
	}

	function compileArrayIndexAssign(arr:TypedExpr, index:TypedExpr, rhs:TypedExpr):RustExpr {
		// Haxe assignment returns the RHS value.
		// `{ let __tmp = rhs; arr.set(idx, __tmp.clone()); __tmp }`
		var stmts:Array<RustStmt> = [];
		var rhsExpr = compileExpr(rhs);
		rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
		stmts.push(RLet("__tmp", false, null, rhsExpr));

		var idx = ECast(compileExpr(index), "usize");
		var rhsVal:RustExpr = isCopyType(rhs.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
		var fill = nullFillExprForType(arrayElementType(arr.t), rhs.pos);
		var fillFn = EClosure([], {stmts: [], tail: fill}, true);
		stmts.push(RSemi(ECall(EField(compileExpr(arr), "set_haxe"), [idx, rhsVal, fillFn])));

		return EBlock({stmts: stmts, tail: EPath("__tmp")});
	}

	function classNameFromType(t:Type):Null<String> {
		var ft = TypeTools.follow(t);
		return switch (ft) {
			case TInst(clsRef, _): {
					var cls = clsRef.get();
					if (cls == null)
						null
					else if (isMainClass(cls))
						rustTypeNameForClass(cls)
					else
						("crate::" + rustModulePathForClass(cls) + "::" + rustTypeNameForClass(cls));
				}
			case _: null;
		}
	}

	function classNameFromClass(cls:ClassType):String {
		return isMainClass(cls) ? rustTypeNameForClass(cls) : ("crate::" + rustModulePathForClass(cls) + "::" + rustTypeNameForClass(cls));
	}

	function isExternInstanceType(t:Type):Bool {
		return switch (followType(t)) {
			case TInst(clsRef, _): clsRef.get().isExtern;
			case _: false;
		}
	}

	function unwrapMetaExpr(e:Expr):Expr {
		return switch (e.expr) {
			case EParenthesis(inner): unwrapMetaExpr(inner);
			case EMeta(_, inner): unwrapMetaExpr(inner);
			case _: e;
		}
	}

	function readConstStringExpr(e:Expr):Null<String> {
		return switch (unwrapMetaExpr(e).expr) {
			case EConst(CString(s, _)): s;
			case _: null;
		}
	}

	function rustExternBasePath(cls:ClassType):Null<String> {
		for (entry in cls.meta.get()) {
			if (entry.name != ":native")
				continue;
			if (entry.params == null || entry.params.length == 0)
				continue;
			var path = readConstStringExpr(entry.params[0]);
			if (path != null)
				return path;
		}
		return null;
	}

	function rustExternFieldName(cf:ClassField):String {
		function escapeRustPathOrIdent(name:String):String {
			if (RustNaming.isValidIdent(name))
				return RustNaming.escapeKeyword(name);
			if (name != null && name.indexOf("::") >= 0) {
				var parts = name.split("::");
				for (i in 0...parts.length) {
					if (RustNaming.isValidIdent(parts[i]))
						parts[i] = RustNaming.escapeKeyword(parts[i]);
				}
				return parts.join("::");
			}
			return name;
		}

		for (entry in cf.meta.get()) {
			if (entry.name != ":native")
				continue;
			if (entry.params == null || entry.params.length == 0)
				continue;
			var nativeName = readConstStringExpr(entry.params[0]);
			if (nativeName != null)
				return escapeRustPathOrIdent(nativeName);
		}
		// For extern fields, Haxe may rewrite the field name and store the original name in `:realPath`.
		// Use the actual (post-metadata) identifier by default.
		return escapeRustPathOrIdent(cf.name);
	}

	function rustDerivesFromMeta(meta:haxe.macro.Type.MetaAccess):Array<String> {
		var derives:Array<String> = [];

		for (entry in meta.get()) {
			if (entry.name != ":rustDerive")
				continue;

			if (entry.params == null || entry.params.length == 0) {
				#if eval
				Context.error("`@:rustDerive` requires a single parameter.", entry.pos);
				#end
				continue;
			}

			switch (entry.params[0].expr) {
				case EConst(CString(s, _)):
					derives.push(s);
				case EArrayDecl(values):
					{
						for (v in values) {
							switch (v.expr) {
								case EConst(CString(s, _)):
									derives.push(s);
								case _:
									#if eval
									Context.error("`@:rustDerive` array must contain only strings.", entry.pos);
									#end
							}
						}
					}
				case _:
					#if eval
					Context.error("`@:rustDerive` must be a string or array of strings.", entry.pos);
					#end
			}
		}

		return derives;
	}

	function rustImplsFromMeta(meta:haxe.macro.Type.MetaAccess):Array<RustImplSpec> {
		var out:Array<RustImplSpec> = [];

		function unwrap(e:Expr):Expr {
			return switch (e.expr) {
				case EParenthesis(inner): unwrap(inner);
				case EMeta(_, inner): unwrap(inner);
				case _: e;
			}
		}

		function stringConst(e:Expr):Null<String> {
			return switch (unwrap(e).expr) {
				case EConst(CString(s, _)): s;
				case _: null;
			}
		}

		for (entry in meta.get()) {
			if (entry.name != ":rustImpl")
				continue;

			var pos = entry.pos;
			if (entry.params == null || entry.params.length == 0) {
				#if eval
				Context.error("`@:rustImpl` requires at least one parameter.", pos);
				#end
				continue;
			}

			function addSpec(spec:RustImplSpec):Void {
				if (spec.traitPath == null || StringTools.trim(spec.traitPath).length == 0) {
					#if eval
					Context.error("`@:rustImpl` trait path must be a non-empty string.", pos);
					#end
					return;
				}
				out.push(spec);
			}

			// Forms:
			// - `@:rustImpl("path::Trait")`
			// - `@:rustImpl("path::Trait", "fn ...")` (body is inner content)
			// - `@:rustImpl({ trait: "...", forType: "...", body: "..." })`
			if (entry.params.length == 1) {
				var s = stringConst(entry.params[0]);
				if (s != null) {
					addSpec({traitPath: s, pos: pos});
					continue;
				}
				switch (unwrap(entry.params[0]).expr) {
					case EObjectDecl(fields):
						var traitPath:Null<String> = null;
						var forType:Null<String> = null;
						var body:Null<String> = null;

						for (field in fields) {
							switch (field.field) {
								case "trait":
									traitPath = stringConst(field.expr);
									if (traitPath == null) {
										#if eval
										Context.error("`@:rustImpl` field `trait` must be a string.", pos);
										#end
									}
								case "forType":
									forType = stringConst(field.expr);
									if (forType == null) {
										#if eval
										Context.error("`@:rustImpl` field `forType` must be a string.", pos);
										#end
									}
								case "body":
									body = stringConst(field.expr);
									if (body == null) {
										#if eval
										Context.error("`@:rustImpl` field `body` must be a string.", pos);
										#end
									}
								case _:
							}
						}

						if (traitPath != null) {
							var spec:RustImplSpec = {traitPath: traitPath, pos: pos};
							if (forType != null)
								spec.forType = forType;
							if (body != null)
								spec.body = body;
							addSpec(spec);
							continue;
						}
					case _:
				}

				#if eval
				Context.error("`@:rustImpl` must be a compile-time constant string or object.", pos);
				#end
				continue;
			}

			if (entry.params.length >= 2) {
				var traitPath:Null<String> = null;
				var body:Null<String> = null;
				traitPath = stringConst(entry.params[0]);
				body = stringConst(entry.params[1]);
				if (traitPath != null) {
					var spec:RustImplSpec = {traitPath: traitPath, pos: pos};
					if (body != null)
						spec.body = body;
					addSpec(spec);
					continue;
				}
				if (traitPath == null) {
					#if eval
					Context.error("`@:rustImpl` first parameter must be a compile-time string trait path.", pos);
					#end
					continue;
				}
				var spec:RustImplSpec = {traitPath: traitPath, pos: pos};
				if (body != null)
					spec.body = body;
				addSpec(spec);
				continue;
			}
		}

		// Stable ordering for snapshots.
		out.sort((a, b) -> compareStrings(a.traitPath, b.traitPath));
		return out;
	}

	function renderRustImplBlock(spec:RustImplSpec, implGenerics:RustGenericParameters, forType:RustType):String {
		var header = "impl" + reflaxe.rust.ast.RustASTPrinter.printGenericParameters(implGenerics);
		header += " " + spec.traitPath + " for " + (spec.forType != null ? spec.forType : rustTypeToString(forType)) + " {";

		var lines:Array<String> = [header];
		var body = spec.body;
		if (body != null) {
			var trimmed = StringTools.trim(body);
			if (trimmed.length > 0) {
				for (l in body.split("\n"))
					lines.push("\t" + l);
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	function mergeUniqueStrings(base:Array<String>, extra:Array<String>):Array<String> {
		var seen = new Map<String, Bool>();
		var out:Array<String> = [];

		for (s in base) {
			if (seen.exists(s))
				continue;
			seen.set(s, true);
			out.push(s);
		}

		for (s in extra) {
			if (seen.exists(s))
				continue;
			seen.set(s, true);
			out.push(s);
		}

		return out;
	}

	function isInterfaceType(t:Type):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, _): clsRef.get().isInterface;
			case _: false;
		}
	}

	function isPolymorphicClassType(t:Type):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, _): {
					var cls = clsRef.get();
					!cls.isInterface && classHasSubclasses(cls)
					;
				}
			case _: false;
		}
	}

	function shouldOptionWrapStructFieldType(t:Type):Bool {
		// Haxe reference types are nullable, but this backend does not model full nullability yet.
		//
		// One particularly important case is storing polymorphic values (interfaces / base classes)
		// in struct fields, which becomes `HxRc<dyn Trait>` in Rust.
		//
		// `HxRc<dyn Trait>` does not implement `Default`, which breaks constructor allocation that
		// needs some initial value before the constructor body assigns real values.
		//
		// Wrapping these fields in `Option<...>` makes allocation always possible (`None`), while
		// getters/field-reads unwrap to preserve the non-Option surface type.
		return !isNullType(t) && (isInterfaceType(t) || isPolymorphicClassType(t));
	}

	function ensureSubclassIndex() {
		if (classHasSubclass != null)
			return;
		classHasSubclass = new Map();

		// Mark any superclass of an emitted user class as having a subclass.
		var classes = getUserClassesForModules();
		for (cls in classes) {
			var cur = cls.superClass != null ? cls.superClass.t.get() : null;
			while (cur != null) {
				if (shouldEmitClass(cur, false)) {
					classHasSubclass.set(classKey(cur), true);
				}
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
		}
	}

	function classHasSubclasses(cls:ClassType):Bool {
		ensureSubclassIndex();
		return classHasSubclass != null && classHasSubclass.exists(classKey(cls));
	}

	function emitClassTrait(classType:ClassType, funcFields:Array<ClassFuncData>):String {
		var traitName = rustTypeNameForClass(classType) + "Trait";
		var generics = rustGenericDeclsForClass(classType);
		var genericSuffix = reflaxe.rust.ast.RustASTPrinter.printGenericParameters(generics);
		var lines:Array<String> = [];
		lines.push("pub trait " + traitName + genericSuffix + ": Send + Sync {");

		for (spec in getAllInstanceVarFieldSpecsForStruct(classType)) {
			var cf = spec.field;
			var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
			var ty = rustTypeToString(toRustType(fieldType, cf.pos));
			lines.push("\tfn " + rustGetterName(classType, cf) + "(&self) -> " + ty + ";");
			lines.push("\tfn " + rustSetterName(classType, cf) + "(&self, v: " + ty + ");");
		}

		for (f in funcFields) {
			if (f.isStatic)
				continue;
			if (f.field.getHaxeName() == "new")
				continue;
			if (f.expr == null)
				continue;

			var sigArgs:Array<String> = ["&self"];
			var usedArgNames:Map<String, Bool> = [];
			for (a in f.args) {
				var baseName = a.getName();
				if (baseName == null || baseName.length == 0)
					baseName = "a";
				var argName = RustNaming.stableUnique(RustNaming.snakeIdent(baseName), usedArgNames);
				sigArgs.push(argName + ": " + rustTypeToString(toRustType(a.type, f.field.pos)));
			}
			var ret = rustTypeToString(toRustType(f.ret, f.field.pos));
			lines.push("\tfn " + rustMethodName(classType, f.field) + "(" + sigArgs.join(", ") + ") -> " + ret + ";");
		}

		lines.push("\tfn __hx_type_id(&self) -> u32;");
		lines.push("}");
		return lines.join("\n");
	}

	function emitClassTraitImplForSelf(classType:ClassType, funcFields:Array<ClassFuncData>):String {
		var modName = rustModulePathForClass(classType);
		var traitPathBase = "crate::" + modName + "::" + rustTypeNameForClass(classType) + "Trait";
		var rustSelfType = rustTypeNameForClass(classType);
		var rustSelfInst = rustClassTypeInst(classType);
		var generics = rustGenericDeclsForClass(classType);
		var genericNames = rustGenericNamesFromDecls(generics);
		var turbofish = genericNames.length > 0 ? ("::<" + genericNames.join(", ") + ">") : "";
		var traitArgs = genericNames.length > 0 ? "<" + genericNames.join(", ") + ">" : "";
		var implGenerics = reflaxe.rust.ast.RustASTPrinter.printGenericParameters(generics);

		var lines:Array<String> = [];
		lines.push("impl" + implGenerics + " " + traitPathBase + traitArgs + " for " + refCellBasePath() + "<" + rustSelfInst + "> {");

		for (spec in getAllInstanceVarFieldSpecsForStruct(classType)) {
			var cf = spec.field;
			var fieldType = specializeAncestorType(classType, spec.owner, cf.type);
			var ty = rustTypeToString(toRustType(fieldType, cf.pos));

			lines.push("\tfn " + rustGetterName(classType, cf) + "(&self) -> " + ty + " {");
			if (shouldOptionWrapStructFieldType(fieldType)) {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf) + ".as_ref().unwrap().clone()");
			} else if (isCopyType(fieldType)) {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf));
			} else {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf) + ".clone()");
			}
			lines.push("\t}");

			lines.push("\tfn " + rustSetterName(classType, cf) + "(&self, v: " + ty + ") {");
			if (shouldOptionWrapStructFieldType(fieldType)) {
				lines.push("\t\tself.borrow_mut()." + rustFieldName(classType, cf) + " = Some(v);");
			} else {
				lines.push("\t\tself.borrow_mut()." + rustFieldName(classType, cf) + " = v;");
			}
			lines.push("\t}");
		}

		for (f in funcFields) {
			if (f.isStatic)
				continue;
			if (f.field.getHaxeName() == "new")
				continue;
			if (f.expr == null)
				continue;

			var sigArgs:Array<String> = ["&self"];
			var callArgs:Array<String> = ["self"];
			var usedArgNames:Map<String, Bool> = [];
			for (a in f.args) {
				var baseName = a.getName();
				if (baseName == null || baseName.length == 0)
					baseName = "a";
				var argName = RustNaming.stableUnique(RustNaming.snakeIdent(baseName), usedArgNames);
				sigArgs.push(argName + ": " + rustTypeToString(toRustType(a.type, f.field.pos)));
				callArgs.push(argName);
			}
			var ret = rustTypeToString(toRustType(f.ret, f.field.pos));
			var rustName = rustMethodName(classType, f.field);
			lines.push("\tfn " + rustName + "(" + sigArgs.join(", ") + ") -> " + ret + " {");
			lines.push("\t\t" + rustSelfType + turbofish + "::" + rustName + "(" + callArgs.join(", ") + ")");
			lines.push("\t}");
		}

		lines.push("\tfn __hx_type_id(&self) -> u32 {");
		lines.push("\t\tcrate::" + modName + "::__HX_TYPE_ID");
		lines.push("\t}");

		lines.push("}");
		return lines.join("\n");
	}

	function emitBaseTraitImplForSubclass(baseType:ClassType, subType:ClassType, subFuncFields:Array<ClassFuncData>):String {
		var baseMod = rustModulePathForClass(baseType);
		var baseTraitPathBase = "crate::" + baseMod + "::" + rustTypeNameForClass(baseType) + "Trait";
		var rustSubType = rustTypeNameForClass(subType);
		var rustSubInst = rustClassTypeInst(subType);
		var subGenerics = rustGenericDeclsForClass(subType);
		var subGenericNames = rustGenericNamesFromDecls(subGenerics);
		var subTurbofish = subGenericNames.length > 0 ? ("::<" + subGenericNames.join(", ") + ">") : "";
		var subImplGenerics = reflaxe.rust.ast.RustASTPrinter.printGenericParameters(subGenerics);

		var resolvedBaseArgs = resolvedAncestorTypeArgs(subType, baseType);
		var baseArgs = resolvedBaseArgs != null ? resolvedBaseArgs : [];
		var baseTraitArgs = baseArgs.length > 0 ? ("<" + [for (p in baseArgs) rustTypeToString(toRustType(p, subType.pos))].join(", ") + ">") : "";

		var subMethodsByKey = new Map<String, ClassFuncData>();
		for (f in subFuncFields) {
			if (f.isStatic)
				continue;
			if (f.field.getHaxeName() == "new")
				continue;
			if (f.expr == null)
				continue;
			subMethodsByKey.set(f.field.getHaxeName() + "/" + f.args.length, f);
		}

		var lines:Array<String> = [];
		lines.push("impl"
			+ subImplGenerics
			+ " "
			+ baseTraitPathBase
			+ baseTraitArgs
			+ " for "
			+ refCellBasePath()
			+ "<"
			+ rustSubInst
			+ "> {");

		for (spec in getAllInstanceVarFieldSpecsForStruct(baseType)) {
			var cf = spec.field;
			var fieldType = specializeAncestorType(subType, spec.owner, cf.type);
			var ty = rustTypeToString(toRustType(fieldType, cf.pos));

			lines.push("\tfn " + rustGetterName(baseType, cf) + "(&self) -> " + ty + " {");
			if (shouldOptionWrapStructFieldType(fieldType)) {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf) + ".as_ref().unwrap().clone()");
			} else if (isCopyType(fieldType)) {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf));
			} else {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf) + ".clone()");
			}
			lines.push("\t}");

			lines.push("\tfn " + rustSetterName(baseType, cf) + "(&self, v: " + ty + ") {");
			if (shouldOptionWrapStructFieldType(fieldType)) {
				lines.push("\t\tself.borrow_mut()." + rustFieldName(subType, cf) + " = Some(v);");
			} else {
				lines.push("\t\tself.borrow_mut()." + rustFieldName(subType, cf) + " = v;");
			}
			lines.push("\t}");
		}

		// Base traits include inherited methods (see `emitClassTrait` using `effectiveFuncFields`).
		// Implement the same surface here: baseType declared methods with bodies plus inherited base bodies.
		var baseTraitMethods:Array<{owner:ClassType, field:ClassField}> = [];
		var baseTraitSeen:Map<String, Bool> = [];

		function considerBaseTraitMethod(owner:ClassType, cf:ClassField):Void {
			if (cf.getHaxeName() == "new")
				return;
			switch (cf.kind) {
				case FMethod(_):
					var ft = followType(cf.type);
					var argc = switch (ft) {
						case TFun(a, _): a.length;
						case _: 0;
					};
					var key = cf.getHaxeName() + "/" + argc;
					if (baseTraitSeen.exists(key))
						return;
					// Only include methods that actually have bodies; abstract/extern methods are not part of base traits yet.
					if (cf.expr() == null)
						return;
					baseTraitSeen.set(key, true);
					baseTraitMethods.push({owner: owner, field: cf});
				case _:
			}
		}

		for (cf in baseType.fields.get())
			considerBaseTraitMethod(baseType, cf);
		var curBase:Null<ClassType> = baseType.superClass != null ? baseType.superClass.t.get() : null;
		while (curBase != null) {
			for (cf in curBase.fields.get())
				considerBaseTraitMethod(curBase, cf);
			curBase = curBase.superClass != null ? curBase.superClass.t.get() : null;
		}

		function baseTraitKey(spec:{owner:ClassType, field:ClassField}):String {
			var cf = spec.field;
			var ft = followType(cf.type);
			var argc = switch (ft) {
				case TFun(a, _): a.length;
				case _: 0;
			};
			return cf.getHaxeName() + "/" + argc;
		}
		baseTraitMethods.sort((a, b) -> compareStrings(baseTraitKey(a), baseTraitKey(b)));

		for (spec in baseTraitMethods) {
			var cf = spec.field;
			switch (cf.kind) {
				case FMethod(_):
					{
						var ft = followType(specializeAncestorType(subType, spec.owner, cf.type));
						var args = switch (ft) {
							case TFun(a, _): a;
							case _: [];
						}

						var sigArgs:Array<String> = ["&self"];
						var callArgs:Array<String> = ["self"];
						var usedArgNames:Map<String, Bool> = [];
						for (i in 0...args.length) {
							var a = args[i];
							var argName = a.name != null && a.name.length > 0 ? a.name : ("a" + i);
							var rustArgName = RustNaming.stableUnique(RustNaming.snakeIdent(argName), usedArgNames);
							sigArgs.push(rustArgName + ": " + rustTypeToString(toRustType(a.t, cf.pos)));
							callArgs.push(rustArgName);
						}

						var retTy = switch (ft) {
							case TFun(_, r): r;
							case _: Context.getType("Void");
						}
						var ret = rustTypeToString(toRustType(retTy, cf.pos));

						lines.push("\tfn " + rustMethodName(baseType, cf) + "(" + sigArgs.join(", ") + ") -> " + ret + " {");
						var key = cf.getHaxeName() + "/" + args.length;
						var implFunc = subMethodsByKey.get(key);
						if (implFunc == null) {
							Context.error("Internal compiler error: missing inherited method shim for base-trait method `"
								+ cf.getHaxeName()
								+ "/"
								+ args.length
								+ "` while emitting `"
								+ rustTypeNameForClass(baseType)
								+ "Trait` for `"
								+ rustTypeNameForClass(subType)
								+ "`. This path must never emit runtime `todo!()` stubs.",
								cf.pos);
						}
						var overrideFunc = implFunc;
						var call = rustSubType + subTurbofish + "::" + rustMethodName(subType, overrideFunc.field) + "(" + callArgs.join(", ") + ")";

						var baseRetIsTrait = isInterfaceType(retTy) || isPolymorphicClassType(retTy);
						var overrideRetRust = toRustType(overrideFunc.ret, overrideFunc.field.pos);
						var overrideRetIsHxRef = rustTypeIsHxRef(overrideRetRust);

						// Covariant return types: base trait returns `HxRc<dyn BaseTrait>`, override may return
						// a concrete `HxRef<Sub>`. Upcast via `as_arc_opt()` when needed.
						if (baseRetIsTrait && overrideRetIsHxRef) {
							lines.push("\t\t{");
							lines.push("\t\t\tlet __tmp = " + call + ";");
							lines.push("\t\t\tlet __up: " + ret + " = match __tmp.as_arc_opt() {");
							lines.push("\t\t\t\tSome(__rc) => __rc.clone(),");
							lines.push("\t\t\t\tNone => { hxrt::exception::throw(hxrt::dynamic::from(String::from(\"Null Access\"))) }");
							lines.push("\t\t\t};");
							lines.push("\t\t\t__up");
							lines.push("\t\t}");
						} else {
							lines.push("\t\t" + call);
						}
						lines.push("\t}");
					}
				case _:
			}
		}

		var subMod = rustModulePathForClass(subType);
		lines.push("\tfn __hx_type_id(&self) -> u32 {");
		lines.push("\t\tcrate::" + subMod + "::__HX_TYPE_ID");
		lines.push("\t}");

		lines.push("}");
		return lines.join("\n");
	}

	function typeIdLiteralForClass(cls:ClassType):String {
		return typeIdLiteralForKey(classKey(cls));
	}

	function typeIdLiteralForEnum(en:EnumType):String {
		return typeIdLiteralForKey(enumKey(en));
	}

	/**
		Builds a typed Rust AST expression for a stable `u32` type-id value.

		Why
		- Several runtime-typing paths (`Type`/`Std.isOfType`/dynamic boxing metadata) need compile-time
		  class/enum ids as expression nodes.
		- Emitting those ids via `ERaw("0x...u32")` introduced avoidable metal fallback counts in otherwise
		  typed modules.

		How
		- Reuses the existing FNV-1a key hash and emits the canonical Rust literal form
		  (`0x????????u32`) as an expression node.
		- This preserves the exact `u32` bit pattern for both positive and negative Haxe `Int`
		  hash values without relying on `ERaw` fallback nodes.
	**/
	function typeIdExprForClass(cls:ClassType):RustExpr {
		return typeIdExprForKey(classKey(cls));
	}

	function typeIdExprForEnum(en:EnumType):RustExpr {
		return typeIdExprForKey(enumKey(en));
	}

	function typeIdExprForKey(key:String):RustExpr {
		return EPath(typeIdLiteralForKey(key));
	}

	function typeIdLiteralForKey(key:String):String {
		var id = fnv1a32(key);
		var hex = StringTools.hex(id, 8).toLowerCase();
		return "0x" + hex + "u32";
	}

	function fnv1a32(s:String):Int {
		var hash = 0x811C9DC5;
		for (i in 0...s.length) {
			hash = hash ^ s.charCodeAt(i);
			hash = hash * 0x01000193;
		}
		return hash;
	}

	function getAllInstanceVarFieldSpecsForStruct(classType:ClassType):Array<{owner:ClassType, field:ClassField}> {
		var out:Array<{owner:ClassType, field:ClassField}> = [];
		var seen = new Map<String, Bool>();

		function isPhysicalVarField(cls:ClassType, cf:ClassField):Bool {
			return varFieldHasPhysicalStorage(cls, cf);
		}

		// Walk base -> derived so field layout is deterministic.
		var chain:Array<ClassType> = [];
		var cur:Null<ClassType> = classType;
		while (cur != null) {
			chain.unshift(cur);
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}

		for (cls in chain) {
			for (cf in cls.fields.get()) {
				switch (cf.kind) {
					case FVar(_, _):
						{
							if (!isPhysicalVarField(cls, cf))
								continue;
							var name = cf.getHaxeName();
							if (seen.exists(name))
								continue;
							seen.set(name, true);
							out.push({owner: cls, field: cf});
						}
					case _:
				}
			}
		}

		return out;
	}

	function getAllInstanceVarFieldsForStruct(classType:ClassType):Array<ClassField> {
		return [for (spec in getAllInstanceVarFieldSpecsForStruct(classType)) spec.field];
	}

	function isDynamicMethodField(cf:ClassField):Bool {
		return switch (cf.kind) {
			case FMethod(MethDynamic): true;
			case _: false;
		};
	}

	function getAllInstanceDynamicMethodFieldSpecsForStorage(classType:ClassType):Array<{owner:ClassType, field:ClassField}> {
		var out:Array<{owner:ClassType, field:ClassField}> = [];
		var seen = new Map<String, Bool>();

		var chain:Array<ClassType> = [];
		var cur:Null<ClassType> = classType;
		while (cur != null) {
			chain.unshift(cur);
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}

		for (cls in chain) {
			for (cf in cls.fields.get()) {
				if (!isDynamicMethodField(cf))
					continue;
				var argc = switch (followType(cf.type)) {
					case TFun(args, _): args.length;
					case _: 0;
				};
				var key = cf.getHaxeName() + "/" + argc;
				if (seen.exists(key))
					continue;
				seen.set(key, true);
				out.push({owner: cls, field: cf});
			}
		}

		return out;
	}

	function getAllInstanceDynamicMethodFieldsForStorage(classType:ClassType):Array<ClassField> {
		return [for (spec in getAllInstanceDynamicMethodFieldSpecsForStorage(classType)) spec.field];
	}

	function rustDynamicMethodFieldName(classType:ClassType, cf:ClassField):String {
		return "__hx_dyn_" + rustMethodName(classType, cf);
	}

	function rustDynamicMethodDefaultName(classType:ClassType, cf:ClassField):String {
		return "__hx_dyn_default_" + rustMethodName(classType, cf);
	}

	function unwrapFieldFunctionBody(ex:TypedExpr):TypedExpr {
		// ClassField.expr() returns a `TFunction` for methods; we want the body expression.
		return switch (ex.expr) {
			case TFunction(fn): fn.expr;
			case _: ex;
		};
	}

	function collectInheritedInstanceMethodShims(classType:ClassType, funcFields:Array<ClassFuncData>):Array<{owner:ClassType, f:ClassFuncData}> {
		// We only need to synthesize methods that have bodies on a base class and are not
		// overridden in `classType`. This allows concrete dispatch on the subclass and
		// avoids `todo!()` stubs in base trait impls for subclasses.
		var out:Array<{owner:ClassType, f:ClassFuncData}> = [];

		var implemented:Map<String, Bool> = [];
		for (f in funcFields) {
			if (f.isStatic)
				continue;
			if (f.field.getHaxeName() == "new")
				continue;
			if (f.expr == null)
				continue;
			implemented.set(f.field.getHaxeName() + "/" + f.args.length, true);
		}

		function buildFrom(owner:ClassType, cf:ClassField, body:TypedExpr):Null<{owner:ClassType, f:ClassFuncData}> {
			var ft = followType(specializeAncestorType(classType, owner, cf.type));
			var sig = switch (ft) {
				case TFun(args, ret): {args: args, ret: ret};
				case _: null;
			};
			if (sig == null)
				return null;

			var args:Array<ClassFuncArg> = [];
			for (i in 0...sig.args.length) {
				var a = sig.args[i];
				var baseName = a.name != null && a.name.length > 0 ? a.name : ("a" + i);
				args.push(new ClassFuncArg(i, a.t, a.opt, baseName));
			}

			var kind:MethodKind = switch (cf.kind) {
				case FMethod(k): k;
				case _: MethNormal;
			};

			var id = classKey(classType) + " inherited " + classKey(owner) + " " + cf.getHaxeName() + "/" + args.length;
			var data = new ClassFuncData(id, classType, cf, false, kind, sig.ret, args, null, body, false, null);
			for (a in args)
				a.setFuncData(data);
			return {owner: owner, f: data};
		}

		// Walk nearest base first so overrides in closer bases win.
		var cur:Null<ClassType> = classType.superClass != null ? classType.superClass.t.get() : null;
		while (cur != null) {
			for (cf in cur.fields.get()) {
				if (cf.getHaxeName() == "new")
					continue;
				switch (cf.kind) {
					case FMethod(_):
						{
							var ex = cf.expr();
							if (ex == null)
								continue;
							var body = unwrapFieldFunctionBody(ex);

							var ft = followType(cf.type);
							var argc = switch (ft) {
								case TFun(args, _): args.length;
								case _: 0;
							};
							var key = cf.getHaxeName() + "/" + argc;
							if (implemented.exists(key))
								continue;

							var built = buildFrom(cur, cf, body);
							if (built != null) {
								out.push(built);
								implemented.set(key, true);
							}
						}
					case _:
				}
			}
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}

		return out;
	}

	/**
		Lowers a compound update of one typed Haxe array element.

		Why
		- `array[index]` is a get/set protocol in generated Rust, not a Rust place expression.
		- Haxe resolves the array, index, and current element before evaluating the right-hand side.
		  The RHS may mutate the same array, so reading after it would change observable behavior.
		- `String` is reusable but non-`Copy`; expression position needs separate stored and returned
		  ownership, while statement position should not pay for an unused clone.

		What
		- Supports the existing `Copy` compound operators plus typed `String` append (`+=`).
		- Rejects other non-`Copy` element operators instead of inventing runtime dispatch.

		How
		- Binds array, index, current element, and RHS exactly once in source evaluation order.
		- Computes the updated value through typed Rust operations and the existing string wrapper.
		- Clones a new String only when both the array and the enclosing Haxe expression need ownership.
	**/
	function compileArrayElementAssignOp(inner:Binop, opStr:String, element:TypedExpr, arrayExpr:TypedExpr, indexExpr:TypedExpr,
			rhsExpr:TypedExpr, fullExpr:TypedExpr, preserveResult:Bool):RustExpr {
		var stringy = inner == OpAdd
			&& (isStringType(followType(fullExpr.t))
				|| isStringType(followType(element.t))
				|| isStringType(followType(rhsExpr.t)));
		if (!isCopyType(element.t) && !stringy)
			return unsupported(fullExpr, "assignop array lvalue (non-copy)");

		var arrayName = "__hx_arr";
		var indexName = "__hx_idx";
		var currentName = "__current";
		var rhsName = "__rhs";
		var updatedName = "__tmp";
		var stmts:Array<RustStmt> = [
			RLet(arrayName, false, null, maybeCloneForReuseValue(compileExpr(arrayExpr), arrayExpr)),
			RLet(indexName, false, null, ECast(compileExpr(indexExpr), "usize")),
			RLet(currentName, false, null, ECall(EField(EPath(arrayName), "get_unchecked"), [EPath(indexName)]))
		];

		var compiledRhs = stringy ? maybeCloneForReuseValue(compileExpr(rhsExpr), rhsExpr) : compileExpr(rhsExpr);
		stmts.push(RLet(rhsName, false, null, compiledRhs));

		var updated:RustExpr;
		if (stringy) {
			var rhsString:RustExpr = isStringType(followType(rhsExpr.t)) ? EPath(rhsName) : ECall(EField(ECall(EPath("hxrt::dynamic::from"),
				[EPath(rhsName)]), "to_haxe_string"), []);
			updated = wrapRustStringExpr(EMacroCall("format", [ELitString("{}{}"), EPath(currentName), rhsString]));
		} else {
			updated = EBinary(opStr, EPath(currentName), EPath(rhsName));
		}
		stmts.push(RLet(updatedName, false, null, updated));

		var storedValue:RustExpr = stringy && preserveResult ? ECall(EField(EPath(updatedName), "clone"), []) : EPath(updatedName);
		stmts.push(RSemi(ECall(EField(EPath(arrayName), "set"), [EPath(indexName), storedValue])));
		return EBlock({stmts: stmts, tail: preserveResult ? EPath(updatedName) : null});
	}

	function compileBinop(op:Binop, e1:TypedExpr, e2:TypedExpr, fullExpr:TypedExpr):RustExpr {
		function unwrapAssignLocal(e:TypedExpr):Null<TVar> {
			var cur = unwrapMetaParen(e);
			while (true) {
				switch (cur.expr) {
					case TCast(inner, _):
						cur = unwrapMetaParen(inner);
						continue;
					case TCall(callExpr, args) if (args.length == 1):
						{
							switch (callExpr.expr) {
								case TField(_, FStatic(typeRef, cfRef)): {
										var cf = cfRef.get();
										var full = typeRef.toString();
										if (cf != null
											&& cf.name == "fromValue"
											&& (full.indexOf("rust.Ref") != -1 || full.indexOf("rust.MutRef") != -1)) {
											cur = unwrapMetaParen(args[0]);
											continue;
										}
									}
								case _:
							}
						}
					case _:
				}
				break;
			}
			return switch (cur.expr) {
				case TLocal(v): v;
				case _: null;
			};
		}

		if (op == OpAssign) {
			var lhsLocal = unwrapAssignLocal(e1);
			if (lhsLocal != null) {
				var localName = rustLocalRefIdent(lhsLocal);
				var cellBackedLocal = isCapturedCellLocal(lhsLocal) || isCapturedCellLocalName(localName);
				var writesNullOption = isNullOptionType(lhsLocal.t, e1.pos) && !isNullType(e2.t) && !isNullConstExpr(e2);

				if (writesNullOption) {
					var stmts:Array<RustStmt> = [];
					stmts.push(RLet("__tmp", false, null, compileExpr(e2)));
					var rhsVal:RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
					var wrapped = ECall(EPath("Some"), [rhsVal]);
					if (cellBackedLocal) {
						var cellWrite = EUnary("*", ECall(EField(EPath(localName), "borrow_mut"), []));
						stmts.push(RSemi(EAssign(cellWrite, wrapped)));
					} else {
						stmts.push(RSemi(EAssign(EPath(localName), wrapped)));
					}
					return EBlock({stmts: stmts, tail: EPath("__tmp")});
				}

				var rhsExpr = compileExpr(e2);
				rhsExpr = maybeCloneForReuseValue(rhsExpr, e2);
				rhsExpr = coerceExprToExpected(rhsExpr, e2, e1.t);
				if (!cellBackedLocal)
					return EAssign(EPath(localName), rhsExpr);

				var stmts:Array<RustStmt> = [];
				stmts.push(RLet("__tmp", false, null, rhsExpr));
				var writeVal = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
				var cellWrite = EUnary("*", ECall(EField(EPath(localName), "borrow_mut"), []));
				stmts.push(RSemi(EAssign(cellWrite, writeVal)));
				return EBlock({stmts: stmts, tail: EPath("__tmp")});
			}
		}

		function compileNumericOperand(e:TypedExpr):RustExpr {
			var inner = nullOptionInnerType(e.t, e.pos);
			if (inner != null) {
				var ft = followType(inner);
				if (TypeHelper.isInt(ft) || TypeHelper.isFloat(ft)) {
					return coerceExprToExpected(compileExpr(e), e, inner);
				}
			}
			return compileExpr(e);
		}

		return switch (op) {
			case OpAssign:
				switch (e1.expr) {
					case TCast(inner, _):
						// Haxe often wraps lvalues in casts during desugaring (e.g. closure-local `x++` -> `x = x + 1`).
						// Recurse on the inner lvalue so local-assignment lowering (including captured-cell locals)
						// still applies.
						compileBinop(OpAssign, inner, e2, fullExpr);
					case TLocal(v) if (isNullOptionType(v.t, e1.pos) && !isNullType(e2.t) && !isNullConstExpr(e2)): {
							// Assignment to `Null<T>` (Option<T>) from a non-null `T`:
							// `{ let __tmp = rhs; lhs = Some(__tmp.clone()); __tmp }`
							var localName = rustLocalRefIdent(v);
							var cellBackedLocal = isCapturedCellLocal(v) || isCapturedCellLocalName(localName);
							var stmts:Array<RustStmt> = [];
							stmts.push(RLet("__tmp", false, null, compileExpr(e2)));

							var rhsVal:RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
							var wrapped = ECall(EPath("Some"), [rhsVal]);
							if (cellBackedLocal) {
								var cellWrite = EUnary("*", ECall(EField(EPath(localName), "borrow_mut"), []));
								stmts.push(RSemi(EAssign(cellWrite, wrapped)));
							} else {
								stmts.push(RSemi(EAssign(compileExpr(e1), wrapped)));
							}

							return EBlock({stmts: stmts, tail: EPath("__tmp")});
						}
					case TLocal(v): {
							// Assignment into a local: coerce the RHS into the local's storage type.
							// This handles trait upcasts and structural typedef adapters (TypeResolver).
							var localName = rustLocalRefIdent(v);
							var cellBackedLocal = isCapturedCellLocal(v) || isCapturedCellLocalName(localName);
							var rhsExpr = compileExpr(e2);
							rhsExpr = maybeCloneForReuseValue(rhsExpr, e2);
							rhsExpr = coerceExprToExpected(rhsExpr, e2, e1.t);
							if (!cellBackedLocal)
								return EAssign(compileExpr(e1), rhsExpr);

							var stmts:Array<RustStmt> = [];
							stmts.push(RLet("__tmp", false, null, rhsExpr));
							var writeVal = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
							var cellWrite = EUnary("*", ECall(EField(EPath(localName), "borrow_mut"), []));
							stmts.push(RSemi(EAssign(cellWrite, writeVal)));
							return EBlock({stmts: stmts, tail: EPath("__tmp")});
						}
					case TArray(arr, index): {
							compileArrayIndexAssign(arr, index, e2);
						}
					case TField(obj, FAnon(cfRef)): {
							// Assignment into anonymous-object fields:
							// `{ let __obj = obj.clone(); let __tmp = rhs; __obj.borrow_mut().set("field", __tmp.clone()); __tmp }`
							//
							// Only supported for general anonymous objects, not iterator protocol structs.
							if (!isAnonObjectType(obj.t)) {
								var rhsExpr = compileExpr(e2);
								rhsExpr = maybeCloneForReuseValue(rhsExpr, e2);
								return EAssign(compileExpr(e1), rhsExpr);
							}

							var cf = cfRef.get();
							if (cf == null)
								return unsupported(fullExpr, "anon field assign");

							var fieldIsNullOpt = isNullOptionType(cf.type, cf.pos);
							var rhsIsNullish = isNullOptionType(e2.t, e2.pos) || isNullConstExpr(e2);

							function typedNoneForNull(t:Type, pos:haxe.macro.Expr.Position):RustExpr {
								var inner = nullOptionInnerType(t, pos);
								if (inner == null)
									return EPath("None");
								var innerRust = rustTypeToString(toRustType(inner, pos));
								return EPath("Option::<" + innerRust + ">::None");
							}

							var stmts:Array<RustStmt> = [];

							// Evaluate receiver once (and clone locals to avoid moves).
							stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));

							// Evaluate RHS before taking a mutable borrow.
							var rhsExpr = if (isNullConstExpr(e2) && fieldIsNullOpt) typedNoneForNull(cf.type,
								e2.pos) else maybeCloneForReuseValue(compileExpr(e2), e2);
							stmts.push(RLet("__tmp", false, null, rhsExpr));

							var rhsVal:RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
							var assigned = (fieldIsNullOpt && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal;

							var borrowed = ECall(EField(EPath("__obj"), "borrow_mut"), []);
							var setCall = ECall(EField(borrowed, "set"), [ELitString(cf.getHaxeName()), assigned]);
							stmts.push(RSemi(setCall));

							return EBlock({stmts: stmts, tail: EPath("__tmp")});
						}
					case TField(_, FStatic(clsRef, cfRef)): {
							// Assignment into static vars:
							// `{ let __tmp = rhs; crate::<mod>::__hx_static_set_x(__tmp.clone()); __tmp }`
							//
							// Static var reads compile to `__hx_static_get_x()` (a getter function), which is not an lvalue.
							// We must call the generated setter to mutate the static cell.
							var owner = clsRef.get();
							var cf = cfRef.get();
							if (owner == null || cf == null)
								return unsupported(fullExpr, "static var assign");
							switch (cf.kind) {
								case FVar(_, _): {
										var stmts:Array<RustStmt> = [];
										var rhsExpr = compileExpr(e2);
										rhsExpr = maybeCloneForReuseValue(rhsExpr, e2);
										stmts.push(RLet("__tmp", false, null, rhsExpr));

										var rustName = rustMethodName(owner, cf);
										var setterFn = rustStaticVarHelperName("__hx_static_set", rustName);
										var setter = staticVarHelperPath(owner, setterFn);

										var argVal:RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
										stmts.push(RSemi(ECall(EPath(setter), [argVal])));
										return EBlock({stmts: stmts, tail: EPath("__tmp")});
									}
								case _:
									// Fall back to plain assignment (likely invalid), but keep behavior explicit.
									EAssign(compileExpr(e1), compileExpr(e2));
							}
						}
					case TField(obj, FDynamic(name)): {
							// Assignment into Dynamic fields:
							// `{ let __obj = obj.clone(); let __tmp = rhs; hxrt::dynamic::field_set(&__obj, "field", <boxed>); __tmp }`
							//
							// This supports cases like:
							//   `var o:Dynamic = ...; o.x = 1;`
							var stmts:Array<RustStmt> = [];
							stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));

							var rhsExpr:RustExpr = maybeCloneForReuseValue(compileExpr(e2), e2);
							stmts.push(RLet("__tmp", false, null, rhsExpr));

							var rhsVal:RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
							var boxed:RustExpr = if (mapsToRustDynamic(e2.t, e2.pos)) {
								rhsVal;
							} else if (isNullConstExpr(e2)) {
								rustDynamicNullExpr();
							} else {
								ECall(EPath("hxrt::dynamic::from"), [rhsVal]);
							}

							stmts.push(RSemi(ECall(EPath("hxrt::dynamic::field_set"), [EUnary("&", EPath("__obj")), ELitString(name), boxed])));
							return EBlock({stmts: stmts, tail: EPath("__tmp")});
						}
					case TField(obj, FInstance(clsRef, _, cfRef)): {
							var owner = clsRef.get();
							var cf = cfRef.get();
							switch (cf.kind) {
								case FVar(_, _):
									compileInstanceFieldAssign(obj, owner, cf, e2);
								case FMethod(MethDynamic): {
										if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
											return unsupported(fullExpr, "dynamic method assign (polymorphic)");
										}
										var recvCls = if (isThisExpr(obj) && currentClassType != null) currentClassType else owner;
										var recvName = "__hx_obj";
										var recvExpr:RustExpr = isThisExpr(obj) ? currentThisPathExpr() : EPath(recvName);
										var fieldName = rustDynamicMethodFieldName(recvCls, cf);
										var stmts:Array<RustStmt> = [];
										if (!isThisExpr(obj))
											stmts.push(RLet(recvName, false, null, ECall(EField(compileExpr(obj), "clone"), [])));
										var rhsExpr = maybeCloneForReuseValue(compileExpr(e2), e2);
										stmts.push(RLet("__tmp", false, null, rhsExpr));
										stmts.push(RSemi(EAssign(EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName),
											ECall(EField(EPath("__tmp"), "clone"), []))));
										return EBlock({stmts: stmts, tail: EPath("__tmp")});
									}
								case _:
									EAssign(compileExpr(e1), compileExpr(e2));
							}
						}
					case _:
						switch (e1.expr) {
							case TLocal(v) if (v != null && v.name != null && StringTools.startsWith(v.name, "_g") && isArrayType(v.t)): {
									// Same heuristic as above for `_g*` temporaries: avoid moving arrays.
									var rhsU = unwrapMetaParen(e2);
									switch (rhsU.expr) {
										case TLocal(_):
											EAssign(compileExpr(e1), ECall(EField(compileExpr(e2), "clone"), []));
										case _:
											EAssign(compileExpr(e1), compileExpr(e2));
									}
								}
							case _:
								var rhsExpr = compileExpr(e2);
								rhsExpr = maybeCloneForReuseValue(rhsExpr, e2);
								EAssign(compileExpr(e1), rhsExpr);
						}
				}

			case OpAdd:
				var ft = followType(fullExpr.t);
				if (isStringType(ft) || isStringType(followType(e1.t)) || isStringType(followType(e2.t))) {
					// String concatenation via a single `format!` call.
					//
					// This flattens nested `a + b + c` chains into `format!("{}{}{}", a, b, c)` to avoid
					// nested `format!` calls (cleaner, more idiomatic Rust).
					//
					// Evaluation order:
					// - Haxe evaluates `+` left-to-right.
					// - Rust evaluates macro arguments left-to-right, so the flattened form preserves order.
					function collectParts(e:TypedExpr, out:Array<TypedExpr>):Void {
						var u = unwrapMetaParen(e);
						switch (u.expr) {
							case TBinop(OpAdd, a, b) if (isStringType(followType(u.t))):
								collectParts(a, out);
								collectParts(b, out);
							case _:
								out.push(e);
						}
					}

					var parts:Array<TypedExpr> = [];
					collectParts(fullExpr, parts);

					// Prefer borrowing `String`-typed values as `&String` inside `format!` to avoid
					// intermediate `String::clone()` allocations when all we need is to format into a
					// new output string.
					//
					// Additionally, emit string literals as `&'static str` (no `String::from`) inside
					// `format!` args to reduce heap allocation noise.
					function formatArg(p:TypedExpr):RustExpr {
						if (!isStringType(followType(p.t))) {
							// Haxe string concatenation stringifies non-String values (Std.string-like semantics).
							// Rust's `format!` requires `Display`, which `Option<T>` and many runtime types do not
							// implement. Route through `hxrt::dynamic::Dynamic::to_haxe_string()` for stability.
							var v = maybeCloneForReuseValue(compileExpr(p), p);
							return ECall(EField(ECall(EPath("hxrt::dynamic::from"), [v]), "to_haxe_string"), []);
						}

						function unwrapPortableDisplayExpr(expr:RustExpr):RustExpr {
							if (!useNullableStringRepresentation()) {
								return expr;
							}
							return switch (expr) {
								case ECall(EPath("hxrt::string::HxString::from"), [inner]):
									inner;
								case _:
									expr;
							}
						}

						var u = unwrapMetaParen(p);
						switch (u.expr) {
							case TConst(TString(s)):
								return ELitString(s);
							case TLocal(_):
								return EUnary("&", unwrapPortableDisplayExpr(compileExpr(p)));
							case TField(obj, FInstance(clsRef, _, cfRef)):
								{
									var owner = clsRef.get();
									var cf = cfRef.get();
									if (cf != null) {
										switch (cf.kind) {
											case FMethod(_):
												// fall through
											case _:
												// Polymorphic field reads go through getters which return owned values.
												// Borrowing those would create references to temporaries, so keep the
												// portable clone behavior here.
												if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
													return unwrapPortableDisplayExpr(compileExpr(p));
												}
												// Special-cased property-like fields (Bytes/Array length) are not `String`.
												// For plain instance `String` fields, borrow directly.
												var recv = compileExpr(obj);
												var borrowed = ECall(EField(recv, "borrow"), []);
												var access = EField(borrowed, rustFieldName(owner, cf));
												return EUnary("&", access);
										}
									}
								}
							case _:
						}

						return unwrapPortableDisplayExpr(compileExpr(p));
					}

					var fmt = "";
					for (_ in 0...parts.length)
						fmt += "{}";

					var args:Array<RustExpr> = [ELitString(fmt)];
					for (p in parts)
						args.push(formatArg(p));
					wrapRustStringExpr(EMacroCall("format", args));
				} else {
					// Mixed numeric ops: Haxe freely mixes `Int` and `Float`.
					// When the result is `Float`, coerce both sides to `f64` to satisfy Rust's typing.
					if (TypeHelper.isFloat(ft)) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("+", lhs, rhs);
					} else {
						EBinary("+", compileNumericOperand(e1), compileNumericOperand(e2));
					}
				}

			case OpSub: {
					if (TypeHelper.isFloat(followType(fullExpr.t))) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("-", lhs, rhs);
					} else {
						EBinary("-", compileNumericOperand(e1), compileNumericOperand(e2));
					}
				}
			case OpMult: {
					if (TypeHelper.isFloat(followType(fullExpr.t))) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("*", lhs, rhs);
					} else {
						EBinary("*", compileNumericOperand(e1), compileNumericOperand(e2));
					}
				}
			case OpDiv: {
					// Haxe `/` always returns `Float`.
					//
					// If both operands are `Int`, Rust `/` would perform integer division. Route through
					// `f64` so generated code matches Haxe semantics (and upstream stdlib expectations).
					if (TypeHelper.isFloat(followType(fullExpr.t))) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("/", lhs, rhs);
					} else {
						EBinary("/", compileNumericOperand(e1), compileNumericOperand(e2));
					}
				}
			case OpMod: {
					if (TypeHelper.isFloat(followType(fullExpr.t))) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("%", lhs, rhs);
					} else {
						EBinary("%", compileNumericOperand(e1), compileNumericOperand(e2));
					}
				}

			// Bitwise ops (Int).
			case OpAnd: EBinary("&", compileNumericOperand(e1), compileNumericOperand(e2));
			case OpOr: EBinary("|", compileNumericOperand(e1), compileNumericOperand(e2));
			case OpXor: EBinary("^", compileNumericOperand(e1), compileNumericOperand(e2));
			case OpShl: EBinary("<<", compileNumericOperand(e1), compileNumericOperand(e2));
			case OpShr: EBinary(">>", compileNumericOperand(e1), compileNumericOperand(e2));
			case OpUShr: {
					// Unsigned shift-right (`>>>`) uses `u32` then casts back to `i32`.
					// This matches Haxe's `Int` semantics for `>>>` (logical shift).
					var lhs = ECast(compileExpr(e1), "u32");
					var rhs = ECast(compileExpr(e2), "u32");
					ECast(EBinary(">>", lhs, rhs), "i32");
				}

			case OpEq: {
					if ((isNullConstExpr(e2) && isStrictNonNullableStringType(e1.t, e1.pos))
						|| (isNullConstExpr(e1) && isStrictNonNullableStringType(e2.t, e2.pos))) {
						// In strict non-null string contract mode, `String` cannot be null.
						// Keep comparisons valid and explicit without forcing users to rewrite common guard code.
						return ELitBool(false);
					}
					// `Null<T> == null` should not require `T: PartialEq` (e.g. `Null<Fn>`), and must
					// respect our two null representations:
					// - `Option<T>` when `Null<T>` maps to Rust `Option<T>`
					// - erased `Null<T>` when the Rust representation already has an explicit null value
					var e1NullOpt = isNullOptionType(e1.t, e1.pos);
					var e2NullOpt = isNullOptionType(e2.t, e2.pos);

					if (isNullType(e1.t) && isNullConstExpr(e2)) {
						var lhs = compileExpr(e1);
						if (e1NullOpt) {
							ECall(EField(lhs, "is_none"), []);
						} else {
							// Erased null: compare the underlying nullable value.
							switch (followType(e1.t)) {
								case TAbstract(absRef, _): {
										var abs = absRef.get();
										if (abs != null && abs.module == "StdTypes" && (abs.name == "Class" || abs.name == "Enum")) {
											return EBinary("==", lhs, ECast(ELitInt(0), "u32"));
										}
									}
								case _:
							}
							ECall(EField(lhs, "is_null"), []);
						}
					} else if (isNullType(e2.t) && isNullConstExpr(e1)) {
						var rhs = compileExpr(e2);
						if (e2NullOpt) {
							ECall(EField(rhs, "is_none"), []);
						} else {
							switch (followType(e2.t)) {
								case TAbstract(absRef, _): {
										var abs = absRef.get();
										if (abs != null && abs.module == "StdTypes" && (abs.name == "Class" || abs.name == "Enum")) {
											return EBinary("==", rhs, ECast(ELitInt(0), "u32"));
										}
									}
								case _:
							}
							ECall(EField(rhs, "is_null"), []);
						}
					} else if (e1NullOpt && !isNullType(e2.t) && !isNullConstExpr(e2)) {
						// `Option<T> == T` -> `Option<T> == Some(T)`
						var inner = nullOptionInnerType(e1.t, e1.pos);
						var rhs = maybeCloneForReuseValue(compileExpr(e2), e2);
						if (inner != null)
							rhs = coerceExprToExpected(rhs, e2, inner);
						EBinary("==", compileExpr(e1), ECall(EPath("Some"), [rhs]));
					} else if (e2NullOpt && !isNullType(e1.t) && !isNullConstExpr(e1)) {
						var inner = nullOptionInnerType(e2.t, e2.pos);
						var lhs = maybeCloneForReuseValue(compileExpr(e1), e1);
						if (inner != null)
							lhs = coerceExprToExpected(lhs, e1, inner);
						EBinary("==", ECall(EPath("Some"), [lhs]), compileExpr(e2));
					} else {
						var ft1 = followType(e1.t);
						var ft2 = followType(e2.t);
						var isDyn1 = mapsToRustDynamic(ft1, e1.pos);
						var isDyn2 = mapsToRustDynamic(ft2, e2.pos);

						// `Dynamic == null` should not require `Dynamic: PartialEq`.
						if (isDyn1 && isNullConstExpr(e2)) {
							ECall(EField(compileExpr(e1), "is_null"), []);
						} else if (isDyn2 && isNullConstExpr(e1)) {
							ECall(EField(compileExpr(e2), "is_null"), []);
						} else {
							// `Dynamic == Dynamic` (and mixed `Dynamic == T`) cannot rely on Rust `PartialEq`.
							// Route through runtime equality helpers.
							if (isDyn1 || isDyn2) {
								var dynTy = haxeDynamicBoundaryType();
								function toDynamic(te:TypedExpr, compiled:RustExpr):RustExpr {
									if (isNullConstExpr(te))
										return rustDynamicNullExpr();
									return coerceExprToExpected(compiled, te, dynTy);
								}
								var lhs = toDynamic(e1, compileExpr(e1));
								var rhs = toDynamic(e2, compileExpr(e2));
								return ECall(EPath("hxrt::dynamic::eq"), [EUnary("&", lhs), EUnary("&", rhs)]);
							}

							// Mixed numeric equality: Haxe allows comparing `Int` and `Float` freely.
							// Coerce the `Int` side to `f64` when the other side is `Float`.
							if (TypeHelper.isFloat(ft1) && TypeHelper.isInt(ft2)) {
								return EBinary("==", compileExpr(e1), ECast(compileExpr(e2), "f64"));
							} else if (TypeHelper.isInt(ft1) && TypeHelper.isFloat(ft2)) {
								return EBinary("==", ECast(compileExpr(e1), "f64"), compileExpr(e2));
							}

							// Interface/polymorphic values lower to non-null trait-object `HxRc` handles once
							// constructed/upcast. A direct comparison against the null literal must not go
							// through generic pointer equality with an untyped `Default::default()`.
							if ((isInterfaceType(ft1) || isPolymorphicClassType(ft1)) && isNullConstExpr(e2)) {
								return EBlock({stmts: [RLet("_", false, null, compileExpr(e1))], tail: ELitBool(false)});
							} else if ((isInterfaceType(ft2) || isPolymorphicClassType(ft2)) && isNullConstExpr(e1)) {
								return EBlock({stmts: [RLet("_", false, null, compileExpr(e2))], tail: ELitBool(false)});
							}

							// Haxe object/array equality is identity-based.
							if (isArrayType(ft1) && isArrayType(ft2)) {
								ECall(EField(compileExpr(e1), "ptr_eq"), [EUnary("&", compileExpr(e2))]);
							} else if (isRcBackedType(ft1) && isRcBackedType(ft2)) {
								ECall(EPath("hxrt::hxref::ptr_eq"), [EUnary("&", compileExpr(e1)), EUnary("&", compileExpr(e2))]);
							} else {
								EBinary("==", compileExpr(e1), compileExpr(e2));
							}
						}
					}
				}
			case OpNotEq: {
					if ((isNullConstExpr(e2) && isStrictNonNullableStringType(e1.t, e1.pos))
						|| (isNullConstExpr(e1) && isStrictNonNullableStringType(e2.t, e2.pos))) {
						// `String != null` is always true under strict non-null string contract.
						return ELitBool(true);
					}
					var e1NullOpt = isNullOptionType(e1.t, e1.pos);
					var e2NullOpt = isNullOptionType(e2.t, e2.pos);

					if (isNullType(e1.t) && isNullConstExpr(e2)) {
						var lhs = compileExpr(e1);
						if (e1NullOpt) {
							ECall(EField(lhs, "is_some"), []);
						} else {
							switch (followType(e1.t)) {
								case TAbstract(absRef, _): {
										var abs = absRef.get();
										if (abs != null && abs.module == "StdTypes" && (abs.name == "Class" || abs.name == "Enum")) {
											return EBinary("!=", lhs, ECast(ELitInt(0), "u32"));
										}
									}
								case _:
							}
							EUnary("!", ECall(EField(lhs, "is_null"), []));
						}
					} else if (isNullType(e2.t) && isNullConstExpr(e1)) {
						var rhs = compileExpr(e2);
						if (e2NullOpt) {
							ECall(EField(rhs, "is_some"), []);
						} else {
							switch (followType(e2.t)) {
								case TAbstract(absRef, _): {
										var abs = absRef.get();
										if (abs != null && abs.module == "StdTypes" && (abs.name == "Class" || abs.name == "Enum")) {
											return EBinary("!=", rhs, ECast(ELitInt(0), "u32"));
										}
									}
								case _:
							}
							EUnary("!", ECall(EField(rhs, "is_null"), []));
						}
					} else if (e1NullOpt && !isNullType(e2.t) && !isNullConstExpr(e2)) {
						var inner = nullOptionInnerType(e1.t, e1.pos);
						var rhs = maybeCloneForReuseValue(compileExpr(e2), e2);
						if (inner != null)
							rhs = coerceExprToExpected(rhs, e2, inner);
						EBinary("!=", compileExpr(e1), ECall(EPath("Some"), [rhs]));
					} else if (e2NullOpt && !isNullType(e1.t) && !isNullConstExpr(e1)) {
						var inner = nullOptionInnerType(e2.t, e2.pos);
						var lhs = maybeCloneForReuseValue(compileExpr(e1), e1);
						if (inner != null)
							lhs = coerceExprToExpected(lhs, e1, inner);
						EBinary("!=", ECall(EPath("Some"), [lhs]), compileExpr(e2));
					} else {
						var ft1 = followType(e1.t);
						var ft2 = followType(e2.t);
						var isDyn1 = mapsToRustDynamic(ft1, e1.pos);
						var isDyn2 = mapsToRustDynamic(ft2, e2.pos);

						if (isDyn1 && isNullConstExpr(e2)) {
							EUnary("!", ECall(EField(compileExpr(e1), "is_null"), []));
						} else if (isDyn2 && isNullConstExpr(e1)) {
							EUnary("!", ECall(EField(compileExpr(e2), "is_null"), []));
						} else {
							if (isDyn1 || isDyn2) {
								var dynTy = haxeDynamicBoundaryType();
								function toDynamic(te:TypedExpr, compiled:RustExpr):RustExpr {
									if (isNullConstExpr(te))
										return rustDynamicNullExpr();
									return coerceExprToExpected(compiled, te, dynTy);
								}
								var lhs = toDynamic(e1, compileExpr(e1));
								var rhs = toDynamic(e2, compileExpr(e2));
								return EUnary("!", ECall(EPath("hxrt::dynamic::eq"), [EUnary("&", lhs), EUnary("&", rhs)]));
							}

							// Mixed numeric inequality: Haxe allows comparing `Int` and `Float` freely.
							// Coerce the `Int` side to `f64` when the other side is `Float`.
							if (TypeHelper.isFloat(ft1) && TypeHelper.isInt(ft2)) {
								return EBinary("!=", compileExpr(e1), ECast(compileExpr(e2), "f64"));
							} else if (TypeHelper.isInt(ft1) && TypeHelper.isFloat(ft2)) {
								return EBinary("!=", ECast(compileExpr(e1), "f64"), compileExpr(e2));
							}

							if ((isInterfaceType(ft1) || isPolymorphicClassType(ft1)) && isNullConstExpr(e2)) {
								return EBlock({stmts: [RLet("_", false, null, compileExpr(e1))], tail: ELitBool(true)});
							} else if ((isInterfaceType(ft2) || isPolymorphicClassType(ft2)) && isNullConstExpr(e1)) {
								return EBlock({stmts: [RLet("_", false, null, compileExpr(e2))], tail: ELitBool(true)});
							}

							if (isArrayType(ft1) && isArrayType(ft2)) {
								EUnary("!", ECall(EField(compileExpr(e1), "ptr_eq"), [EUnary("&", compileExpr(e2))]));
							} else if (isRcBackedType(ft1) && isRcBackedType(ft2)) {
								EUnary("!", ECall(EPath("hxrt::hxref::ptr_eq"), [EUnary("&", compileExpr(e1)), EUnary("&", compileExpr(e2))]));
							} else {
								EBinary("!=", compileExpr(e1), compileExpr(e2));
							}
						}
					}
				}
			case OpLt | OpLte | OpGt | OpGte: {
					// Mixed numeric comparisons: Haxe allows comparing `Int` and `Float` freely.
					// Coerce the `Int` side to `f64` when the other side is `Float`.
					var ft1 = followType(e1.t);
					var ft2 = followType(e2.t);

					var opStr = switch (op) {
						case OpLt: "<";
						case OpLte: "<=";
						case OpGt: ">";
						case OpGte: ">=";
						case _: "<";
					};

					function nullableOrderedComparison(optExpr:TypedExpr, plainExpr:TypedExpr, optionOnLeft:Bool):Null<RustExpr> {
						var inner = nullOptionInnerType(optExpr.t, optExpr.pos);
						if (inner == null)
							return null;
						var innerFt = followType(inner);
						var plainFt = followType(plainExpr.t);
						var innerNumeric = TypeHelper.isInt(innerFt) || TypeHelper.isFloat(innerFt);
						var plainNumeric = TypeHelper.isInt(plainFt) || TypeHelper.isFloat(plainFt);
						if (!innerNumeric || !plainNumeric)
							return null;

						var optValue:RustExpr = EPath("__v");
						var plainValue:RustExpr = EPath("__hx_plain");
						if (TypeHelper.isInt(innerFt) && TypeHelper.isFloat(plainFt)) {
							optValue = ECast(optValue, "f64");
						} else if (TypeHelper.isFloat(innerFt) && TypeHelper.isInt(plainFt)) {
							plainValue = ECast(plainValue, "f64");
						}

						var comparison = optionOnLeft ? EBinary(opStr, optValue, plainValue) : EBinary(opStr, plainValue, optValue);
						var arms:Array<RustMatchArm> = [
							{pat: PTupleStruct("Some", [PBind("__v")]), expr: comparison},
							{pat: PPath("None"), expr: ELitBool(false)}
						];
						var stmts:Array<RustStmt> = [];
						if (optionOnLeft) {
							stmts.push(RLet("__hx_opt", false, null, compileExpr(optExpr)));
							stmts.push(RLet("__hx_plain", false, null, compileExpr(plainExpr)));
						} else {
							stmts.push(RLet("__hx_plain", false, null, compileExpr(plainExpr)));
							stmts.push(RLet("__hx_opt", false, null, compileExpr(optExpr)));
						}
						return EBlock({stmts: stmts, tail: EMatch(EPath("__hx_opt"), arms)});
					}

					var nullableCmp:Null<RustExpr> = null;
					if (isNullOptionType(e1.t, e1.pos) && !isNullOptionType(e2.t, e2.pos) && !isNullType(e2.t) && !isNullConstExpr(e2)) {
						nullableCmp = nullableOrderedComparison(e1, e2, true);
					} else if (isNullOptionType(e2.t, e2.pos) && !isNullOptionType(e1.t, e1.pos) && !isNullType(e1.t) && !isNullConstExpr(e1)) {
						nullableCmp = nullableOrderedComparison(e2, e1, false);
					}
					if (nullableCmp != null) {
						nullableCmp;
					} else if (TypeHelper.isFloat(ft1) && TypeHelper.isInt(ft2)) {
						EBinary(opStr, compileExpr(e1), ECast(compileExpr(e2), "f64"));
					} else if (TypeHelper.isInt(ft1) && TypeHelper.isFloat(ft2)) {
						EBinary(opStr, ECast(compileExpr(e1), "f64"), compileExpr(e2));
					} else {
						EBinary(opStr, compileExpr(e1), compileExpr(e2));
					}
				}
			case OpBoolAnd: EBinary("&&", compileExpr(e1), compileExpr(e2));
			case OpBoolOr: EBinary("||", compileExpr(e1), compileExpr(e2));

			case OpInterval:
				ERange(compileExpr(e1), compileExpr(e2));

			case OpAssignOp(inner): {
					// Compound assignments (`x += y`, `x %= y`, ...).
					//
					// Current behavior: support locals (common in loops/desugarings). More complex lvalues
					// (fields/indices) can be added when needed.
					var opStr:Null<String> = switch (inner) {
						case OpAdd: "+";
						case OpSub: "-";
						case OpMult: "*";
						case OpDiv: "/";
						case OpMod: "%";
						case OpAnd: "&";
						case OpOr: "|";
						case OpXor: "^";
						case OpShl: "<<";
						case OpShr: ">>";
						case _: null;
					}
					if (opStr == null)
						return unsupported(fullExpr, "assignop" + Std.string(inner));

					switch (e1.expr) {
						case TLocal(v): {
								var localName = rustLocalRefIdent(v);
								var cellBackedLocal = isCapturedCellLocal(v) || isCapturedCellLocalName(localName);
								// `{ x = x <op> rhs; x }`
								//
								// Special-case Strings: Rust `String` is non-Copy and `x += y` must not move out of `x`
								// (Haxe strings are reusable). Implement as `x = format!("{}{}", x, rhs); x.clone()`.
								var rhsExpr = maybeCloneForReuseValue(compileExpr(e2), e2);
								var stringy = inner == OpAdd
									&& (isStringType(followType(fullExpr.t))
										|| isStringType(followType(e1.t))
										|| isStringType(followType(e2.t)));
								if (cellBackedLocal) {
									if (stringy) {
										var rhsStr:RustExpr = isStringType(followType(e2.t)) ? EPath("__tmp") : ECall(EField(ECall(EPath("hxrt::dynamic::from"),
											[EPath("__tmp")]), "to_haxe_string"), []);
										return EBlock({
											stmts: [
												RLet("__tmp", false, null, rhsExpr),
												RLet("__b", true, null, ECall(EField(EPath(localName), "borrow_mut"), [])),
												RSemi(EAssign(EUnary("*", EPath("__b")),
													wrapRustStringExpr(EMacroCall("format", [ELitString("{}{}"), EUnary("*", EPath("__b")), rhsStr]))))
											],
											tail: ECall(EField(EUnary("*", EPath("__b")), "clone"), [])
										});
									}
									var rhs = compileExpr(e2);
									return EBlock({
										stmts: [
											RLet("__rhs", false, null, rhs),
											RLet("__b", true, null, ECall(EField(EPath(localName), "borrow_mut"), [])),
											RSemi(EAssign(EUnary("*", EPath("__b")), EBinary(opStr, EUnary("*", EPath("__b")), EPath("__rhs"))))
										],
										tail: isCopyType(e1.t) ? EUnary("*", EPath("__b")) : ECall(EField(EUnary("*", EPath("__b")), "clone"), [])
									});
								}
								var lhs = compileExpr(e1);
								if (stringy) {
									var rhsStr:RustExpr = isStringType(followType(e2.t)) ? EPath("__tmp") : ECall(EField(ECall(EPath("hxrt::dynamic::from"),
										[EPath("__tmp")]), "to_haxe_string"), []);
									EBlock({
										stmts: [
											RLet("__tmp", false, null, rhsExpr),
											RSemi(EAssign(lhs, wrapRustStringExpr(EMacroCall("format", [ELitString("{}{}"), lhs, rhsStr]))))
										],
										tail: ECall(EField(lhs, "clone"), [])
									});
								} else {
									var rhs = compileExpr(e2);
									EBlock({
										stmts: [RSemi(EAssign(lhs, EBinary(opStr, lhs, rhs)))],
										tail: lhs
									});
								}
							}
						case TField(_, FDynamic(_)):
							return unsupportedDynamicFieldOperator(fullExpr, "compound assignment");
						case TField(_, FStatic(clsRef, cfRef)): {
								var owner = clsRef.get();
								var cf = cfRef.get();
								if (owner == null || cf == null)
									return unsupported(fullExpr, "assignop static field lvalue");
								switch (cf.kind) {
									case FVar(_, _):
									case _:
										return unsupported(fullExpr, "assignop static field lvalue");
								}

								var stringy = inner == OpAdd
									&& (isStringType(followType(fullExpr.t))
										|| isStringType(followType(e1.t))
										|| isStringType(followType(e2.t)));
								if (!isCopyType(e1.t) && !stringy)
									return unsupported(fullExpr, "assignop static field lvalue (non-copy)");

								// Why: generated static reads are getter calls, so they are not Rust lvalues.
								// What: preserve Haxe read/compute/write and assigned-value semantics for static updates.
								// How: capture the current value before the RHS can mutate the same static, then call the
								// existing typed setter with the computed result.
								var rustName = rustMethodName(owner, cf);
								var getter = staticVarHelperPath(owner, rustStaticVarHelperName("__hx_static_get", rustName));
								var setter = staticVarHelperPath(owner, rustStaticVarHelperName("__hx_static_set", rustName));
								var rhsExpr = maybeCloneForReuseValue(compileExpr(e2), e2);
								var stmts:Array<RustStmt> = [
									RLet("__current", false, null, ECall(EPath(getter), [])),
									RLet("__rhs", false, null, rhsExpr)
								];
								var updated:RustExpr;
								if (stringy) {
									var rhsStr:RustExpr = isStringType(followType(e2.t)) ? EPath("__rhs") : ECall(EField(ECall(EPath("hxrt::dynamic::from"),
										[EPath("__rhs")]), "to_haxe_string"), []);
									updated = wrapRustStringExpr(EMacroCall("format", [ELitString("{}{}"), EPath("__current"), rhsStr]));
								} else {
									updated = EBinary(opStr, EPath("__current"), EPath("__rhs"));
								}
								stmts.push(RLet("__tmp", false, null, updated));
								var setterValue:RustExpr = stringy ? ECall(EField(EPath("__tmp"), "clone"), []) : EPath("__tmp");
								stmts.push(RSemi(ECall(EPath(setter), [setterValue])));
								return EBlock({stmts: stmts, tail: EPath("__tmp")});
							}
						case TArray(arr, index): {
								compileArrayElementAssignOp(inner, opStr, e1, arr, index, e2, fullExpr, true);
							}
						case TField(obj, FInstance(clsRef, _, cfRef)): {
								// Compound assignment on a concrete instance field: `obj.field <op>= rhs`.
								//
								// Like field ++/--, we must avoid overlapping `RefCell` borrows. Compound assignment
								// additionally requires Haxe order: receiver -> current value -> RHS -> write.
								var owner = clsRef.get();
								var cf = cfRef.get();
								switch (cf.kind) {
									case FVar(_, _): {
											var stringy = inner == OpAdd
												&& (isStringType(followType(fullExpr.t))
													|| isStringType(followType(e1.t))
													|| isStringType(followType(e2.t)));
											if (!isCopyType(e1.t) && !stringy) {
												return unsupported(fullExpr, "assignop field lvalue (non-copy)");
											}

											var read:Null<VarAccess> = null;
											var write:Null<VarAccess> = null;
											switch (cf.kind) {
												case FVar(r, w):
													read = r;
													write = w;
												case _:
											}

											function receiverClassForField(obj:TypedExpr, fallback:ClassType):ClassType {
												if (isThisExpr(obj) && currentClassType != null)
													return currentClassType;
												return switch (followType(obj.t)) {
													case TInst(cls2Ref, _): {
															var cls2 = cls2Ref.get();
															cls2 != null ? cls2 : fallback;
														}
													case _: fallback;
												}
											}

											function findInstanceMethodInChain(start:ClassType, haxeName:String):Null<ClassField> {
												var cur:Null<ClassType> = start;
												while (cur != null) {
													for (f in cur.fields.get()) {
														if (f.getHaxeName() != haxeName)
															continue;
														switch (f.kind) {
															case FMethod(_):
																return f;
															case _:
														}
													}
													cur = cur.superClass != null ? cur.superClass.t.get() : null;
												}
												return null;
											}

											function getterCall(recvCls:ClassType, recvExpr:RustExpr):RustExpr {
												var propName = cf.getHaxeName();
												if (propName == null)
													return unsupported(fullExpr, "assignop property read (missing name)");
												var getter = findInstanceMethodInChain(recvCls, "get_" + propName);
												if (getter == null)
													return unsupported(fullExpr, "assignop property read (missing getter)");
												if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
													return ECall(EField(recvExpr, rustMethodName(recvCls, getter)), []);
												}
												var modName = rustModulePathForClass(recvCls);
												var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, getter);
												return ECall(EPath(path), [EUnary("&", recvExpr)]);
											}

											function setterCall(recvCls:ClassType, recvExpr:RustExpr, value:RustExpr):RustExpr {
												var propName = cf.getHaxeName();
												if (propName == null)
													return unsupported(fullExpr, "assignop property write (missing name)");
												var setter = findInstanceMethodInChain(recvCls, "set_" + propName);
												if (setter == null)
													return unsupported(fullExpr, "assignop property write (missing setter)");
												if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
													return ECall(EField(recvExpr, rustMethodName(recvCls, setter)), [value]);
												}
												var modName = rustModulePathForClass(recvCls);
												var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
												return ECall(EPath(path), [EUnary("&", recvExpr), value]);
											}

											var recvName = "__hx_obj";
											var recvExpr:RustExpr = isThisExpr(obj) ? currentThisPathExpr() : EPath(recvName);

											var fieldName = rustFieldName(owner, cf);
											var currentName = "__current";
											var rhsName = "__rhs";
											var tmpName = "__tmp";

											var stmts:Array<RustStmt> = [];
											if (!isThisExpr(obj)) {
												// Evaluate receiver once and keep it alive across borrows.
												var base = compileExpr(obj);
												stmts.push(RLet(recvName, false, null, ECall(EField(base, "clone"), [])));
											}

											function stringAssignOpValue(currentValue:RustExpr):RustExpr {
												var rhsStr:RustExpr = isStringType(followType(e2.t)) ? EPath(rhsName) : ECall(EField(ECall(EPath("hxrt::dynamic::from"),
													[EPath(rhsName)]), "to_haxe_string"), []);
												return wrapRustStringExpr(EMacroCall("format", [ELitString("{}{}"), currentValue, rhsStr]));
											}

											// Why: a base-typed trait object does not expose the concrete child's physical fields.
											// What: treat that raw field like an accessor-backed property for compound updates.
											// How: use the same generated typed getter/setter methods as ordinary polymorphic field access.
											var polymorphicField = !isThisExpr(obj) && isPolymorphicClassType(obj.t);
											var usesAccessors = (read == AccCall) || (write == AccCall) || polymorphicField;
											var recvCls = receiverClassForField(obj, owner);

											/**
												Identifies the deliberately tiny effect-free RHS set for String field append.

												Why
												- A general RHS call may mutate the same field, requiring an owned pre-RHS snapshot.
												- Cloning the entire current String is unnecessary when the RHS is only a value read.

												What
												- Admits constants, locals, and transparent casts around them.
												- Rejects calls, field reads, operators, and every other form conservatively.

												How
												- The admitted RHS may be bound before borrowing the field because it cannot mutate the
												  receiver; formatting then borrows the current field without a full String clone.
											**/
											function rhsIsTriviallyEffectFree(expr:TypedExpr):Bool {
												var current = unwrapMetaParen(expr);
												return switch (current.expr) {
													case TConst(_) | TLocal(_): true;
													case TCast(inner, _): rhsIsTriviallyEffectFree(inner);
													case _: false;
												};
											}
											var borrowStringAfterRhs = stringy && read != AccCall && !polymorphicField && rhsIsTriviallyEffectFree(e2);

											var rhsExpr = stringy ? maybeCloneForReuseValue(compileExpr(e2), e2) : compileExpr(e2);
											if (borrowStringAfterRhs) {
												stmts.push(RLet(rhsName, false, null, rhsExpr));
												var borrowedUpdate = EBlock({
													stmts: [RLet("__b", false, null, ECall(EField(recvExpr, "borrow"), []))],
													tail: stringAssignOpValue(EUnary("&", EField(EPath("__b"), fieldName)))
												});
												stmts.push(RLet(tmpName, false, null, borrowedUpdate));
											} else {
												// Capture an owned current value before evaluating the RHS. The scoped raw-field borrow
												// ends inside this initializer, so user code in the RHS never runs under a read lock.
												var currentValue:RustExpr;
												if (read == AccCall) {
													currentValue = getterCall(recvCls, recvExpr);
												} else if (polymorphicField) {
													currentValue = ECall(EField(recvExpr, rustGetterName(owner, cf)), []);
												} else {
													var rawField = EField(EPath("__b"), fieldName);
													var ownedField:RustExpr = stringy ? ECall(EField(rawField, "clone"), []) : rawField;
													currentValue = EBlock({
														stmts: [RLet("__b", false, null, ECall(EField(recvExpr, "borrow"), []))],
														tail: ownedField
													});
												}
												stmts.push(RLet(currentName, false, null, currentValue));
												stmts.push(RLet(rhsName, false, null, rhsExpr));
												var tmpExpr:RustExpr = stringy ? stringAssignOpValue(EPath(currentName)) : EBinary(opStr, EPath(currentName), EPath(rhsName));
												stmts.push(RLet(tmpName, false, null, tmpExpr));
											}

											if (usesAccessors) {
												var setterValue:RustExpr = stringy ? ECall(EField(EPath(tmpName), "clone"), []) : EPath(tmpName);
												var assigned = if (write == AccCall) setterCall(recvCls, recvExpr, setterValue) else if (polymorphicField) EBlock({
													stmts: [RSemi(ECall(EField(recvExpr, rustSetterName(owner, cf)), [setterValue]))],
													tail: EPath(tmpName)
												}) else EBlock({
													stmts: [
														RSemi(EAssign(EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName), setterValue))
													],
													tail: EPath(tmpName)
												});
												stmts.push(RLet("__assigned", false, null, assigned));
												return EBlock({stmts: stmts, tail: EPath("__assigned")});
											} else {
												var writeField = EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName);
												var writeValue:RustExpr = stringy ? ECall(EField(EPath(tmpName), "clone"), []) : EPath(tmpName);
												stmts.push(RSemi(EAssign(writeField, writeValue)));

												return EBlock({stmts: stmts, tail: EPath(tmpName)});
											}
										}
									case _:
										unsupported(fullExpr, "assignop field lvalue");
								}
							}
						case TField(obj, FAnon(cfRef)): {
								// Compound assignment on an anonymous-object field: `obj.field <op>= rhs`.
								//
								// Preserve Haxe order (object -> current value -> RHS) without holding an anonymous
								// object borrow across user code in the RHS.
								if (!isAnonObjectType(obj.t)) {
									return unsupported(fullExpr, "assignop anon field lvalue (non-anon)");
								}
								if (!isCopyType(e1.t)) {
									return unsupported(fullExpr, "assignop anon field lvalue (non-copy)");
								}

								var cf = cfRef.get();
								if (cf == null)
									return unsupported(fullExpr, "assignop anon field lvalue (missing field)");
								var fieldName = cf.getHaxeName();

								var recvName = "__hx_obj";
								var rhsName = "__rhs";
								var tmpName = "__tmp";

								var stmts:Array<RustStmt> = [];
								stmts.push(RLet(recvName, false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));

								var tyStr = rustTypeToString(toRustType(cf.type, fullExpr.pos));
								var borrowRead = ECall(EField(EPath(recvName), "borrow"), []);
								var getter = "get::<" + tyStr + ">";
								var read = ECall(EField(borrowRead, getter), [ELitString(fieldName)]);
								stmts.push(RLet("__current", false, null, read));
								stmts.push(RLet(rhsName, false, null, compileExpr(e2)));
								stmts.push(RLet(tmpName, false, null, EBinary(opStr, EPath("__current"), EPath(rhsName))));

								var borrowWrite = ECall(EField(EPath(recvName), "borrow_mut"), []);
								var setCall = ECall(EField(borrowWrite, "set"), [ELitString(fieldName), EPath(tmpName)]);
								stmts.push(RSemi(setCall));

								EBlock({stmts: stmts, tail: EPath(tmpName)});
							}
						case _:
							unsupported(fullExpr, "assignop lvalue");
					}
				}

			default:
				unsupported(fullExpr, "binop" + Std.string(op));
		}
	}

	function compileUnop(op:Unop, postFix:Bool, expr:TypedExpr, fullExpr:TypedExpr):RustExpr {
		if (op == OpIncrement || op == OpDecrement) {
			// Current behavior: support ++/-- for locals, array elements, static fields, and instance fields.
			return switch (expr.expr) {
				case TLocal(v): {
						var name = rustLocalRefIdent(v);
						var delta:RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
						var binop = (op == OpIncrement) ? "+" : "-";
						var cellBackedLocal = isCapturedCellLocal(v) || isCapturedCellLocalName(name);
						if (cellBackedLocal) {
							// Captured+mutated locals are stored in `HxRef<T>`. ++/-- must mutate through the
							// shared cell so closures and outer scopes observe the same value.
							if (postFix) {
								return EBlock({
									stmts: [
										RLet("__b", true, null, ECall(EField(EPath(name), "borrow_mut"), [])),
										RLet("__old", false, null, EUnary("*", EPath("__b"))),
										RSemi(EAssign(EUnary("*", EPath("__b")), EBinary(binop, EPath("__old"), delta)))
									],
									tail: EPath("__old")
								});
							}
							return EBlock({
								stmts: [
									RLet("__b", true, null, ECall(EField(EPath(name), "borrow_mut"), [])),
									RSemi(EAssign(EUnary("*", EPath("__b")), EBinary(binop, EUnary("*", EPath("__b")), delta)))
								],
								tail: EUnary("*", EPath("__b"))
							});
						}
						if (postFix) {
							EBlock({
								stmts: [RLet("__next", false, null, EBinary(binop, EPath(name), delta))],
								// Use `std::mem::replace` for postfix locals to avoid Rust
								// `unused_assignments` warnings when the incremented value is not read later.
								tail: ECall(EPath("std::mem::replace"), [EUnary("&mut ", EPath(name)), EPath("__next")])
							});
						} else {
							EBlock({
								stmts: [RSemi(EAssign(EPath(name), EBinary(binop, EPath(name), delta)))],
								tail: EPath(name)
							});
						}
					}

				case TField(_, FStatic(clsRef, cfRef)): {
						var owner = clsRef.get();
						var cf = cfRef.get();
						if (owner == null || cf == null || !isCopyType(expr.t))
							return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " static field unop");
						switch (cf.kind) {
							case FVar(_, _):
							case _:
								return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " static field unop");
						}

						// Why: the lazy static cell is intentionally hidden behind generated functions.
						// What: preserve Haxe's old-value postfix and new-value prefix results.
						// How: read once through the getter, compute directly, and write once through the setter.
						var rustName = rustMethodName(owner, cf);
						var getter = staticVarHelperPath(owner, rustStaticVarHelperName("__hx_static_get", rustName));
						var setter = staticVarHelperPath(owner, rustStaticVarHelperName("__hx_static_set", rustName));
						var delta:RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
						var binop = (op == OpIncrement) ? "+" : "-";
						var stmts:Array<RustStmt> = [];
						if (postFix) {
							stmts.push(RLet("__old", false, null, ECall(EPath(getter), [])));
							stmts.push(RLet("__new", false, null, EBinary(binop, EPath("__old"), delta)));
							stmts.push(RSemi(ECall(EPath(setter), [EPath("__new")])));
							return EBlock({stmts: stmts, tail: EPath("__old")});
						}
						stmts.push(RLet("__new", false, null, EBinary(binop, ECall(EPath(getter), []), delta)));
						stmts.push(RSemi(ECall(EPath(setter), [EPath("__new")])));
						return EBlock({stmts: stmts, tail: EPath("__new")});
					}

				case TArray(arr, index): {
						if (!isCopyType(expr.t))
							return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " array element unop (non-copy)");

						// Why: an Array element access is a get operation, not a Rust place expression.
						// What: preserve Haxe's single-evaluation and old/new result contract for array ++/--.
						// How: bind array then index once, read through the existing typed array API, and write once.
						var arrName = "__hx_arr";
						var idxName = "__hx_idx";
						var delta:RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
						var binop = (op == OpIncrement) ? "+" : "-";
						var stmts:Array<RustStmt> = [
							RLet(arrName, false, null, maybeCloneForReuseValue(compileExpr(arr), arr)),
							RLet(idxName, false, null, ECast(compileExpr(index), "usize"))
						];
						var read = ECall(EField(EPath(arrName), "get_unchecked"), [EPath(idxName)]);
						if (postFix) {
							stmts.push(RLet("__old", false, null, read));
							stmts.push(RLet("__new", false, null, EBinary(binop, EPath("__old"), delta)));
							stmts.push(RSemi(ECall(EField(EPath(arrName), "set"), [EPath(idxName), EPath("__new")])));
							return EBlock({stmts: stmts, tail: EPath("__old")});
						}
						stmts.push(RLet("__new", false, null, EBinary(binop, read, delta)));
						stmts.push(RSemi(ECall(EField(EPath(arrName), "set"), [EPath(idxName), EPath("__new")])));
						return EBlock({stmts: stmts, tail: EPath("__new")});
					}

				case TField(obj, FInstance(clsRef, _, cfRef)): {
						var owner = clsRef.get();
						var cf = cfRef.get();
						switch (cf.kind) {
							case FVar(_, _): {
									// Properties (`var x(get,set)` / mixed `default,set`) must go through accessors.
									var read:Null<VarAccess> = null;
									var write:Null<VarAccess> = null;
									switch (cf.kind) {
										case FVar(r, w):
											read = r;
											write = w;
										case _:
									}

									function receiverClassForField(obj:TypedExpr, fallback:ClassType):ClassType {
										if (isThisExpr(obj) && currentClassType != null)
											return currentClassType;
										return switch (followType(obj.t)) {
											case TInst(cls2Ref, _): {
													var cls2 = cls2Ref.get();
													cls2 != null ? cls2 : fallback;
												}
											case _: fallback;
										}
									}

									function findInstanceMethodInChain(start:ClassType, haxeName:String):Null<ClassField> {
										var cur:Null<ClassType> = start;
										while (cur != null) {
											for (f in cur.fields.get()) {
												if (f.getHaxeName() != haxeName)
													continue;
												switch (f.kind) {
													case FMethod(_):
														return f;
													case _:
												}
											}
											cur = cur.superClass != null ? cur.superClass.t.get() : null;
										}
										return null;
									}

									function readValue(recvCls:ClassType, recvExpr:RustExpr):RustExpr {
										if (read == AccCall) {
											var propName = cf.getHaxeName();
											if (propName == null)
												return unsupported(fullExpr, "property unop read (missing name)");
											var getter = findInstanceMethodInChain(recvCls, "get_" + propName);
											if (getter == null)
												return unsupported(fullExpr, "property unop read (missing getter)");
											if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
												return ECall(EField(recvExpr, rustMethodName(recvCls, getter)), []);
											}
											var modName = rustModulePathForClass(recvCls);
											var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, getter);
											return ECall(EPath(path), [EUnary("&", recvExpr)]);
										}
										if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
											return ECall(EField(recvExpr, rustGetterName(owner, cf)), []);
										}
										var fieldName = rustFieldName(owner, cf);
										return EField(ECall(EField(recvExpr, "borrow"), []), fieldName);
									}

									function writeValue(recvCls:ClassType, recvExpr:RustExpr, value:RustExpr):RustExpr {
										if (write == AccCall) {
											var propName = cf.getHaxeName();
											if (propName == null)
												return unsupported(fullExpr, "property unop write (missing name)");
											var setter = findInstanceMethodInChain(recvCls, "set_" + propName);
											if (setter == null)
												return unsupported(fullExpr, "property unop write (missing setter)");
											if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
												return ECall(EField(recvExpr, rustMethodName(recvCls, setter)), [value]);
											}
											var modName = rustModulePathForClass(recvCls);
											var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
											return ECall(EPath(path), [EUnary("&", recvExpr), value]);
										}
										if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
											return EBlock({
												stmts: [RSemi(ECall(EField(recvExpr, rustSetterName(owner, cf)), [value]))],
												tail: value
											});
										}
										var fieldName = rustFieldName(owner, cf);
										var writeField = EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName);
										return EBlock({stmts: [RSemi(EAssign(writeField, value))], tail: value});
									}

									// Why: a polymorphic field is reachable only through the generated trait surface.
									// What: use the property-shaped update path for raw polymorphic numeric fields too.
									// How: read and write through the existing getter/setter while preserving prefix/postfix results.
									var usesAccessors = (read == AccCall) || (write == AccCall)
										|| (!isThisExpr(obj) && isPolymorphicClassType(obj.t));
									if (usesAccessors) {
										if (!isCopyType(expr.t)) {
											return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " property unop (non-copy)");
										}

										var recvCls = receiverClassForField(obj, owner);
										var recvName = "__hx_obj";
										var recvExpr:RustExpr = isThisExpr(obj) ? currentThisPathExpr() : EPath(recvName);
										var delta:RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
										var binop = (op == OpIncrement) ? "+" : "-";

										var stmts:Array<RustStmt> = [];
										if (!isThisExpr(obj)) {
											var base = compileExpr(obj);
											stmts.push(RLet(recvName, false, null, ECall(EField(base, "clone"), [])));
										}

										if (postFix) {
											stmts.push(RLet("__tmp", false, null, readValue(recvCls, recvExpr)));
											stmts.push(RLet("__new", false, null, EBinary(binop, EPath("__tmp"), delta)));
											stmts.push(RLet("_", false, null, writeValue(recvCls, recvExpr, EPath("__new"))));
											return EBlock({stmts: stmts, tail: EPath("__tmp")});
										} else {
											stmts.push(RLet("__new", false, null, EBinary(binop, readValue(recvCls, recvExpr), delta)));
											stmts.push(RLet("__tmp", false, null, writeValue(recvCls, recvExpr, EPath("__new"))));
											return EBlock({stmts: stmts, tail: EPath("__tmp")});
										}
									}

									// Support ++/-- on instance fields:
									// - `obj.field++` returns old value
									// - `++obj.field` returns new value
									//
									// For `RefCell`-backed instances we must avoid overlapping borrows:
									// read (borrow) -> compute -> write (borrow_mut).

									var recvName = "__hx_obj";
									var recvExpr:RustExpr = if (isThisExpr(obj)) {
										EPath("self_");
									} else {
										EPath(recvName);
									}

									var fieldName = rustFieldName(owner, cf);
									var delta:RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
									var binop = (op == OpIncrement) ? "+" : "-";

									var borrowRead = ECall(EField(recvExpr, "borrow"), []);
									var readField = EField(borrowRead, fieldName);

									var stmts:Array<RustStmt> = [];
									if (!isThisExpr(obj)) {
										// Evaluate receiver once and keep it alive for both borrows.
										var base = compileExpr(obj);
										stmts.push(RLet(recvName, false, null, ECall(EField(base, "clone"), [])));
									}

									if (postFix) {
										stmts.push(RLet("__tmp", false, null, readField));
										var borrowWrite = ECall(EField(recvExpr, "borrow_mut"), []);
										var writeField = EField(borrowWrite, fieldName);
										stmts.push(RSemi(EAssign(writeField, EBinary(binop, EPath("__tmp"), delta))));
										return EBlock({stmts: stmts, tail: EPath("__tmp")});
									} else {
										stmts.push(RLet("__tmp", false, null, EBinary(binop, readField, delta)));
										var borrowWrite = ECall(EField(recvExpr, "borrow_mut"), []);
										var writeField = EField(borrowWrite, fieldName);
										stmts.push(RSemi(EAssign(writeField, EPath("__tmp"))));
										return EBlock({stmts: stmts, tail: EPath("__tmp")});
									}
								}
							case _:
								unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " field unop");
						}
					}
				case TField(_, FDynamic(_)):
					return unsupportedDynamicFieldOperator(fullExpr, postFix ? "postfix update" : "prefix update");

				case TField(obj, FAnon(cfRef)): {
						// Support ++/-- on anonymous-object fields (Copy types only).
						if (!isAnonObjectType(obj.t)) {
							return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " anon field unop (non-anon)");
						}
						if (!isCopyType(expr.t)) {
							return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " anon field unop (non-copy)");
						}

						var cf = cfRef.get();
						if (cf == null)
							return unsupported(fullExpr, "anon field unop (missing field)");
						var fieldName = cf.getHaxeName();

						var recvName = "__hx_obj";
						var tyStr = rustTypeToString(toRustType(cf.type, fullExpr.pos));
						var getter = "get::<" + tyStr + ">";

						var delta:RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
						var binop = (op == OpIncrement) ? "+" : "-";

						var stmts:Array<RustStmt> = [];
						stmts.push(RLet(recvName, false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));

						function readField():RustExpr {
							var borrowRead = ECall(EField(EPath(recvName), "borrow"), []);
							return ECall(EField(borrowRead, getter), [ELitString(fieldName)]);
						}

						function writeField(value:RustExpr):RustStmt {
							var borrowWrite = ECall(EField(EPath(recvName), "borrow_mut"), []);
							return RSemi(ECall(EField(borrowWrite, "set"), [ELitString(fieldName), value]));
						}

						if (postFix) {
							stmts.push(RLet("__tmp", false, null, readField()));
							stmts.push(RLet("__new", false, null, EBinary(binop, EPath("__tmp"), delta)));
							stmts.push(writeField(EPath("__new")));
							return EBlock({stmts: stmts, tail: EPath("__tmp")});
						} else {
							stmts.push(RLet("__tmp", false, null, EBinary(binop, readField(), delta)));
							stmts.push(writeField(EPath("__tmp")));
							return EBlock({stmts: stmts, tail: EPath("__tmp")});
						}
					}

				case _:
					unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " unop");
			}
		}

		if (postFix) {
			return unsupported(fullExpr, "postfix unop");
		}

		return switch (op) {
			case OpNot: EUnary("!", compileExpr(expr));
			case OpNeg: EUnary("-", compileExpr(expr));
			case OpNegBits: EUnary("!", compileExpr(expr));
			default: unsupported(fullExpr, "unop" + Std.string(op));
		}
	}

	function followType(t:Type):Type {
		#if eval
		return Context.followWithAbstracts(TypeTools.follow(t));
		#else
		return TypeTools.follow(t);
		#end
	}

	function isStringType(t:Type):Bool {
		var ft = followType(t);
		if (TypeHelper.isString(ft))
			return true;
		var direct = switch (ft) {
			case TInst(clsRef, []): {
					var cls = clsRef.get();
					var isCoreStringName = cls.name == "String" && cls.pack.length == 0;
					var isCoreStringModule = cls.module == "String" || cls.module == "StdTypes";
					var nativePath = rustExternBasePath(cls);
					var isNativeCoreString = nativePath == "String";
					isCoreStringName && (isCoreStringModule || isNativeCoreString)
					;
				}
			case TType(typeRef, _): {
					var tt = typeRef.get();
					tt != null && tt.name == "String"
					;
				}
			case TAbstract(absRef, []): {
					var abs = absRef.get();
					abs.module == "StdTypes" && abs.name == "String"
					;
				}
			case _: false;
		};
		if (direct)
			return true;
		#if eval
		var printed = TypeTools.toString(ft);
		if (printed == "String" || printed == "StdTypes.String")
			return true;
		#end
		return false;
	}

	function unsupported(e:TypedExpr, what:String):RustExpr {
		#if eval
		Context.error('Unsupported $what for Rust target: ' + Std.string(e.expr), e.pos);
		#end
		return ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, e.pos));
	}

	/**
		Reports the admitted boundary for operators on fields reached through `Dynamic`.

		Why
		- A Dynamic field read carries no compile-time `Int`, `Float`, or `String` payload kind.
		- Guessing from the right-hand side would silently change Haxe behavior; general runtime
		  operator dispatch is deliberately outside the current contract.

		What
		- Emits one stable error identifier for compound assignment and prefix/postfix updates.
		- Leaves ordinary Dynamic field get/set behavior unchanged.

		How
		- Anchor the diagnostic at the complete user expression and direct callers back to a typed
		  boundary: decode, update the concrete value, then write it back explicitly.
	**/
	function unsupportedDynamicFieldOperator(e:TypedExpr, operation:String):RustExpr {
		#if eval
		RustDiagnostic.error(RustDiagnosticId.DynamicFieldOperator,
			"Dynamic field " + operation
			+ " requires runtime payload-kind dispatch and is not supported. Decode the field to `Int`, `Float`, or `String`, perform the update, then write it back explicitly.",
			e.pos);
		#end
		return ERaw(RustRawCode.compilerAt("todo!()", RawUnsupportedFallback, e.pos));
	}

	function rustTraitObjectType(primaryTrait:RustPath, ?extraLifetime:RustLifetime):RustType {
		var bounds:Array<RustGenericBound> = [
			GenericTraitBound(primaryTrait, TraitBoundRequired),
			GenericTraitBound(RustPath.single("Send"), TraitBoundRequired),
			GenericTraitBound(RustPath.single("Sync"), TraitBoundRequired)
		];
		if (extraLifetime != null)
			bounds.push(GenericLifetimeBound(extraLifetime));
		return RTraitObject(RustTraitObject.of(bounds));
	}

	function rustFunctionTraitObjectType(argumentTypes:Array<RustType>, returnType:Null<RustType>, ?extraLifetime:RustLifetime):RustType {
		var fnPath = RustPath.relative([RustPathSegment.parenthesized("Fn", argumentTypes, returnType)]);
		return rustTraitObjectType(fnPath, extraLifetime);
	}

	function traitObjectRustType(t:Type, pos:haxe.macro.Expr.Position):Null<RustType> {
		return switch (followType(t)) {
			case TInst(clsRef, params): {
					var cls = clsRef.get();
					if (cls == null || cls.isExtern) {
						null;
					} else {
						var traitName = if (cls.isInterface) {
							rustTypeNameForClass(cls);
						} else if (classHasSubclasses(cls)) {
							rustTypeNameForClass(cls) + "Trait";
						} else {
							return null;
						}
						var names = rustModuleSegmentsForClass(cls);
						names.push(traitName);
						var arguments = params == null ? [] : rustTypeArguments([for (parameter in params) toRustType(parameter, pos)]);
						rustTraitObjectType(rustCratePath(names, arguments));
					}
				}
			case _:
				null;
		}
	}

	function traitObjectRustInnerPath(t:Type, pos:haxe.macro.Expr.Position):Null<String> {
		var type = traitObjectRustType(t, pos);
		return type == null ? null : rustTypeToString(type);
	}

	function dynRefTraitObjectRustType(t:Type, pos:haxe.macro.Expr.Position):Null<RustType> {
		var inner = traitObjectRustType(t, pos);
		return inner == null ? null : rustDynRefType(inner);
	}

	function dynRefNullExprForTraitObject(t:Type, pos:haxe.macro.Expr.Position):Null<RustExpr> {
		var inner = traitObjectRustInnerPath(t, pos);
		return inner == null ? null : ECall(EPath(dynRefBasePath() + "::<" + inner + ">::null"), []);
	}

	function nullableTraitObjectInnerType(t:Type, pos:haxe.macro.Expr.Position):Null<Type> {
		var inner = nullInnerType(t);
		if (inner == null)
			return null;
		var innerType:Type = inner;
		while (true) {
			var n = nullInnerType(innerType);
			if (n == null)
				break;
			innerType = n;
		}
		return traitObjectRustInnerPath(innerType, pos) == null ? null : innerType;
	}

	function toRustType(t:Type, pos:haxe.macro.Expr.Position):reflaxe.rust.ast.RustAST.RustType {
		// Inherited bodies retain their owner's type parameters in the typed AST. Specialize those
		// parameters for the concrete class currently being emitted before any Rust representation
		// decision (including raw Null<T> handling) observes the type.
		t = specializeCurrentMethodType(t);

		// Haxe `Null<T>` in Rust output is represented by `Option<T>` *unless* the chosen Rust
		// representation already has an explicit null sentinel.
		//
		// IMPORTANT: detect this on the *raw* type before `TypeTools.follow` potentially erases the
		// wrapper (some follow variants will eagerly follow abstracts).
		switch (t) {
			case TAbstract(absRef, params):
				{
					var abs = absRef.get();
					if (abs != null && abs.module == "StdTypes" && abs.name == "Null" && params.length == 1) {
						// Collapse nested nullability (`Null<Null<T>>` == `Null<T>` in practice).
						var innerType:Type = params[0];
						while (true) {
							var n = nullInnerType(innerType);
							if (n == null)
								break;
							innerType = n;
						}
						var inner = toRustType(innerType, pos);

						// Interface and polymorphic class trait objects need an explicit null sentinel
						// when the Haxe type is `Null<T>`. A bare `HxRc<dyn Trait>` cannot represent
						// null and does not implement `Default`.
						var dynRefTraitObject = dynRefTraitObjectRustType(innerType, pos);
						if (dynRefTraitObject != null) {
							return dynRefTraitObject;
						}

						// Some Rust representations already have an explicit null value (no extra `Option<...>` needed).
						// `Dynamic` already carries its own null sentinel (`Dynamic::null()`).
						if (rustTypeIsDynamicCarrier(inner)) {
							return inner;
						}
						// Portable `String` uses `HxString`, which already models null.
						if (rustTypeIsNullableStringCarrier(inner)) {
							return inner;
						}
						// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
						if (isCoreClassOrEnumHandleType(innerType)) {
							return inner;
						}
						if (rustTypeIsHxRef(inner) || rustTypeIsArrayCarrier(inner) || rustTypeIsDynRefCarrier(inner)) {
							return inner;
						}

						return rustOptionType(inner);
					}
				}
			case _:
		}

		var base = TypeTools.follow(t);
		// Expand typedefs explicitly (e.g. `Iterable<T>`, `Iterator<T>`, many std typedef helpers).
		// `TypeTools.follow` doesn't always erase `TType` in practice (notably in macro/std contexts),
		// so handle it here to keep type mapping predictable.
		switch (base) {
			case TType(typeRef, params):
				{
					var tt = typeRef.get();
					if (tt != null) {
						var under:Type = tt.type;
						if (tt.params != null && tt.params.length > 0 && params != null && params.length == tt.params.length) {
							under = TypeTools.applyTypeParameters(under, tt.params, params);
						}
						return toRustType(under, pos);
					}
				}
			case _:
		}
		if (TypeHelper.isVoid(t))
			return RUnit;
		if (TypeHelper.isBool(t))
			return RBool;
		if (TypeHelper.isInt(t))
			return RI32;
		if (TypeHelper.isFloat(t))
			return RF64;
		if (isStringType(base)) {
			return rustStringType();
		}

		var ft = followType(base);

		// Unresolved monomorphs can occur when Haxe keeps a type variable open (most commonly due to
		// `untyped` expressions or as-yet-unified generics). For codegen we need a concrete runtime
		// representation.
		//
		// Policy:
		// - user/project code fails fast (typed mapping required)
		// - framework/upstream std can still use runtime-dynamic compatibility fallback
		switch (ft) {
			case TMono(m):
				{
					var inner = m.get();
					if (inner != null)
						return toRustType(inner, pos);
					#if eval
					if (!shouldAllowUnresolvedMonomorphDynamicFallback(pos)) {
						Context.error("Rust backend: unresolved monomorph in user code. Add an explicit type annotation/cast instead of relying on dynamic fallback.",
							pos);
					}
					#end
					#if eval
					var key = Std.string(pos);
					if (shouldWarnUnresolvedMonomorph(pos) && !warnedUnresolvedMonomorphPos.exists(key)) {
						warnedUnresolvedMonomorphPos.set(key, true);
						Context.warning("Rust backend: unresolved monomorph, lowering to runtime dynamic carrier.", pos);
					}
					#end
					return rustDynamicType();
				}
			case _:
		}

		switch (ft) {
			case TDynamic(_):
				return rustDynamicType();
			case _:
		}

		switch (ft) {
			case TFun(params, ret):
				{
					var retTy = TypeHelper.isVoid(ret) ? null : toRustType(ret, pos);
					return rustDynRefType(rustFunctionTraitObjectType([for (parameter in params) toRustType(parameter.t, pos)], retTy));
				}
			case _:
		}

		switch (ft) {
			case TAbstract(absRef, params):
				{
					var abs = absRef.get();
					var key = abs.pack.join(".") + "." + abs.name;
					if (key == "rust.HxRef" && params.length == 1) {
						var inner = toRustType(params[0], pos);
						return rustHxRefType(inner);
					}
					if (key == "rust.Ref" && params.length == 1) {
						return RBorrow(toRustType(params[0], pos), false, null);
					}
					if (key == "rust.MutRef" && params.length == 1) {
						return RBorrow(toRustType(params[0], pos), true, null);
					}
					if (key == "rust.Str" && params.length == 0) {
						return RBorrow(rustNamedType("str"), false, null);
					}
					if (key == "rust.Slice" && params.length == 1) {
						var inner = toRustType(params[0], pos);
						return RBorrow(RSlice(inner), false, null);
					}
					if (key == "rust.MutSlice" && params.length == 1) {
						var inner = toRustType(params[0], pos);
						return RBorrow(RSlice(inner), true, null);
					}

					// `@:coreType` abstracts have no Haxe-level "underlying type" that is safe to follow.
					// Following `abs.type` for these can recurse back into the same abstract indefinitely.
					//
					// For core types, we must provide an explicit Rust representation mapping.
					if (abs.meta != null && abs.meta.has(":coreType")) {
						var dynamicCoreTypeKey = "." + dynamicBoundaryTypeName();
						// Core primitives (StdTypes) can show up as `@:coreType abstract` types.
						// Even if earlier helpers missed them, map them to Rust primitives here.
						switch (key) {
							case ".Void":
								return RUnit;
							case ".Int":
								return RI32;
							case ".Float":
								return RF64;
							case ".Single":
								// Rust backend currently uses `f64` for Haxe floating-point arithmetic semantics.
								// Keep `Single` aligned with that representation until a dedicated f32 mode exists.
								return RF64;
							case ".Bool":
								return RBool;
							case ".Class":
								// `Class<T>` values are runtime handles and can appear in `Type.typeof` / `ValueType`.
								// For now we represent them as a numeric id. (A richer handle type can be added later.)
								return rustNamedType("u32");
							case ".Enum":
								// Same representation strategy as `Class<T>`.
								return rustNamedType("u32");
							case _ if (key == dynamicCoreTypeKey):
								return rustDynamicType();
							case _:
						}
						if (key == "haxe.io.BytesData") {
							// Target-private storage type backing `haxe.io.Bytes`.
							// For Rust we treat it as a plain byte vector.
							return rustRelativeType(["Vec"], [rustNamedType("u8")]);
						}

						#if eval
						if (!shouldAllowUnmappedCoreTypeDynamicFallback(pos)) {
							Context.error('Rust backend: unmapped @:coreType abstract `'
								+ key
								+ '` in user code. Add a typed mapping in `toRustType` instead of relying on dynamic fallback.',
								pos);
						}
						if (shouldWarnUnmappedCoreType(pos)) {
							Context.warning('Rust backend: unmapped @:coreType abstract `' + key + '`, lowering to runtime dynamic carrier for now.', pos);
						}
						#end
					return rustDynamicType();
					}

					// General abstract fallback: treat as its underlying type.
					// (Most Haxe abstracts are compile-time-only; runtime representation is the backing type.)
					var underlying:Type = abs.type;
					if (abs.params != null && abs.params.length > 0 && params != null && params.length == abs.params.length) {
						underlying = TypeTools.applyTypeParameters(underlying, abs.params, params);
					}
					return toRustType(underlying, pos);
				}
			case _:
		}

		// StdTypes: Iterator<T> / KeyValueIterator<K,V> are typedefs to method-shaped structural types.
		// We lower them to owned Rust iterators for codegen simplicity (primarily used in `for` loops).
		// Mutable anonymous function-field records that merely reuse the names `hasNext` / `next`
		// remain ordinary shared `HxRef<Anon>` objects.
		//
		// Documented limitation: manually calling `.hasNext()` / `.next()` on these iterators is not
		// guaranteed to work; prefer `for (x in ...)`.
		switch (ft) {
			case TAnonymous(anonRef):
				{
					var anon = anonRef.get();
					if (anon != null && anon.fields != null && anon.fields.length == 2) {
						var hasNext:Null<ClassField> = null;
						var next:Null<ClassField> = null;

						for (cf in anon.fields) {
							switch (cf.getHaxeName()) {
								case "hasNext": hasNext = cf;
								case "next": next = cf;
								case _:
							}
						}

						// Iterator<T> (structural methods): { hasNext():Bool, next():T }
						if (hasNext != null && next != null && isIteratorStructType(ft)) {
							var nextRet:Type = switch (followType(next.type)) {
								case TFun(_, r): r;
								case _: next.type;
							}
							var item = toRustType(nextRet, pos);
							return rustRelativeType(["hxrt", "iter", "Iter"], [item]);
						}
					}

					// General anonymous object / structural record.
					// Represent as a reference value to preserve Haxe aliasing + mutability semantics.
					return rustHxRefType(rustRelativeType(["hxrt", "anon", "Anon"]));
				}
			case _:
		}

		if (isArrayType(ft)) {
			var elem = arrayElementType(ft);
			var elemRust = toRustType(elem, pos);
			return rustRelativeType(["hxrt", "array", "Array"], [elemRust]);
		}

		return switch (ft) {
			case TEnum(enumRef, params): {
					var en = enumRef.get();
					var key = en.pack.join(".") + "." + en.name;
					if ((key == "haxe.ds.Option" || key == "reflaxe.std.Option" || key == "rust.Option") && params.length == 1) {
						var t = toRustType(params[0], pos);
						rustOptionType(t);
					} else if ((key == "haxe.functional.Result" || key == "reflaxe.std.Result" || key == "rust.Result")
						&& params.length >= 1) {
						var okT = toRustType(params[0], pos);
						var errT = params.length >= 2 ? toRustType(params[1], pos) : rustStringType();
						rustRelativeType(["Result"], [okT, errT]);
					} else if (key == "haxe.io.Error") {
						rustRelativeType(["hxrt", "io", "Error"]);
					} else {
						rustCrateNominalType(rustModuleSegmentsForEnum(en), rustTypeNameForEnum(en),
							params == null ? [] : [for (parameter in params) toRustType(parameter, pos)]);
					}
				}
			case TInst(clsRef, params): {
					var cls = clsRef.get();
					if (params != null && params.length == 1) {
						switch (haxeArrayIteratorKind(cls)) {
							case ArrayIteratorValues:
								var item = toRustType(params[0], pos);
								return rustRelativeType(["hxrt", "iter", "Iter"], [item]);
							case ArrayIteratorKeyValues:
								return rustRelativeType(["hxrt", "iter", "Iter"],
									[rustHxRefType(rustRelativeType(["hxrt", "anon", "Anon"]))]);
							case null:
						}
					}
					if (isRustAsyncFutureClass(cls)) {
						if (params == null || params.length != 1) {
							#if eval
							RustDiagnostic.error(RustDiagnosticId.AsyncFutureShape, "`rust.async.Future<T>` requires exactly one type parameter.", pos);
							#end
							return rustRelativeType(["hxrt", "async_", "HxFuture"], [RUnit]);
						}
						var inner = toRustType(params[0], pos);
						return rustRelativeType(["hxrt", "async_", "HxFuture"], [inner]);
					}
					switch (cls.kind) {
						case KTypeParameter(_):
							return rustNamedType(cls.name);
						case _:
					}
					if (isBytesClass(cls)) {
						return rustHxRefType(rustRelativeType(["hxrt", "bytes", "Bytes"]));
					}
					if (cls.isExtern) {
						var base = rustExternBasePath(cls);
						var path = if (base == null) {
							RustPath.single(cls.name);
						} else {
							try {
								RustMetadataSyntax.parsePath(base);
							} catch (message:String) {
								#if eval
								RustDiagnostic.error(RustDiagnosticId.MetadataValue, "Invalid extern Rust path syntax: " + message, cls.pos);
								#end
								RustPath.single(cls.name);
							}
						};
						var arguments = params == null ? [] : rustTypeArguments([for (parameter in params) toRustType(parameter, pos)]);
						return RNamed(rustPathWithFinalArguments(path, arguments));
					}
					if (cls.isInterface) {
						var traitObject = traitObjectRustType(t, pos);
						traitObject == null ? RUnit : rustRcType(traitObject);
					} else if (classHasSubclasses(cls)) {
						var traitObject = traitObjectRustType(t, pos);
						traitObject == null ? RUnit : rustRcType(traitObject);
					} else {
						rustHxRefType(rustCrateNominalType(rustModuleSegmentsForClass(cls), rustTypeNameForClass(cls),
							params == null ? [] : [for (parameter in params) toRustType(parameter, pos)]));
					}
				}
			case _: {
					#if eval
					Context.error("Unsupported Rust type in current backend: " + Std.string(t), pos);
					#end
					RUnit;
				}
		}
	}

	function isCopyType(t:Type):Bool {
		t = specializeCurrentMethodType(t);
		var ft = followType(t);
		return TypeHelper.isBool(ft) || TypeHelper.isInt(ft) || TypeHelper.isFloat(ft);
	}

	var cachedHaxeDynamicType:Null<Type> = null;

	/**
		Returns the Haxe `Dynamic` type used at unavoidable compiler boundary coercions.

		Why
		- `Dynamic` lookups are used in several lowering paths (casts, equality coercions).
		- Keeping this lookup centralized makes boundary usage explicit and easier to audit.

		How
		- Lazily resolves and caches `Context.getType("Dynamic")`.
	**/
	function haxeDynamicBoundaryType():Type {
		if (cachedHaxeDynamicType == null) {
			cachedHaxeDynamicType = Context.getType(dynamicBoundaryTypeName());
		}
		return cachedHaxeDynamicType;
	}

	function isDynamicType(t:Type):Bool {
		return switch (followType(t)) {
			case TDynamic(_): true;
			case TAbstract(absRef, _): {
					var abs = absRef.get();
					abs != null && abs.module == "StdTypes" && abs.name == dynamicBoundaryTypeName()
					;
				}
			case _: false;
		}
	}

	/**
		Returns `true` if this Haxe type is represented as `hxrt::dynamic::Dynamic` in emitted Rust.

		Why
		- The Haxe type system can contain monomorphs/type-parameters that end up *lowered* to
		  `Dynamic` by this backend (notably in upstream stdlib code).
		- Relying purely on `isDynamicType(...)` misses those cases and leads to incorrect boxing
		  (`Dynamic::from(Dynamic)`) and failed coercions.

		What
		- Treats both real Haxe `Dynamic` *and* types that lower to Rust `Dynamic` as dynamic for
		  coercion/boxing decisions.

		How
		- Uses `toRustType` to observe the final Rust representation.
	**/
	function mapsToRustDynamic(t:Type, pos:haxe.macro.Expr.Position):Bool {
		if (isDynamicType(t))
			return true;
		return rustTypeIsDynamicCarrier(toRustType(t, pos));
	}

	function isBytesClass(cls:ClassType):Bool {
		return cls.pack.join(".") == "haxe.io" && cls.name == "Bytes";
	}

	function isBytesType(t:Type):Bool {
		return switch (followType(t)) {
			case TInst(clsRef, _): isBytesClass(clsRef.get());
			case _: false;
		}
	}

	/**
		Classifies Haxe's compiler-supplied array-backed iterator classes.

		Why
		- `Array.iterator()` and `Array.keyValueIterator()` are inline and expose nominal std classes
		  in typed AST.
		- Upstream std modules are typed but are not generally emitted by this backend, so nominal
		  constructor paths for these classes cannot be referenced from generated crates.

		What
		- Returns a closed representation kind for only the canonical Haxe std classes, never user
		  classes with the same short names.

		How
		- Uses typed package, module, and class identity so construction, Rust type mapping, reuse,
		  and HxRef exclusion share one product-neutral classification.
	**/
	function haxeArrayIteratorKind(cls:Null<ClassType>):Null<HaxeArrayIteratorKind> {
		if (cls == null || cls.pack.join(".") != "haxe.iterators")
			return null;

		return switch (cls.module + ":" + cls.name) {
			case "haxe.iterators.ArrayIterator:ArrayIterator": ArrayIteratorValues;
			case "haxe.iterators.ArrayKeyValueIterator:ArrayKeyValueIterator": ArrayIteratorKeyValues;
			case _: null;
		}
	}

	/**
		Checks whether a typed value uses either canonical array-backed iterator representation.

		Why / What / How
		- Representation and reuse decisions receive `Type`, rather than a bare `ClassType`.
		- This wrapper follows typedef/lazy layers and requires the one item type parameter before
		  delegating identity to `haxeArrayIteratorKind`.
	**/
	function isHaxeArrayBackedIteratorType(t:Type):Bool {
		return switch (followType(t)) {
			case TInst(clsRef, params): haxeArrayIteratorKind(clsRef.get()) != null && params != null && params.length == 1;
			case _: false;
		}
	}

	function isArrayType(t:Type):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, _): {
					var cls = clsRef.get();
					cls.pack.length == 0 && cls.module == "Array" && cls.name == "Array"
					;
				}
			case _: false;
		}
	}

	function isRustVecType(t:Type):Bool {
		return switch (followType(t)) {
			case TInst(clsRef, params):
				{
					var cls = clsRef.get();
					cls != null
				&& cls.isExtern
				&& cls.name == "Vec"
				&& (cls.pack.join(".") == "rust" || cls.module == "rust.Vec")
				&& params.length == 1
					;
				}
			case _:
				false;
		}
	}

	function isRustSliceType(t:Type):Bool {
		return switch (followType(t)) {
			case TAbstract(absRef, params):
				{
					var abs = absRef.get();
					abs != null
				&& abs.name == "Slice"
				&& (abs.pack.join(".") == "rust" || abs.module == "rust.Slice")
				&& params.length == 1
					;
				}
			case _:
				false;
		}
	}

	function isRustHashMapType(t:Type):Bool {
		return switch (followType(t)) {
			case TInst(clsRef, params):
				{
					var cls = clsRef.get();
					var externPath = cls != null ? rustExternBasePath(cls) : null;
					var isRealRustHashMap = false;
					if (cls != null) {
						for (m in cls.meta.get()) {
							if (m.name != ":realPath" && m.name != "realPath")
								continue;
							if (m.params == null || m.params.length != 1)
								continue;
							switch (m.params[0].expr) {
								case EConst(CString(s, _)):
									if (s == "rust.HashMap") isRealRustHashMap = true;
								case _:
							}
						}
					}

					cls != null
				&& cls.isExtern
				&& cls.name == "HashMap"
				&& (isRealRustHashMap
					|| cls.pack.join(".") == "rust"
					|| cls.module == "rust.HashMap"
					|| externPath == "std::collections::HashMap")
				&& params.length == 2
					;
				}
			case _:
				false;
		}
	}

	function isRustHxRefType(t:Type):Bool {
		return switch (followType(t)) {
			case TAbstract(absRef, params):
				{
					var abs = absRef.get();
					abs != null
				&& abs.name == "HxRef"
				&& (abs.pack.join(".") == "rust" || abs.module == "rust.HxRef")
				&& params.length == 1
					;
				}
			case _:
				false;
		}
	}

	function isHxRefValueType(t:Type):Bool {
		if (isBytesType(t))
			return true;
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, _): {
					var cls = clsRef.get();
					if (cls == null)
						return false;
					// Generic type parameters are Rust type variables (`T`), not framework class
					// instances. Treating them as ref-backed forces `.clone()` at call sites and
					// incorrectly requires `T: Clone` for plain by-value generics.
					switch (cls.kind) {
						case KTypeParameter(_):
							return false;
						case _:
					}
					// Arrays are represented as `hxrt::array::Array<T>`, not `HxRef<_>`.
					if (cls.pack.length == 0 && cls.module == "Array" && cls.name == "Array")
						return false;
					// Compiler-owned array-backed iterator adapters are `hxrt::iter::Iter<_>` values even
					// though their source Haxe types are non-extern classes.
					if (haxeArrayIteratorKind(cls) != null)
						return false;
					!cls.isExtern && !cls.isInterface
					;
				}
			case _:
				false;
		}
	}

	function isRcBackedType(t:Type):Bool {
		// Concrete classes / Bytes are `HxRef<T>` (shared ref-backed).
		// Interfaces and polymorphic base classes are `HxRc<dyn Trait>` (shared ref-backed).
		// Additionally, `rust.HxRef<T>` is a shared ref used by framework helpers.
		// Function values also lower to shared runtime handles (`HxDynRef<dyn Fn...>`).
		return isHxRefValueType(t) || isRustHxRefType(t) || isAnonObjectType(t) || isInterfaceType(t) || isPolymorphicClassType(t) || isFunctionValueType(t);
	}

	function isRustIterType(t:Type):Bool {
		return switch (followType(t)) {
			case TInst(clsRef, params): {
					var cls = clsRef.get();
					var isRealRustIter = false;
					if (cls != null) {
						for (m in cls.meta.get()) {
							if (m.name != ":realPath" && m.name != "realPath")
								continue;
							if (m.params == null || m.params.length != 1)
								continue;
							switch (m.params[0].expr) {
								case EConst(CString(s, _)):
									if (s == "rust.Iter") isRealRustIter = true;
								case _:
							}
						}
					}

					cls != null && cls.isExtern && isRealRustIter && params.length == 1
					;
				}
			case _:
				false;
		}
	}

	function arrayElementType(t:Type):Type {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, params): {
					var cls = clsRef.get();
					if (cls.pack.length == 0 && cls.module == "Array" && cls.name == "Array") {
						return params.length > 0 ? params[0] : ft;
					}
					ft;
				}
			case _: ft;
		}
	}

	function iterBorrowMethod(t:Type):String {
		var elem:Null<Type> = null;
		var ft = followType(t);

		if (isArrayType(ft)) {
			elem = arrayElementType(ft);
		} else {
			switch (ft) {
				case TInst(_, params) if (isRustVecType(ft) && params.length == 1):
					elem = params[0];
				case TAbstract(_, params) if (isRustSliceType(ft) && params.length == 1):
					elem = params[0];
				case _:
			}
		}

		return elem != null && isCopyType(elem) ? "copied" : "cloned";
	}

	function rustTypeToString(t:reflaxe.rust.ast.RustAST.RustType):String {
		return reflaxe.rust.ast.RustASTPrinter.printTypeSyntax(t);
	}
}

private class RustModuleDeclTree {
	public var hasFile:Bool = false;
	public var children:Map<String, RustModuleDeclTree> = [];

	public function new() {}
}
#end
