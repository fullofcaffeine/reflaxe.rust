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
import reflaxe.compiler.TypeUsageTracker.TypeOrModuleType;
import reflaxe.compiler.TargetCodeInjection;
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
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustMatchArm;
import reflaxe.rust.ast.RustAST.RustPattern;
import reflaxe.rust.ast.RustAST.RustStmt;
import reflaxe.rust.ast.RustAST.RustVisibility;
import reflaxe.helpers.TypeHelper;
import reflaxe.rust.macros.CargoMetaRegistry;
import reflaxe.rust.macros.RustExtraSrcRegistry;
import reflaxe.rust.naming.RustNaming;
import reflaxe.rust.ProfileResolver;
import reflaxe.rust.RustProfile;

using reflaxe.helpers.BaseTypeHelper;
using reflaxe.helpers.ClassFieldHelper;

private typedef RustImplSpec = {
	var traitPath:String;
	@:optional var forType:String;
	@:optional var body:String;
};

private enum RustTestReturnKind {
	TestVoid;
	TestBool;
}

private typedef RustTestSpec = {
	var classType:ClassType;
	var field:ClassField;
	var wrapperName:String;
	var serial:Bool;
	var returnKind:RustTestReturnKind;
	var pos:haxe.macro.Expr.Position;
};

/**
 * RustCompiler (POC)
 *
 * Emits a minimal Rust program for the Haxe main class.
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
	var frameworkSrcDir:Null<String> = null;
	var upstreamStdDirs:Array<String> = [];
	var frameworkRuntimeDir:Null<String> = null;
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
	var currentArgNames:Null<Map<String, String>> = null;
	var currentLocalNames:Null<Map<Int, String>> = null;
	var currentLocalUsed:Null<Map<String, Bool>> = null;
	var currentEnumParamBinds:Null<Map<String, String>> = null;
	var currentFunctionReturn:Null<Type> = null;
	var currentFunctionIsAsync:Bool = false;
	var warnedUnresolvedMonomorphPos:Map<String, Bool> = [];
	// Rust identifier to use for Haxe `this` (`TThis`) in the current function body.
	// - constructors: `"self_"` (a local `HxRef<T>`)
	// - instance methods/super thunks: `"__hx_this"` (materialized from `&HxRefCell<T>` via `self_ref()`)
	var currentThisIdent:Null<String> = null;
	var rustNamesByClass:Map<String, {fields:Map<String, String>, methods:Map<String, String>}> = [];
	var inCodeInjectionArg:Bool = false;
	var rustTestSpecs:Array<RustTestSpec> = [];

	inline function wantsPreludeAliases():Bool {
		// Always emit stable `crate::HxRc` / `crate::HxRefCell` / `crate::HxRef` aliases so:
		// - generated code stays uniform across profiles
		// - the runtime can evolve the underlying representation (e.g. thread-safe heap)
		return true;
	}

	inline function rcBasePath():String {
		return wantsPreludeAliases() ? "crate::HxRc" : "std::rc::Rc";
	}

	inline function dynRefBasePath():String {
		return wantsPreludeAliases() ? "crate::HxDynRef" : "hxrt::cell::HxDynRef";
	}

	inline function refCellBasePath():String {
		return wantsPreludeAliases() ? "crate::HxRefCell" : "std::cell::RefCell";
	}

	inline function useNullableStringRepresentation():Bool {
		if (Context.defined("rust_string_non_nullable"))
			return false;
		return Context.defined("rust_string_nullable");
	}

	inline function asyncPreviewEnabled():Bool {
		return Context.defined("rust_async_preview");
	}

	inline function rustStringTypePath():String {
		return useNullableStringRepresentation() ? "hxrt::string::HxString" : "String";
	}

	inline function stringLiteralExpr(value:String):RustExpr {
		return useNullableStringRepresentation() ? ECall(EPath("hxrt::string::HxString::from"),
			[ELitString(value)]) : ECall(EPath("String::from"), [ELitString(value)]);
	}

	inline function stringNullExpr():RustExpr {
		return useNullableStringRepresentation() ? ECall(EPath("hxrt::string::HxString::null"), []) : ECall(EPath("String::from"), [ELitString("null")]);
	}

	inline function wrapRustStringExpr(value:RustExpr):RustExpr {
		return useNullableStringRepresentation() ? ECall(EPath("hxrt::string::HxString::from"), [value]) : value;
	}

	inline function stringNullDefaultValue():String {
		return useNullableStringRepresentation() ? "hxrt::string::HxString::null()" : "String::from(\"null\")";
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
		return "Dynamic";
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
		return "hxrt::dynamic::" + dynamicBoundaryTypeName();
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

	inline function isRustDynamicPath(path:String):Bool {
		return path == rustDynamicPath();
	}

	public function new() {
		super();
	}

	public function createCompilationContext():CompilationContext {
		return new CompilationContext(crateName);
	}

	public function generateOutputIterator():Iterator<DataAndFileInfo<StringOrBytes>> {
		return new RustOutputIterator(this);
	}

	override public function onCompileStart() {
		// Reset cached class hierarchy info per compilation.
		classHasSubclass = null;
		frameworkStdDir = null;
		frameworkSrcDir = null;
		upstreamStdDirs = [];
		frameworkRuntimeDir = null;
		warnedUnresolvedMonomorphPos = [];
		rustTestSpecs = [];

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

		// Allow overriding crate name with -D rust_crate=<name>
		var v = Context.definedValue("rust_crate");
		if (v != null && v.length > 0)
			crateName = v;

		// Compute this haxelib's key roots:
		// - `std/` for local-dev layout in this repository
		// - `src/` for flattened package layout (where std overrides are merged into classPath)
		//
		// We intentionally keep both so framework std classification stays correct in both environments.
		try {
			var compilerPath = Context.resolvePath("reflaxe/rust/RustCompiler.hx");
			var rustDir = Path.directory(compilerPath); // .../src/reflaxe/rust
			var reflaxeDir = Path.directory(rustDir); // .../src/reflaxe
			var srcDir = Path.directory(reflaxeDir); // .../src
			var libraryRoot = Path.directory(srcDir); // .../
			frameworkStdDir = canonicalizePath(Path.normalize(Path.join([libraryRoot, "std"])));
			frameworkSrcDir = canonicalizePath(Path.normalize(Path.join([libraryRoot, "src"])));
			frameworkRuntimeDir = canonicalizePath(Path.normalize(Path.join([libraryRoot, "runtime", "hxrt"])));
		} catch (e:haxe.Exception) {
			frameworkStdDir = null;
			frameworkSrcDir = null;
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

		extraRustSrcFiles.sort((a, b) -> Reflect.compare(a.module, b.module));
	}

	override public function onCompileEnd() {
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

		// Emit the bundled runtime crate (hxrt) alongside the generated crate.
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

		var metaDeps = CargoMetaRegistry.renderDependencyLines();
		var deps = 'hxrt = { path = "./hxrt" }' + "\n" + metaDeps + depsExtra;

		var cargo = [
			"[package]",
			'name = "' + crateName + '"',
			'version = "0.0.1"',
			'edition = "2021"',
			"",
			"[dependencies]",
			deps
		].join("\n");
		setExtraFile(OutputPath.fromStr("Cargo.toml"), cargo);
	}

	function emitRuntimeCrate():Void {
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
		var isMain = isMainClass(classType);
		if (!shouldEmitClass(classType, isMain))
			return null;

		// Ensure this lands at <rust_output>/src/main.rs
		setOutputFileDir("src");
		if (isMain) {
			setOutputFileName("main");
			didEmitMain = true;
			mainBaseType = classType;
			mainClassKey = classKey(classType);
		} else {
			setOutputFileName(rustModuleNameForClass(classType));
		}

		currentClassKey = classKey(classType);
		currentClassName = classType.name;
		currentClassType = classType;
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
		items.push(RRaw("// Generated by reflaxe.rust (POC)"));

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

			var preludeLines:Array<String> = wantsPreludeAliases() ? [
				"type HxRc<T> = hxrt::cell::HxRc<T>;",
				"type HxDynRef<T: ?Sized> = hxrt::cell::HxDynRef<T>;",
				"type HxRefCell<T> = hxrt::cell::HxCell<T>;",
				"type HxRef<T> = hxrt::cell::HxRef<T>;"
			] : ["type HxRef<T> = hxrt::cell::HxRef<T>;"];

			headerLines = headerLines.concat(lintLines.concat([""].concat(preludeLines).concat([""])));

			for (cls in otherUserClasses) {
				var modName = rustModuleNameForClass(cls);
				addMod(modName);
			}

			// User enums
			var otherUserEnums = getUserEnumsForModules();
			for (en in otherUserEnums) {
				var modName = rustModuleNameForEnum(en);
				addMod(modName);
			}

			modLines.sort(Reflect.compare);

			headerLines = headerLines.concat(modLines);
			headerLines.push("");
			headerLines.push(emitSubtypeTypeIdRegistryFn());
			if (headerLines.length > 0)
				items.push(RRaw(headerLines.join("\n")));
		} else if (classType.isInterface) {
			// Interfaces compile to Rust traits (no struct allocation).
			items.push(RRaw("// Haxe interface -> Rust trait"));

			var traitLines:Array<String> = [];
			var traitGenerics = classGenericDecls;
			var traitGenericSuffix = traitGenerics.length > 0 ? "<" + traitGenerics.join(", ") + ">" : "";
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
			items.push(RRaw(traitLines.join("\n")));
		} else {
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
					var baseMod = rustModuleNameForClass(base);
					var baseTrait = rustTypeNameForClass(base) + "Trait";
					var key = baseMod + "::" + baseTrait;
					if (!seenBaseUses.exists(key) && baseCtorCallsThisMethods(base)) {
						seenBaseUses.set(key, true);
						items.push(RRaw("use crate::" + baseMod + "::" + baseTrait + ";"));
					}
				}
				base = base.superClass != null ? base.superClass.t.get() : null;
			}

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
			// --------------------------------------------------------------------
			if (varFields != null) {
				for (varData in varFields) {
					if (!varData.isStatic)
						continue;

					var cf = varData.field;
					var rustName = rustMethodName(classType, cf);
					var tyStr = rustTypeToString(toRustType(cf.type, cf.pos));

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

					items.push(RRaw(lines.join("\n")));
				}
			}

			// Stable RTTI id for this class (portable-mode baseline).
			items.push(RRaw("pub const __HX_TYPE_ID: u32 = " + typeIdLiteralForClass(classType) + ";"));

			var derives = rustDerivesFromMeta(classType.meta);
			var canDeriveDebug = true;
			for (cf in getAllInstanceVarFieldsForStruct(classType)) {
				if (shouldOptionWrapStructFieldType(cf.type)) {
					canDeriveDebug = false;
					break;
				}
				// Trait objects (`dyn ...`) do not implement `Debug` by default, so auto-deriving `Debug`
				// for any struct that contains them would fail to compile.
				var tyStr = rustTypeToString(toRustType(cf.type, cf.pos));
				if (tyStr.indexOf("dyn ") != -1) {
					canDeriveDebug = false;
					break;
				}
			}
			if (canDeriveDebug) {
				derives = mergeUniqueStrings(["Debug"], derives);
			}
			if (derives.length > 0)
				items.push(RRaw("#[derive(" + derives.join(", ") + ")]"));

			var structFields:Array<reflaxe.rust.ast.RustAST.RustStructField> = [];
			for (cf in getAllInstanceVarFieldsForStruct(classType)) {
				var ty = toRustType(cf.type, cf.pos);
				if (shouldOptionWrapStructFieldType(cf.type)) {
					ty = RPath("Option<" + rustTypeToString(ty) + ">");
				}
				structFields.push({
					name: rustFieldName(classType, cf),
					ty: ty,
					isPub: cf.isPublic
				});
			}
			if (classNeedsPhantomForUnusedTypeParams(classType)) {
				var decls = rustGenericDeclsForClass(classType);
				var names = rustGenericNamesFromDecls(decls);
				var phantomTy = names.length == 1 ? ("std::marker::PhantomData<" + names[0] + ">") : ("std::marker::PhantomData<(" + names.join(", ") + ")>");
				structFields.push({
					name: "__hx_phantom",
					ty: RPath(phantomTy),
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
				implFunctions.push(compileInstanceMethod(classType, f, owner));
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
					keys.sort(Reflect.compare);
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
				forType: rustSelfTypeInst,
				functions: implFunctions
			}));

			// Extra Rust trait impls declared via `@:rustImpl(...)` metadata.
			var rustImpls = rustImplsFromMeta(classType.meta);
			for (spec in rustImpls) {
				items.push(RRaw(renderRustImplBlock(spec, classGenericDecls, rustSelfTypeInst)));
			}

			// Base-class polymorphism: if this class has subclasses, emit a trait for it.
			if (classHasSubclasses(classType)) {
				items.push(RRaw(emitClassTrait(classType, effectiveFuncFields)));
				items.push(RRaw(emitClassTraitImplForSelf(classType, effectiveFuncFields)));
			}

			// If this class has polymorphic base classes, implement their traits for this type.
			var base = classType.superClass != null ? classType.superClass.t.get() : null;
			while (base != null) {
				if (classHasSubclasses(base)) {
					items.push(RRaw(emitBaseTraitImplForSubclass(base, classType, effectiveFuncFields)));
				}
				base = base.superClass != null ? base.superClass.t.get() : null;
			}

			// Implement any Haxe interfaces (including inherited interface parents)
			// as Rust traits on `RefCell<Class>`.
			var ifaceImplTargets:Array<{ifaceType:ClassType, params:Array<Type>}> = [];
			var seenIfaceImplTargets:Map<String, Bool> = [];
			function collectInterfaceImplTargets(ifaceType:ClassType, resolvedParams:Array<Type>):Void {
				if (ifaceType == null)
					return;
				var key = classKey(ifaceType);
				if (seenIfaceImplTargets.exists(key))
					return;
				seenIfaceImplTargets.set(key, true);
				ifaceImplTargets.push({ifaceType: ifaceType, params: resolvedParams});

				for (parent in ifaceType.interfaces) {
					var parentType = parent.t.get();
					if (parentType == null)
						continue;
					var parentResolvedParams = parent.params != null ? parent.params : [];
					if (parentResolvedParams.length > 0 && ifaceType.params != null && ifaceType.params.length > 0 && resolvedParams != null
						&& resolvedParams.length > 0) {
						parentResolvedParams = [
							for (p in parentResolvedParams) TypeTools.applyTypeParameters(p, ifaceType.params, resolvedParams)
						];
					}
					collectInterfaceImplTargets(parentType, parentResolvedParams);
				}
			}
			for (iface in classType.interfaces) {
				var ifaceType = iface.t.get();
				if (ifaceType == null)
					continue;
				collectInterfaceImplTargets(ifaceType, iface.params != null ? iface.params : []);
			}
			for (ifaceTarget in ifaceImplTargets) {
				var ifaceType = ifaceTarget.ifaceType;
				if (!shouldEmitClass(ifaceType, false))
					continue;

				var ifaceMod = rustModuleNameForClass(ifaceType);
				var traitPath = "crate::" + ifaceMod + "::" + rustTypeNameForClass(ifaceType);
				var ifaceTypeParams = ifaceTarget.params != null ? ifaceTarget.params : [];
				var ifaceTypeArgs = ifaceTypeParams.length > 0 ? ("<"
					+ [for (p in ifaceTypeParams) rustTypeToString(toRustType(p, classType.pos))].join(", ") + ">") : "";
				var implGenerics = classGenericDecls.length > 0 ? "<" + classGenericDecls.join(", ") + ">" : "";
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
				implLines.push("\t\tcrate::" + rustModuleNameForClass(classType) + "::__HX_TYPE_ID");
				implLines.push("\t}");
				implLines.push("}");
				items.push(RRaw(implLines.join("\n")));
			}
		}

		if (isMain) {
			// Emit any additional static functions so user code can call them from `main`.
			for (f in funcFields) {
				if (!f.isStatic)
					continue;
				if (f.expr == null)
					continue;

				var haxeName = f.field.getHaxeName();
				if (haxeName == "main")
					continue;

				var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
				var body = {stmts: [], tail: null};
				var isAsyncMethod = hasAsyncFunctionMeta(f.field.meta);
				var asyncInnerRet:Null<Type> = null;
				if (isAsyncMethod) {
					ensureAsyncPreviewAllowed(f.field.pos);
					asyncInnerRet = rustFutureInnerType(f.ret);
					if (asyncInnerRet == null) {
						#if eval
						Context.error("`@:async`/`@:rustAsync` static methods must return `rust.async.Future<T>` (got `" + TypeTools.toString(f.ret) + "`).",
							f.field.pos);
						#end
					}
				}
				withFunctionContext(f.expr, [for (a in f.args) a.getName()], isAsyncMethod ? asyncInnerRet : f.ret, () -> {
					for (a in f.args) {
						args.push({
							name: rustArgIdent(a.getName()),
							ty: toRustType(a.type, f.field.pos)
						});
					}
					if (isAsyncMethod) {
						var innerBody = compileFunctionBody(f.expr, asyncInnerRet);
						var innerBlockExpr = EBlock(innerBody);
						var innerBlockSrc = reflaxe.rust.ast.RustASTPrinter.printExprForInjection(innerBlockExpr);
						body = {
							stmts: [RReturn(ERaw("Box::pin(async move " + innerBlockSrc + ")"))],
							tail: null
						};
					} else {
						body = compileFunctionBody(f.expr, f.ret);
					}
				}, isAsyncMethod);

				items.push(RFn({
					name: rustMethodName(classType, f.field),
					isPub: false,
					args: args,
					ret: toRustType(f.ret, f.field.pos),
					body: body
				}));
			}

			var mainFunc = findStaticMain(funcFields);
			if (mainFunc != null && hasAsyncFunctionMeta(mainFunc.field.meta)) {
				ensureAsyncPreviewAllowed(mainFunc.field.pos);
				#if eval
				Context.error("`main` cannot be marked async in preview mode. Keep `main` sync and call `rust.async.Async.blockOn(...)` at the boundary.",
					mainFunc.field.pos);
				#end
			}
			// Rust `fn main()` is always unit-returning; compile as void to avoid accidental tail expressions.
			var body:RustBlock = (mainFunc != null && mainFunc.expr != null) ? compileVoidBodyWithContext(mainFunc.expr, []) : defaultMainBody();

			items.push(RFn({
				name: "main",
				isPub: false,
				args: [],
				ret: RUnit,
				body: body
			}));

			var rustTests = renderRustTestModule();
			if (rustTests != null && rustTests.length > 0) {
				items.push(RRaw(rustTests));
			}
		}

		currentClassKey = null;
		currentClassName = null;
		currentClassType = null;
		currentMethodOwnerType = null;
		currentNeededSuperThunks = null;
		return {items: items};
	}

	public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<RustFile> {
		if (!shouldEmitEnum(enumType))
			return null;

		setOutputFileDir("src");
		setOutputFileName(rustModuleNameForEnum(enumType));

		var items:Array<RustItem> = [];
		items.push(RRaw("// Generated by reflaxe.rust (POC)"));
		items.push(RRaw("pub const __HX_TYPE_ID: u32 = " + typeIdLiteralForEnum(enumType) + ";"));

		var variants:Array<reflaxe.rust.ast.RustAST.RustEnumVariant> = [];

		function boxRecursiveEnumArg(rt:reflaxe.rust.ast.RustAST.RustType):reflaxe.rust.ast.RustAST.RustType {
			var selfName = enumType.name;
			var selfPath = "crate::" + rustModuleNameForEnum(enumType) + "::" + selfName;
			var s = rustTypeToString(rt);
			if (s == selfName || s == selfPath)
				return RPath("Box<" + selfName + ">");
			if (s == "Option<" + selfName + ">" || s == "Option<" + selfPath + ">")
				return RPath("Option<Box<" + selfName + ">>");
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
			name: enumType.name,
			isPub: true,
			derives: derives,
			variants: variants
		}));

		var rustImpls = rustImplsFromMeta(enumType.meta);
		for (spec in rustImpls) {
			items.push(RRaw(renderRustImplBlock(spec, [], enumType.name)));
		}

		return {items: items};
	}

	override public function compileTypedefImpl(typedefType:DefType):Null<RustFile> {
		return null;
	}

	override public function compileAbstractImpl(abstractType:AbstractType):Null<RustFile> {
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
		var file = Context.getPosInfos(classType.pos).file;
		return isUserProjectFile(file) || isFrameworkStdFile(file);
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
		var file = Context.getPosInfos(enumType.pos).file;
		return isUserProjectFile(file) || isFrameworkStdFile(file);
	}

	function isUserProjectFile(file:String):Bool {
		var cwd = normalizePath(Sys.getCwd());
		var full = resolvePosFileToAbsolute(file, cwd);
		return StringTools.startsWith(full, ensureTrailingSlash(cwd));
	}

	function isFrameworkStdFile(file:String):Bool {
		var cwd = normalizePath(Sys.getCwd());
		var full = resolvePosFileToAbsolute(file, cwd);

		if (isUnderFrameworkStdRoot(full))
			return true;

		if (upstreamStdDirs.length > 0) {
			for (d in upstreamStdDirs) {
				var r = ensureTrailingSlash(normalizePath(d));
				if (StringTools.startsWith(full, r))
					return true;
			}
		}

		return false;
	}

	/**
		Returns whether an absolute file path belongs to this library's framework std overrides.

		Why
		- During local development, overrides live under `<repo>/std/**`.
		- In release packages, we flatten `stdPaths` into `classPath` (`src/**`) to mirror Reflaxe's
		  build flow and keep install-time classpaths simple.
		- We need one classifier that works in both layouts so emission and warning policies remain
		  deterministic regardless of install method.

		How
		- First check the explicit `std/` root when present.
		- Then check flattened `src/` paths against known std roots/modules (`haxe/`, `sys/`,
		  `rust/`, `hxrt/`, plus top-level std modules like `Date`/`Sys`).
	**/
	function isUnderFrameworkStdRoot(full:String):Bool {
		if (frameworkStdDir != null) {
			var stdRoot = ensureTrailingSlash(normalizePath(frameworkStdDir));
			if (StringTools.startsWith(full, stdRoot))
				return true;
		}

		if (frameworkSrcDir != null) {
			var srcRoot = ensureTrailingSlash(normalizePath(frameworkSrcDir));
			if (StringTools.startsWith(full, srcRoot)) {
				var rel = full.substr(srcRoot.length);
				if (isFrameworkStdRelativePath(rel))
					return true;
			}
		}

		return false;
	}

	/**
		Returns true when a path relative to framework `src/` points to a flattened std override file.

		Examples
		- `haxe/Json.cross.hx` -> true
		- `sys/net/Socket.cross.hx` -> true
		- `rust/tui/TuiDemo.hx` -> true
		- `reflaxe/rust/RustCompiler.hx` -> false
	**/
	function isFrameworkStdRelativePath(rel:String):Bool {
		if (rel == null || rel.length == 0)
			return false;

		var normalized = normalizePath(rel);
		while (StringTools.startsWith(normalized, "./"))
			normalized = normalized.substr(2);

		if (StringTools.startsWith(normalized, "haxe/")
			|| StringTools.startsWith(normalized, "sys/")
			|| StringTools.startsWith(normalized, "rust/")
			|| StringTools.startsWith(normalized, "hxrt/"))
			return true;

		// Top-level framework std overrides (no subdirectories).
		if (normalized.indexOf("/") != -1 || !StringTools.endsWith(normalized, ".hx"))
			return false;

		var stem = Path.withoutExtension(normalized); // `Date.cross` or `Date`
		if (StringTools.endsWith(stem, ".cross"))
			stem = stem.substr(0, stem.length - ".cross".length);

		return switch (stem) {
			case "Date" | "Lambda" | "StringBuf" | "StringTools" | "Sys" | "ArrayTools": true;
			case _: false;
		}
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

	function rustModuleNameForClass(classType:ClassType):String {
		var base = (classType.pack.length > 0 ? (classType.pack.join("_") + "_") : "") + classType.name;
		return RustNaming.snakeIdent(base);
	}

	function rustModuleNameForEnum(enumType:EnumType):String {
		var base = (enumType.pack.length > 0 ? (enumType.pack.join("_") + "_") : "") + enumType.name;
		return RustNaming.snakeIdent(base);
	}

	function rustTypeNameForClass(classType:ClassType):String {
		return RustNaming.typeIdent(classType.name);
	}

	function rustTypeNameForEnum(enumType:EnumType):String {
		return RustNaming.typeIdent(enumType.name);
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
			clsMethodNames.sort(Reflect.compare);
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
		staticMethodNames.sort(Reflect.compare);
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
					Context.error("`@:rustTest` can only be declared once per method.", entry.pos);
					#end
					continue;
				}

				if (entry.params == null || entry.params.length == 0)
					continue;

				if (entry.params.length != 1) {
					#if eval
					Context.error("`@:rustTest` accepts no params or a single string/object parameter.", entry.pos);
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
										Context.error("`@:rustTest` field `name` must be a compile-time string.", field.expr.pos);
										#end
										continue;
									}
									cfg.nameOverride = StringTools.trim(nameValue);
								case "serial":
									var serialValue = readConstBool(field.expr);
									if (serialValue == null) {
										#if eval
										Context.error("`@:rustTest` field `serial` must be a compile-time bool.", field.expr.pos);
										#end
										continue;
									}
									cfg.serial = serialValue;
								case _:
									#if eval
									Context.error("`@:rustTest` only supports `name` and `serial` fields.", field.expr.pos);
									#end
							}
						}
					case _:
						#if eval
						Context.error("`@:rustTest` parameter must be a string name or object `{ name, serial }`.", entry.pos);
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
							Context.error("`@:rustTest` methods must live in non-main classes so wrappers can call `crate::<module>::Type::method`.", cf.pos);
							#end
							continue;
						}

						if (!cf.isPublic) {
							#if eval
							Context.error("`@:rustTest` methods must be `public static` so generated wrappers can call them.", cf.pos);
							#end
							continue;
						}

						var returnKind:Null<RustTestReturnKind> = null;
						switch (followType(cf.type)) {
							case TFun(params, ret):
								if (params.length != 0) {
									#if eval
									Context.error("`@:rustTest` methods must have zero parameters.", cf.pos);
									#end
									continue;
								}

								if (TypeHelper.isVoid(ret)) {
									returnKind = TestVoid;
								} else if (TypeHelper.isBool(ret)) {
									returnKind = TestBool;
								} else {
									#if eval
									Context.error("`@:rustTest` methods must return `Void` or `Bool` (got `" + TypeTools.toString(ret) + "`).", cf.pos);
									#end
									continue;
								}
							case _:
								#if eval
								Context.error("`@:rustTest` can only be used on methods.", cf.pos);
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
			return Reflect.compare(ak, bk);
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
		tests.sort((a, b) -> Reflect.compare(a.wrapperName, b.wrapperName));

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
			var methodPath = "crate::" + rustModuleNameForClass(spec.classType) + "::" + rustTypeNameForClass(spec.classType) + "::"
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

	function ensureAsyncPreviewAllowed(pos:haxe.macro.Expr.Position):Void {
		if (!asyncPreviewEnabled()) {
			#if eval
			Context.error("Async preview requires `-D rust_async_preview`.", pos);
			#end
			return;
		}
		if (!ProfileResolver.isRustFirst(profile)) {
			#if eval
			Context.error("Async preview currently requires a Rust-first profile: `-D reflaxe_rust_profile=rusty|metal`.", pos);
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

		out.sort((a, b) -> Reflect.compare(classKey(a), classKey(b)));
		return out;
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

		out.sort((a, b) -> Reflect.compare(enumKey(a), enumKey(b)));
		return out;
	}

	override public function onOutputComplete() {
		if (!didEmitMain)
			return;
		if (output == null || output.outputDir == null)
			return;

		var outDir = output.outputDir;
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
				Context.warning("`" + cargoCmd + " " + subcommand + "` failed (exit " + code + ") for output: " + manifest, Context.currentPos());
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

	function defaultValueForType(t:Type, pos:haxe.macro.Expr.Position):String {
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
						var innerStr = rustTypeToString(inner);

						// Some Rust representations already have an explicit null value (no extra `Option<...>` needed).
						if (isRustDynamicPath(innerStr)) {
							return rustDynamicNullRaw();
						}
						if (innerStr == "hxrt::string::HxString") {
							return "hxrt::string::HxString::null()";
						}
						// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
						if (isCoreClassOrEnumHandleType(innerType)) {
							return "0u32";
						}
						if (StringTools.startsWith(innerStr, "crate::HxRef<")) {
							var prefix = "crate::HxRef<";
							var innerPath = innerStr.substr(prefix.length, innerStr.length - prefix.length - 1);
							return "crate::HxRef::<" + innerPath + ">::null()";
						}
						if (StringTools.startsWith(innerStr, "hxrt::array::Array<")) {
							var prefix = "hxrt::array::Array<";
							var innerPath = innerStr.substr(prefix.length, innerStr.length - prefix.length - 1);
							return "hxrt::array::Array::<" + innerPath + ">::null()";
						}
						if (StringTools.startsWith(innerStr, dynRefBasePath() + "<")) {
							var prefix = dynRefBasePath() + "<";
							var innerPath = innerStr.substr(prefix.length, innerStr.length - prefix.length - 1);
							return dynRefBasePath() + "::<" + innerPath + ">::null()";
						}

						// Fallback: `Null<T>` is represented as `Option<T>`.
						return "None";
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
					var args = params.length == 0 ? "||" : ("|" + argNames.join(", ") + "|");
					var body = TypeHelper.isVoid(ret) ? "{}" : ("{ " + defaultValueForType(ret, pos) + " }");

					var argTys = [for (p in params) rustTypeToString(toRustType(p.t, pos))];
					var fnSig = "dyn Fn(" + argTys.join(", ") + ")";
					if (!TypeHelper.isVoid(ret)) {
						fnSig += " -> " + rustTypeToString(toRustType(ret, pos));
					}
					fnSig += " + Send + Sync";

					var rcTy = rcBasePath() + "<" + fnSig + ">";
					return "{ let __rc: "
						+ rcTy
						+ " = "
						+ rcBasePath()
						+ "::new(move "
						+ args
						+ " "
						+ body
						+ "); "
						+ dynRefBasePath()
						+ "::new(__rc) }";
				}
			case _:
		}

		if (TypeHelper.isBool(t))
			return "false";
		if (TypeHelper.isInt(t))
			return "0";
		if (TypeHelper.isFloat(t))
			return "0.0";
		if (isStringType(t))
			return stringNullDefaultValue();
		if (isDynamicType(t))
			return rustDynamicNullRaw();
		if (isRustVecType(t))
			return "Vec::new()";
		if (isRustHashMapType(t))
			return "std::collections::HashMap::new()";
		if (isArrayType(t)) {
			var elem = arrayElementType(t);
			var elemRust = toRustType(elem, pos);
			return "hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::new()";
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
							var ctorArgs:Array<String> = [];
							switch (sig) {
								case TFun(fnParams, _): {
										for (p in fnParams) {
											ctorArgs.push(defaultValueForType(p.t, pos));
										}
									}
								case _:
							}

							var modName = rustModuleNameForClass(cls);
							var typeName = rustTypeNameForClass(cls);
							var typeParams = params != null
								&& params.length > 0 ? ("::<" + [for (p in params) rustTypeToString(toRustType(p, pos))].join(", ") + ">") : "";
							return "crate::" + modName + "::" + typeName + typeParams + "::new(" + ctorArgs.join(", ") + ")";
						}
					}
				}
			case _:
		}

		return "Default::default()";
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
						var innerStr = rustTypeToString(inner);

						// Some Rust representations already have an explicit null value (no extra `Option<...>` needed).
						if (isRustDynamicPath(innerStr)) {
							return ERaw(rustDynamicNullRaw());
						}
						if (innerStr == "hxrt::string::HxString") {
							return ERaw("hxrt::string::HxString::null()");
						}
						// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
						if (isCoreClassOrEnumHandleType(innerType)) {
							return ERaw("0u32");
						}
						if (StringTools.startsWith(innerStr, "crate::HxRef<")) {
							var prefix = "crate::HxRef<";
							var innerPath = innerStr.substr(prefix.length, innerStr.length - prefix.length - 1);
							return ERaw("crate::HxRef::<" + innerPath + ">::null()");
						}
						if (StringTools.startsWith(innerStr, "hxrt::array::Array<")) {
							var prefix = "hxrt::array::Array<";
							var innerPath = innerStr.substr(prefix.length, innerStr.length - prefix.length - 1);
							return ERaw("hxrt::array::Array::<" + innerPath + ">::null()");
						}
						if (StringTools.startsWith(innerStr, dynRefBasePath() + "<")) {
							var prefix = dynRefBasePath() + "<";
							var innerPath = innerStr.substr(prefix.length, innerStr.length - prefix.length - 1);
							return ERaw(dynRefBasePath() + "::<" + innerPath + ">::null()");
						}

						return ERaw("None");
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
			return ERaw(rustDynamicNullRaw());

		if (isArrayType(t)) {
			var elem = arrayElementType(t);
			var elemRust = toRustType(elem, pos);
			return ERaw("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::null()");
		}

		// Concrete class/Bytes/anon-object values are represented as `HxRef<_>` and can be null.
		if (isBytesType(t) || isHxRefValueType(t) || isRustHxRefType(t) || isAnonObjectType(t)) {
			return ERaw("crate::HxRef::null()");
		}

		// For types that don't have a null representation today (enums, trait objects, etc.),
		// fall back to throwing when/if an out-of-bounds write requires a fill value.
		return ERaw('hxrt::exception::throw(hxrt::dynamic::from(String::from("Null Access")))');
	}

	function compileConstructor(classType:ClassType, varFields:Array<ClassVarData>, f:ClassFuncData):reflaxe.rust.ast.RustAST.RustFunction {
		if (hasAsyncFunctionMeta(f.field.meta)) {
			ensureAsyncPreviewAllowed(f.field.pos);
			#if eval
			Context.error("Constructors cannot be marked `@:async` / `@:rustAsync` in preview mode.", f.field.pos);
			#end
		}
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		var modName = rustModuleNameForClass(classType);
		var rustSelfType = rustTypeNameForClass(classType);
		var selfRefTy = RPath("crate::HxRef<crate::" + modName + "::" + rustClassTypeInst(classType) + ">");

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
				var liftedFieldInit:Map<String, String> = new Map();
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

							function tryLift(e:TypedExpr):Null<{field:String, rhs:String}> {
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
																				var exprStr = reflaxe.rust.ast.RustASTPrinter.printExprForInjection(compileExpr(r));

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
																						var base = needsClone ? (exprStr + ".clone()") : exprStr;
																						if (haxeFieldType != null
																							&& isNullOptionType(haxeFieldType, r.pos)
																							&& !isNullType(v.t)) {
																							"Some(" + base + ")";
																						} else if (wantsOptionWrap) {
																							"Some(" + base + ")";
																						} else {
																							base;
																						}
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

																				var exprStr = reflaxe.rust.ast.RustASTPrinter.printExprForInjection(compiledRhs);
																				var rhsStr = exprStr;
																				if (haxeFieldType != null
																					&& isNullOptionType(haxeFieldType, r.pos)
																					&& !isNullType(r.t)
																					&& !isNullConstExpr(r)) {
																					rhsStr = "Some(" + rhsStr + ")";
																				}
																				if (wantsOptionWrap && !isNullConstExpr(r)) {
																					rhsStr = "Some(" + rhsStr + ")";
																				}
																				if (wantsOptionWrap && isNullConstExpr(r)) {
																					rhsStr = "None";
																				}
																				{field: haxeFieldName, rhs: rhsStr};
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

				var fieldInits:Array<String> = [];
				for (cf in getAllInstanceVarFieldsForStruct(classType)) {
					var haxeName = cf.getHaxeName();
					if (liftedFieldInit.exists(haxeName)) {
						fieldInits.push(rustFieldName(classType, cf) + ": " + liftedFieldInit.get(haxeName));
					} else {
						var def = shouldOptionWrapStructFieldType(cf.type) ? "None" : defaultValueForType(cf.type, cf.pos);
						fieldInits.push(rustFieldName(classType, cf) + ": " + def);
					}
				}
				if (classNeedsPhantomForUnusedTypeParams(classType)) {
					fieldInits.push("__hx_phantom: std::marker::PhantomData");
				}
				var structInit = rustSelfType + " { " + fieldInits.join(", ") + " }";
				var allocExpr = "crate::HxRef::new(" + structInit + ")";

				stmts.push(RLet("self_", false, selfRefTy, ERaw(allocExpr)));

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
					return switch (followType(cf.type)) {
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

				function compilePositionalArgsFor(params:Array<{name:String, t:Type, opt:Bool}>,
						args:Array<TypedExpr>):Array<{param:{name:String, t:Type, opt:Bool}, rust:RustExpr, typed:Null<TypedExpr>}> {
					var out:Array<{param:{name:String, t:Type, opt:Bool}, rust:RustExpr, typed:Null<TypedExpr>}> = [];
					for (i in 0...params.length) {
						var p = params[i];
						if (i < args.length) {
							var a = args[i];
							var compiled = compileExpr(a);
							compiled = coerceArgForParam(compiled, a, p.t);
							out.push({param: p, rust: compiled, typed: a});
						} else if (p.opt) {
							out.push({param: p, rust: nullFillExprForType(p.t, f.field.pos), typed: null});
						} else {
							// Typechecker should prevent this; keep a deterministic fallback.
							out.push({param: p, rust: ERaw(defaultValueForType(p.t, f.field.pos)), typed: null});
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

					var params = ctorParamsFor(cls);
					var compiledArgs = compilePositionalArgsFor(params, callArgs);

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

				var bodyBlock = compileFunctionBody(bodyExpr, f.ret);
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
			args: args,
			ret: selfRefTy,
			body: {stmts: stmts, tail: null}
		};
	}

	function compileInstanceMethod(classType:ClassType, f:ClassFuncData, methodOwner:ClassType):reflaxe.rust.ast.RustAST.RustFunction {
		if (hasAsyncFunctionMeta(f.field.meta)) {
			ensureAsyncPreviewAllowed(f.field.pos);
			#if eval
			Context.error("`@:async`/`@:rustAsync` is currently supported only on static methods.", f.field.pos);
			#end
		}
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		var generics = rustGenericParamsFromFieldMeta(f.field.meta, [for (p in f.field.params) p.name]);
		var selfName = exprUsesThis(f.expr) ? "self_" : "_self_";
		args.push({
			name: selfName,
			ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">")
		});
		var body = {stmts: [], tail: null};
		var prevOwner = currentMethodOwnerType;
		currentMethodOwnerType = methodOwner;
		var prevField = currentMethodField;
		currentMethodField = f.field;
		withFunctionContext(f.expr, [for (a in f.args) a.getName()], f.ret, () -> {
			var prevThisIdent = currentThisIdent;
			if (selfName == "self_")
				currentThisIdent = "__hx_this";
			for (a in f.args) {
				args.push({
					name: rustArgIdent(a.getName()),
					ty: toRustType(a.type, f.field.pos)
				});
			}
			body = compileFunctionBody(f.expr, f.ret);
			if (selfName == "self_") {
				var modName = rustModuleNameForClass(classType);
				var thisTy = RPath("crate::HxRef<crate::" + modName + "::" + rustClassTypeInst(classType) + ">");
				body.stmts.unshift(RLet("__hx_this", false, thisTy, ECall(EField(EPath(selfName), "self_ref"), [])));
			}
			currentThisIdent = prevThisIdent;
		});
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

	function compileStaticMethod(classType:ClassType, f:ClassFuncData):reflaxe.rust.ast.RustAST.RustFunction {
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		var generics = rustGenericParamsFromFieldMeta(f.field.meta, [for (p in f.field.params) p.name]);
		var body = {stmts: [], tail: null};
		var isAsyncMethod = hasAsyncFunctionMeta(f.field.meta);
		var asyncInnerRet:Null<Type> = null;
		if (isAsyncMethod) {
			ensureAsyncPreviewAllowed(f.field.pos);
			asyncInnerRet = rustFutureInnerType(f.ret);
			if (asyncInnerRet == null) {
				#if eval
				Context.error("`@:async`/`@:rustAsync` static methods must return `rust.async.Future<T>` (got `" + TypeTools.toString(f.ret) + "`).",
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
				var innerBody = compileFunctionBody(f.expr, asyncInnerRet);
				var innerBlockExpr = EBlock(innerBody);
				var innerBlockSrc = reflaxe.rust.ast.RustASTPrinter.printExprForInjection(innerBlockExpr);
				body = {
					stmts: [RReturn(ERaw("Box::pin(async move " + innerBlockSrc + ")"))],
					tail: null
				};
			} else {
				body = compileFunctionBody(f.expr, f.ret);
			}
		}, isAsyncMethod);
		currentMethodField = prevField;

		function needsCrateVisibility(cls:ClassType, cf:ClassField):Bool {
			return (cls.meta != null && (cls.meta.has(":allow") || cls.meta.has(":access")))
				|| (cf.meta != null && (cf.meta.has(":allow") || cf.meta.has(":access")));
		}

		var isPub = f.field.isPublic || isAccessorForPublicPropertyStatic(classType, f.field);
		return {
			name: rustMethodName(classType, f.field),
			isPub: isPub,
			vis: (!isPub && needsCrateVisibility(classType, f.field)) ? RustVisibility.VPubCrate : null,
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
				args: [
					{name: "_self_", ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">")}
				],
				ret: RPath("()"),
				body: {stmts: [RSemi(ERaw("todo!()"))], tail: null}
			};
		}

		var bodyExpr = unwrapFieldFunctionBody(ex);
		var sig = switch (followType(cf.type)) {
			case TFun(params, ret): {params: params, ret: ret};
			case _: null;
		};
		if (sig == null) {
			return {
				name: superThunkName(owner, cf),
				isPub: false,
				args: [
					{name: "_self_", ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">")}
				],
				ret: RPath("()"),
				body: {stmts: [RSemi(ERaw("todo!()"))], tail: null}
			};
		}

		var selfName = exprUsesThis(bodyExpr) ? "self_" : "_self_";
		var args:Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
		args.push({
			name: selfName,
			ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">")
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

		var generics = rustGenericParamsFromFieldMeta(cf.meta, [for (p in cf.params) p.name]);
		var body = {stmts: [], tail: null};
		var prevOwner = currentMethodOwnerType;
		currentMethodOwnerType = owner;
		var prevField = currentMethodField;
		currentMethodField = cf;
		withFunctionContext(bodyExpr, argNames, sig.ret, () -> {
			var prevThisIdent = currentThisIdent;
			if (selfName == "self_")
				currentThisIdent = "__hx_this";
			body = compileFunctionBody(bodyExpr, sig.ret);
			if (selfName == "self_") {
				var modName = rustModuleNameForClass(classType);
				var thisTy = RPath("crate::HxRef<crate::" + modName + "::" + rustClassTypeInst(classType) + ">");
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

	function rustGenericParamsFromFieldMeta(meta:haxe.macro.Type.MetaAccess, fallback:Array<String>):Array<String> {
		var out:Array<String> = [];
		var found = false;

		for (entry in meta.get()) {
			if (entry.name != ":rustGeneric")
				continue;
			found = true;

			if (entry.params == null || entry.params.length == 0) {
				#if eval
				Context.error("`@:rustGeneric` requires a single parameter.", entry.pos);
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
									Context.error("`@:rustGeneric` array must contain only strings.", entry.pos);
									#end
							}
						}
					}
				case _:
					#if eval
					Context.error("`@:rustGeneric` must be a string or array of strings.", entry.pos);
					#end
			}
		}

		return found ? out : fallback;
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
					RPath(s);
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

	function rustGenericNamesFromDecls(decls:Array<String>):Array<String> {
		var out:Array<String> = [];
		for (d in decls) {
			var s = StringTools.trim(d);
			if (s.length == 0)
				continue;
			var colon = s.indexOf(":");
			var name = colon >= 0 ? s.substr(0, colon) : s;
			name = StringTools.trim(name);
			// Be defensive: `T where ...` isn't valid in Rust generics, but avoid generating garbage names.
			var space = name.indexOf(" ");
			if (space >= 0)
				name = name.substr(0, space);
			out.push(name);
		}
		return out;
	}

	function rustGenericDeclsForClass(classType:ClassType):Array<String> {
		var out:Array<String> = [];
		var found = false;

		for (entry in classType.meta.get()) {
			if (entry.name != ":rustGeneric")
				continue;
			found = true;

			if (entry.params == null || entry.params.length == 0) {
				#if eval
				Context.error("`@:rustGeneric` requires a single parameter.", entry.pos);
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
									Context.error("`@:rustGeneric` array must contain only strings.", entry.pos);
									#end
							}
						}
					}
				case _:
					#if eval
					Context.error("`@:rustGeneric` must be a string or array of strings.", entry.pos);
					#end
			}
		}

		if (found)
			return out;

		// Default bounds policy for class-level generics:
		//
		// Class instances are interior-mutable (`HxRef<_>`) and methods commonly need to return
		// values by value while borrowing `self`. To preserve Haxe's "values are reusable" semantics,
		// codegen often clones non-`Copy` fields/values, so we default to `T: Clone` for class params.
		var bounded:Array<String> = [];
		for (p in classType.params)
			bounded.push(p.name + ": Clone + Send + Sync");
		return bounded;
	}

	function rustClassTypeInst(classType:ClassType):String {
		var base = rustTypeNameForClass(classType);
		var decls = rustGenericDeclsForClass(classType);
		var names = rustGenericNamesFromDecls(decls);
		return names.length > 0 ? (base + "<" + names.join(", ") + ">") : base;
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

		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			if (haxeTypeContainsClassTypeParam(cf.type, nameSet))
				return false;
		}
		return true;
	}

	function compileFunctionBody(e:TypedExpr, expectedReturn:Null<Type> = null):RustBlock {
		var allowTail = true;
		if (expectedReturn != null && TypeHelper.isVoid(expectedReturn)) {
			allowTail = false;
		}

		var out:RustBlock = switch (e.expr) {
			case TBlock(exprs): compileBlock(exprs, allowTail, expectedReturn);
			case _: {
					// Single-expression function body
					{stmts: [compileStmt(e)], tail: null};
				}
		};

		// Rust function parameters are immutable by default. Haxe code (including upstream std)
		// occasionally assigns to arguments (e.g. `s = urlEncode(s)`), which requires `mut`.
		//
		// Keep the signature stable (no `mut` in params) and shadow mutated args in the body:
		// `let mut s = s;`
		if (currentMutatedArgs != null && currentMutatedArgs.length > 0) {
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

			if (allowTail && isLast && !TypeHelper.isVoid(e.t) && !isStmtOnlyExpr(e)) {
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
						if (currentMutatedLocals != null && currentMutatedLocals.exists(v.id) && i + 1 < exprs.length) {
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
									&& rustTypeToString(rustTy) == "String") {
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
						// Idiomatic move optimization (conservative, straight-line only):
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
									&& rustTypeToString(rustTy) == "String") {
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

			if (!handled) {
				stmts.push(compileStmt(e));
			}

			// Avoid emitting Rust code that is statically unreachable (and triggers `unreachable_code` warnings).
			// Haxe may type-check expressions after `throw`/`return` even when they can never run.
			if (exprAlwaysDiverges(e))
				break;
		}

		return {stmts: stmts, tail: tail};
	}

	function isStmtOnlyExpr(e:TypedExpr):Bool {
		return switch (e.expr) {
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

	function compileStmt(e:TypedExpr):RustStmt {
		return switch (e.expr) {
			case TBlock(exprs): {
					// Haxe desugars `for (x in iterable)` into:
					// `{ var it = iterable.iterator(); while (it.hasNext()) { var x = it.next(); body } }`
					//
					// For Rusty surfaces (Vec/Slice), lower this back to a Rust `for` loop and avoid
					// having to represent Haxe's `Iterator<T>` type in the backend.
					function iterClonedExpr(x:TypedExpr):RustExpr {
						var base = ECall(EField(compileExpr(x), "iter"), []);
						return ECall(EField(base, iterBorrowMethod(x.t)), []);
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

					function extractRustForIterable(init:TypedExpr):Null<RustExpr> {
						function unwrapMetaParenCast(e:TypedExpr):TypedExpr {
							var u = unwrapMetaParen(e);
							return switch (u.expr) {
								case TCast(e1, _): unwrapMetaParenCast(e1);
								case _: u;
							}
						}

						var u = unwrapMetaParenCast(init);
						return switch (u.expr) {
							case TCall(callExpr, callArgs): {
									var c = unwrapMetaParenCast(callExpr);
									switch (c.expr) {
										// Instance `obj.iterator()` (may print as `obj.iter()` due to @:native).
										case TField(obj, fa): {
												var objU = unwrapMetaParenCast(obj);

												// The while-loop shape already proved this "iterator" variable is used
												// with `.hasNext()` / `.next()`. For Rusty surfaces, recover an idiomatic
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
					#if eval
					if (Context.defined("rust_debug_string_types")
						&& useNullableStringRepresentation()
						&& rustTypeToString(rustTy) == "String") {
						var vt = TypeTools.toString(v.t);
						var it = init != null ? TypeTools.toString(init.t) : "<none>";
						Context.warning("rust_debug_string_types TVar `" + name + "`: v.t=" + vt + ", init.t=" + it, e.pos);
					}
					#end
					var initExpr = init != null ? compileExpr(init) : null;
					if (initExpr != null) {
						// Haxe's inliner/desugarer frequently introduces `_g*` temporaries to preserve evaluation
						// order (e.g. for comprehensions / iterator lowering). For `Array<T>` (mapped to `Vec<T>`),
						// these temporaries should not *move* the original value.
						//
						// NOTE: `Array<T>` now maps to `hxrt::array::Array<T>` (Rc-backed), so cloning is cheap
						// and handled by `maybeCloneForReuseValue(...)` below when needed.

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

						// Coerce the initializer to the declared local type (handles `Null<T>` Option wrapping,
						// trait upcasts, structural typedef adapters, numeric widening, etc).
						initExpr = coerceExprToExpected(initExpr, init, v.t);
					}
					var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(v.id);
					RLet(name, mutable, rustTy, initExpr);
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
					if (normalWhile) {
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
						stmts.push(RSemi(EIf(EUnary("!", condExpr), EBlock({stmts: [RSemi(ERaw("break"))], tail: null}), null)));
						RLoop({stmts: stmts, tail: null});
					}
				}
			case TFor(v, iterable, body): {
					function iterCloned(x:TypedExpr):RustExpr {
						// `hxrt::array::Array<T>::iter()` returns an owned iterator; do not append `.cloned()`.
						if (isArrayType(x.t)) {
							return ECall(EField(compileExpr(x), "iter"), []);
						}
						var base = ECall(EField(compileExpr(x), "iter"), []);
						return ECall(EField(base, iterBorrowMethod(x.t)), []);
					}

					var it:RustExpr = switch (unwrapMetaParen(iterable).expr) {
						// Many custom iterables typecheck by providing `iterator()`. We lower specific
						// rusty surfaces to Rust iterators to avoid moving values (Haxe values are reusable).
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
					RFor(rustLocalDeclIdent(v), it, compileVoidBody(body));
				}
			case TBreak:
				RSemi(ERaw("break"));
			case TContinue:
				RSemi(ERaw("continue"));
			case TReturn(ret): {
					var retExpr = ret;
					if (currentFunctionIsAsync && ret != null) {
						var inner = extractAsyncReadyValue(ret);
						if (inner != null) {
							retExpr = inner;
						}
					}
					var ex = retExpr != null ? compileExpr(retExpr) : null;
					if (retExpr != null && ex != null) {
						ex = coerceExprToExpected(ex, retExpr, currentFunctionReturn);
					}
					RReturn(ex);
				}
			case TBinop(OpAssignOp(OpAdd), lhs, rhs) if (isStringType(followType(e.t)) || isStringType(followType(lhs.t)) || isStringType(followType(rhs.t))): {
					// Statement-position `x += y` where the result is unused.
					//
					// `compileExpr` must preserve the expression value, which requires cloning the updated
					// String to avoid moving it. When used as a statement, that clone becomes a `must_use`
					// warning. Emit a unit block that only performs the assignment.
					switch (unwrapMetaParen(lhs).expr) {
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
		var prevArgNames = currentArgNames;
		var prevLocalNames = currentLocalNames;
		var prevLocalUsed = currentLocalUsed;
		var prevEnumParamBinds = currentEnumParamBinds;
		var prevReturn = currentFunctionReturn;
		var prevMutatedArgs = currentMutatedArgs;
		var prevIsAsync = currentFunctionIsAsync;

		currentMutatedLocals = collectMutatedLocals(bodyExpr);
		currentLocalReadCounts = collectLocalReadCounts(bodyExpr);
		currentArgNames = [];
		currentLocalNames = [];
		currentLocalUsed = [];
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

		var out = fn();

		currentMutatedLocals = prevMutated;
		currentLocalReadCounts = prevReadCounts;
		currentArgNames = prevArgNames;
		currentLocalNames = prevLocalNames;
		currentLocalUsed = prevLocalUsed;
		currentEnumParamBinds = prevEnumParamBinds;
		currentFunctionReturn = prevReturn;
		currentMutatedArgs = prevMutatedArgs;
		currentFunctionIsAsync = prevIsAsync;
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

	function collectMutatedLocals(root:TypedExpr):Map<Int, Bool> {
		var mutated:Map<Int, Bool> = [];
		var declaredWithoutInit:Map<Int, Bool> = [];
		var assignCounts:Map<Int, Int> = [];

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
						if (init == null) {
							// Rust allows `let x; x = value;` without `mut` (the first assignment is initialization).
							declaredWithoutInit.set(v.id, true);
						}

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
									} else {
										var prev = assignCounts.exists(v.id) ? assignCounts.get(v.id) : 0;
										assignCounts.set(v.id, prev + 1);
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

		// If a local was declared without an initializer, only require `mut` when it is assigned more than once.
		for (id in assignCounts.keys()) {
			if (assignCounts.get(id) > 1)
				mutated.set(id, true);
		}
		return mutated;
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

	function compileExpr(e:TypedExpr):RustExpr {
		// Target code injection: __rust__("...{0}...", arg0, ...)
		//
		// Note: injected Rust strings frequently include their own explicit borrow/clone logic.
		// When compiling placeholder arguments we suppress implicit "clone-on-local-use" so
		// patterns like `{ let __o = out.borrow_mut(); ... }` remain valid.
		var prevInj = inCodeInjectionArg;
		inCodeInjectionArg = true;
		var injected = TargetCodeInjection.checkTargetCodeInjectionGeneric(options.targetCodeInjectionName ?? "__rust__", e, this);
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
				return ERaw(literal != null ? literal : "");
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
			return ERaw(rendered.toString());
		}

		return switch (e.expr) {
			case TConst(c): switch (c) {
					case TInt(v): ELitInt(v);
					case TFloat(s): ELitFloat(Std.parseFloat(s));
					case TString(s): stringLiteralExpr(s);
					case TBool(b): ELitBool(b);
					case TNull:
						if (isNullOptionType(e.t, e.pos)) {
							ERaw("None");
						} else if (isStringType(e.t)) {
							stringNullExpr();
						} else if (mapsToRustDynamic(e.t, e.pos)) {
							ERaw(rustDynamicNullRaw());
						} else {
							// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids.
							// Use `0u32` as the null sentinel (matches `Type.resolveClass`/`resolveEnum` stubs today).
							if (isCoreClassOrEnumHandleType(e.t)) {
								return ERaw("0u32");
							}

							var rt = toRustType(e.t, e.pos);
							switch (rt) {
								case RPath(p) if (StringTools.startsWith(p, "crate::HxRef<")): {
										var inner = p.substr("crate::HxRef<".length, p.length - "crate::HxRef<".length - 1);
										ECall(ERaw("crate::HxRef::<" + inner + ">::null"), []);
									}
								case RPath(p) if (StringTools.startsWith(p, "hxrt::array::Array<")): {
										var inner = p.substr("hxrt::array::Array<".length, p.length - "hxrt::array::Array<".length - 1);
										ECall(ERaw("hxrt::array::Array::<" + inner + ">::null"), []);
									}
								case RPath(p) if (StringTools.startsWith(p, dynRefBasePath() + "<")): {
										var prefix = dynRefBasePath() + "<";
										var inner = p.substr(prefix.length, p.length - prefix.length - 1);
										ECall(ERaw(dynRefBasePath() + "::<" + inner + ">::null"), []);
									}
								case RString:
									stringNullExpr();
								case _:
									ECall(EPath("Default::default"), []);
							}
						}
					case TThis: EPath(currentThisIdent != null ? currentThisIdent : "self_");
					case _: unsupported(e, "const");
				}

			case TArrayDecl(values): {
					// Haxe `Array<T>` literal: `[]` or `[a, b]` -> `hxrt::array::Array::<T>::new()` or `Array::from_vec(vec![...])`
					if (values.length == 0) {
						var elem = arrayElementType(e.t);
						var elemRust = toRustType(elem, e.pos);
						ECall(ERaw("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::new"), []);
					} else {
						var elem = arrayElementType(e.t);
						var elemRust = toRustType(elem, e.pos);
						var vecExpr = EMacroCall("vec", [for (v in values) maybeCloneForReuseValue(compileExpr(v), v)]);
						ECall(ERaw("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::from_vec"), [vecExpr]);
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
											return ERaw("0u32");
										}
									}
								case _:
							}

							var rt = toRustType(t, e.pos);
							switch (rt) {
								case RPath(p) if (StringTools.startsWith(p, "crate::HxRef<")):
									{
										var inner = p.substr("crate::HxRef<".length, p.length - "crate::HxRef<".length - 1);
										return ECall(ERaw("crate::HxRef::<" + inner + ">::null"), []);
									}
								case RPath(p) if (StringTools.startsWith(p, "hxrt::array::Array<")):
									{
										var inner = p.substr("hxrt::array::Array<".length, p.length - "hxrt::array::Array<".length - 1);
										return ECall(ERaw("hxrt::array::Array::<" + inner + ">::null"), []);
									}
								case RPath(p) if (StringTools.startsWith(p, dynRefBasePath() + "<")):
									{
										var prefix = dynRefBasePath() + "<";
										var inner = p.substr(prefix.length, p.length - prefix.length - 1);
										return ECall(ERaw(dynRefBasePath() + "::<" + inner + ">::null"), []);
									}
								case _:
									return ECall(EPath("Default::default"), []);
							}
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
							return ERaw("__hx_dyn.downcast_ref::<" + tyStr + ">().unwrap().clone()");
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
									tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []), ERaw("None"),
										ECall(EPath("Some"), [innerIsDyn ? EPath("__hx_dyn") : dynDowncastNonNull(inner)]))
								});
							}

							var expectedRust = rustTypeToString(toRustType(e.t, e.pos));
							var isNullableRef = StringTools.startsWith(expectedRust, "crate::HxRef<")
								|| StringTools.startsWith(expectedRust, "hxrt::array::Array<")
								|| StringTools.startsWith(expectedRust, dynRefBasePath() + "<");
							return EBlock({
								stmts: [RLet("__hx_dyn", false, null, dynExpr)],
								tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []),
									isStringType(e.t) ? stringNullExpr() : (isNullableRef ? nullExprForExpected(e.t) : nullAccessThrow()),
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
							return EBlock({
								stmts: [RLet("__hx_opt", false, null, getCall)],
								tail: EMatch(EPath("__hx_opt"), [
									{pat: PTupleStruct("Some", [PBind("__v")]), expr: EPath("__v")},
									{pat: PPath("None"), expr: ERaw("None")}
								])
							});
						}
						getCall;
					} else {
						ECall(EField(compileExpr(arr), "get_unchecked"), [idx]);
					}
				}

			case TLocal(v):
				if (inlineLocalSubstitutions != null && inlineLocalSubstitutions.exists(v.name)) {
					return inlineLocalSubstitutions.get(v.name);
				}
				EPath(rustLocalRefIdent(v));

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
					EIf(condExpr, compileBranchExpr(eThen), compileBranchExpr(eElse));
				}

			case TBlock(exprs):
				EBlock(compileBlock(exprs));

			case TCall(callExpr, args):
				compileCall(callExpr, args, e);

			case TNew(clsRef, typeParams, args): {
					// `new Array<T>()` must lower to `hxrt::array::Array::<T>::new()` rather than an extern `Array::new()`.
					if (isArrayType(e.t) && (args == null || args.length == 0)) {
						var elem = arrayElementType(e.t);
						var elemRust = toRustType(elem, e.pos);
						return ECall(ERaw("hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::new"), []);
					}
					var cls = clsRef.get();
					if (cls != null && !cls.isExtern && isMainClass(cls)) {
						return unsupported(e, "new main class");
					}
					var ctorPath = (cls != null && cls.isExtern ? rustExternBasePath(cls) : null);
					var ctorBase = if (ctorPath != null) {
						ctorPath;
					} else if (cls != null && cls.isExtern) {
						cls.name;
					} else if (cls != null) {
						"crate::" + rustModuleNameForClass(cls) + "::" + rustTypeNameForClass(cls);
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
					if (cls != null && cls.constructor != null) {
						var cf = cls.constructor.get();
						if (cf != null) {
							switch (followType(cf.type)) {
								case TFun(params, _):
									ctorParamDefs = params;
								case _:
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
								// Optional-without-default: implicit `null`.
								// Important: this is NOT always `None` because many Rust
								// representations have their own explicit null value.
								outArgs.push(nullFillExprForType(p.t, e.pos));
							} else {
								// Typechecker should prevent this; keep a deterministic fallback.
								outArgs.push(ERaw(defaultValueForType(p.t, e.pos)));
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
				ERaw("break");

			case TContinue:
				ERaw("continue");

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
						Context.error("`@:await` / `@:rustAwait` is only allowed inside `@:async` / `@:rustAsync` functions.", e.pos);
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
					// NOTE: This is a baseline: we emit a `move` closure and rely on captured values
					// being owned (cloned) so the closure can be `'static` for storage/passing.
					var baseArgNames:Array<String> = [];
					for (a in fn.args) {
						var n = (a.v != null && a.v.name != null && a.v.name.length > 0) ? a.v.name : "a";
						baseArgNames.push(n);
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
						body = compileFunctionBody(fn.expr, fn.t);
					});

					var argTys = [for (a in fn.args) rustTypeToString(toRustType(a.v.t, e.pos))];
					var sig = "dyn Fn(" + argTys.join(", ") + ")";
					if (!TypeHelper.isVoid(fn.t)) {
						sig += " -> " + rustTypeToString(toRustType(fn.t, e.pos));
					}
					sig += " + Send + Sync";

					var rcTy:RustType = RPath(rcBasePath() + "<" + sig + ">");
					var rcExpr:RustExpr = ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, body, true)]);
					EBlock({
						stmts: [RLet("__rc", false, rcTy, rcExpr)],
						tail: ECall(EPath(dynRefBasePath() + "::new"), [EPath("__rc")])
					});
				}

			case TCast(e1, _): {
					var inner = compileExpr(e1);
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
							return EBlock({stmts: stmts, tail: EIf(isNull, ERaw("None"), EIf(hasOpt, thenExpr, elseExpr))});
						}

						var tyStr = rustTypeToString(toRustType(target, pos));
						return EBlock({
							stmts: [RLet("__hx_dyn", false, null, dynExpr)],
							tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []), nullAccessThrow(),
								ERaw("__hx_dyn.downcast_ref::<" + tyStr + ">().unwrap().clone()"))
						});
					}

					// Numeric casts (`Int` <-> `Float`) must be explicit in Rust.
					if (!isNullType(e1.t)
						&& !isNullType(e.t)
						&& (TypeHelper.isInt(fromT) || TypeHelper.isFloat(fromT))
						&& (TypeHelper.isInt(toT) || TypeHelper.isFloat(toT))) {
						var target = rustTypeToString(toRustType(toT, e.pos));
						ECast(inner, target);
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
						// In Rust output, `Null<T>` is `Option<T>`, so unwrap.
						ECall(EField(inner, "unwrap"), []);
					} else if (!isNullOptionType(e1.t, e1.pos) && isNullOptionType(e.t, e.pos)) {
						// Explicit casts from `T` to `Null<T>` are treated as "wrap into nullability".
						ECall(EPath("Some"), [inner]);
					} else {
						inner;
					}
				}

			case TObjectDecl(fields): {
					// Anonymous objects / structural records.
					//
					// Special cases:
					// - `{ key: ..., value: ... }` (used by `KeyValueIterator<K,V>`) lowers to a concrete struct.
					// - Everything else lowers to `crate::HxRef<hxrt::anon::Anon>` for Haxe aliasing semantics.

					// `{ key: ..., value: ... }` (exactly) -> `hxrt::iter::KeyValue { ... }`
					if (fields != null && fields.length == 2) {
						var keyExpr:Null<TypedExpr> = null;
						var valueExpr:Null<TypedExpr> = null;
						for (f in fields) {
							switch (f.name) {
								case "key": keyExpr = f.expr;
								case "value": valueExpr = f.expr;
								case _:
							}
						}

						if (keyExpr != null && valueExpr != null) {
							return EStructLit("hxrt::iter::KeyValue", [
								{name: "key", expr: compileExpr(keyExpr)},
								{name: "value", expr: compileExpr(valueExpr)},
							]);
						}
					}

					// General record literal -> `{ let __o = Rc::new(RefCell::new(Anon::new())); { let mut __b = __o.borrow_mut(); __b.set(...); } __o }`
					function typedNoneForNull(t:Type, pos:haxe.macro.Expr.Position):RustExpr {
						var inner = nullOptionInnerType(t, pos);
						if (inner == null)
							return ERaw("None");
						var innerRust = rustTypeToString(toRustType(inner, pos));
						return ERaw("Option::<" + innerRust + ">::None");
					}

					var stmts:Array<RustStmt> = [];
					var objName = "__o";

					var newAnon = ECall(EPath("hxrt::anon::Anon::new"), []);
					var newRef = ECall(EPath("crate::HxRef::new"), [newAnon]);
					stmts.push(RLet(objName, false, null, newRef));

					var innerStmts:Array<RustStmt> = [];
					innerStmts.push(RLet("__b", true, null, ECall(EField(EPath(objName), "borrow_mut"), [])));
					if (fields != null) {
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
					ERaw(typeIdLiteralForClass(cls));
				}
			case TEnumDecl(enRef): {
					var en = enRef.get();
					if (en == null)
						return unsupported(fullExpr, "type expr (missing enum)");
					ERaw(typeIdLiteralForEnum(en));
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
		var payload = ECall(EPath("hxrt::dynamic::from"), [compileExpr(thrown)]);
		return ECall(EPath("hxrt::exception::throw"), [payload]);
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

		var rustTy = toRustType(c.v.t, c.expr.pos);
		var downcast = ECall(ERaw(exVarName + ".downcast::<" + rustTypeToString(rustTy) + ">"), []);

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

			var elseExpr:RustExpr = edef != null ? compileSwitchArmExpr(edef, expectedReturn) : defaultSwitchArmExpr(expectedReturn);

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
		var arms:Array<RustMatchArm> = [];

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

		function enumParamBindsForCase(values:Array<TypedExpr>):Null<Map<String, String>> {
			var scrutLocalId:Null<Int> = null;
			switch (unwrapMetaParen(switchExpr).expr) {
				case TLocal(v):
					scrutLocalId = v.id;
				case _:
			}
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
										case TLocal(_): {
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
				patterns.push(p);
			}

			if (patterns.length == 0)
				continue;
			var pat = patterns.length == 1 ? patterns[0] : POr(patterns);
			var binds = enumParamBindsForCase(c.values);
			var armExpr = withEnumParamBinds(binds, () -> compileSwitchArmExpr(c.expr, expectedReturn));
			arms.push({pat: pat, expr: armExpr});
		}

		arms.push({pat: PWildcard, expr: edef != null ? compileSwitchArmExpr(edef, expectedReturn) : defaultSwitchArmExpr(expectedReturn)});
		return EMatch(scrutinee, arms);
	}

	function compileEnumIndexSwitch(enumExpr:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, edef:Null<TypedExpr>,
			expectedReturn:Type):RustExpr {
		var en = enumTypeFromType(enumExpr.t);
		if (en == null)
			return unsupported(enumExpr, "enum switch");

		var scrutinee = ECall(EField(compileExpr(enumExpr), "clone"), []);
		var arms:Array<RustMatchArm> = [];
		var matchedVariants = new Map<String, Bool>();

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
				patterns.push(pat);
			}

			if (patterns.length == 0)
				continue;
			var pat = patterns.length == 1 ? patterns[0] : POr(patterns);
			var binds = singleEf != null ? enumParamBindsForSingleVariant(singleEf) : null;
			var armExpr = withEnumParamBinds(binds, () -> compileSwitchArmExpr(c.expr, expectedReturn));
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
				expr: edef != null ? compileSwitchArmExpr(edef, expectedReturn) : defaultSwitchArmExpr(expectedReturn)
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
			case TReturn(_) | TBreak | TContinue | TThrow(_):
				EBlock(compileVoidBody(expr));
			case _:
				coerceExprToExpected(compileExpr(expr), expr, expectedReturn);
		}
	}

	function defaultSwitchArmExpr(expectedReturn:Type):RustExpr {
		return if (TypeHelper.isVoid(expectedReturn)) {
			EBlock({stmts: [], tail: null});
		} else {
			ERaw("todo!()");
		}
	}

	function compilePattern(value:TypedExpr):Null<RustPattern> {
		var v = unwrapMetaParen(value);
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
										case TLocal(_):
											var bindName = argc == 1 ? "__p" : "__p" + i;
											PBind(bindName);
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
		var innerRust = rustTypeToString(toRustType(innerType, pos));
		// `Dynamic` already carries its own null sentinel (`Dynamic::null()`).
		if (isRustDynamicPath(innerRust))
			return null;
		// Portable/idiomatic `String` uses `HxString` with an internal null sentinel.
		if (innerRust == "hxrt::string::HxString")
			return null;

		// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
		if (isCoreClassOrEnumHandleType(innerType))
			return null;

		if (StringTools.startsWith(innerRust, "crate::HxRef<"))
			return null;
		if (StringTools.startsWith(innerRust, "hxrt::array::Array<"))
			return null;
		if (StringTools.startsWith(innerRust, dynRefBasePath() + "<"))
			return null;
		return innerType;
	}

	function isNullOptionType(t:Type, pos:haxe.macro.Expr.Position):Bool {
		return nullOptionInnerType(t, pos) != null;
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
						switch (cf.getHaxeName()) {
							case "hasNext": hasNext = true;
							case "next": next = true;
							case _:
						}
					}
					hasNext && next
					;
				}
			case _:
				false;
		}
	}

	function isKeyValueStructType(t:Type):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TAnonymous(anonRef): {
					var anon = anonRef.get();
					if (anon == null || anon.fields == null || anon.fields.length != 2)
						return false;
					var key = false;
					var value = false;
					for (cf in anon.fields) {
						switch (cf.getHaxeName()) {
							case "key": key = true;
							case "value": value = true;
							case _:
						}
					}
					key && value
					;
				}
			case _:
				false;
		}
	}

	function isAnonObjectType(t:Type):Bool {
		var ft = followType(t);
		return switch (ft) {
			case TAnonymous(_): !isIteratorStructType(t) && !isKeyValueStructType(t);
			case _:
				false;
		}
	}

	function isHaxeReusableValueType(t:Type):Bool {
		// Types that behave like Haxe reference values (must not be "moved" by Rust assignments).
		// - `Array<T>` is `hxrt::array::Array<T>` (Rc-backed).
		// - class instances / Bytes are `HxRef<T>` (Rc-backed).
		// - `String` is immutable and reusable in Haxe (needs clone in Rust when re-used).
		// - structural `Iterator<T>` maps to `hxrt::iter::Iter<T>` (Rc-backed).
		// - general anonymous objects map to `crate::HxRef<hxrt::anon::Anon>` (Rc-backed).
		return isArrayType(t) || isHxRefValueType(t) || isRustHxRefType(t) || isStringType(t) || isIteratorStructType(t) || isAnonObjectType(t)
			|| isDynamicType(t);
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

		// If the local is used only once in this function body, prefer moving it to avoid redundant clones.
		var localId = unwrapToLocalId(valueExpr);
		if (localId != null && currentLocalReadCounts != null && currentLocalReadCounts.exists(localId)) {
			var reads = currentLocalReadCounts.get(localId);
			if (reads <= 1)
				return expr;
		}

		if (isLocalExpr(valueExpr) && !isObviousTemporaryExpr(valueExpr) && isHaxeReusableValueType(valueExpr.t)) {
			return ECall(EField(expr, "clone"), []);
		}
		return expr;
	}

	function coerceExprToExpected(compiled:RustExpr, valueExpr:TypedExpr, expected:Null<Type>):RustExpr {
		if (expected == null)
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

		var expectedRust = rustTypeToString(toRustType(expected, valueExpr.pos));
		var actualRust = rustTypeToString(toRustType(valueExpr.t, valueExpr.pos));

		// Numeric widening: Haxe allows `Int` values where `Float` is expected.
		// Rust requires an explicit cast.
		if (TypeHelper.isFloat(followType(expected)) && TypeHelper.isInt(followType(valueExpr.t))) {
			return ECast(compiled, "f64");
		}

		var expectedIsDyn = mapsToRustDynamic(expected, valueExpr.pos);
		var actualIsDyn = mapsToRustDynamic(valueExpr.t, valueExpr.pos);

		// `Null<T>` (Option<T>) used where a non-null `T` is expected.
		//
		// Haxe allows this implicitly in many places (especially in upstream stdlib for "dynamic-ish"
		// targets). In Rust we must unwrap the `Option<T>`.
		//
		// Semantics: `None` is a "Null Access" error (catchable via hxrt exception machinery).
		var actualNullInner = nullOptionInnerType(valueExpr.t, valueExpr.pos);
		if (!expectedIsDyn && actualNullInner != null) {
			// Avoid moving a reusable local `Option` by cloning it first.
			var optExpr = if (isLocalExpr(valueExpr) && !isObviousTemporaryExpr(valueExpr)) {
				ECall(EField(compiled, "clone"), []);
			} else {
				compiled;
			}

			return EBlock({
				stmts: [RLet("__hx_opt", false, null, optExpr)],
				tail: EMatch(EUnary("&", EPath("__hx_opt")), [
					{pat: PTupleStruct("Some", [PBind("__v")]), expr: ECall(EField(EPath("__v"), "clone"), [])},
					{pat: PPath("None"), expr: isStringType(expected) ? stringNullExpr() : nullAccessThrow()}
				])
			});
		}

		// String representation bridge (`String` <-> `HxString`) for nullable-string mode.
		//
		// We intentionally do this after `Null<T>` unwrapping so `Option<String>` can unwrap first.
		if (expectedRust == "hxrt::string::HxString" && !actualIsDyn) {
			// `HxString::from(HxString)` is valid (`From<T> for T`), so this safely handles
			// both already-wrapped and plain `String`/`&str` expressions.
			if (isDefaultDefaultCall(compiled))
				return compiled;
			return wrapRustStringExpr(compiled);
		}
		if (expectedRust == "String" && actualRust == "hxrt::string::HxString") {
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
							ERaw(typeIdLiteralForClass(cls));
					}
				case TEnum(enumRef, _): {
						var en = enumRef.get();
						en != null ? ERaw(typeIdLiteralForEnum(en)) : null;
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
					tail: EIf(isNull, stringNullExpr(), EIf(hasStr, strExpr, EIf(hasHxStr, hxStrExpr, nullAccessThrow())))
				});
			}

			var tyStr = rustTypeToString(toRustType(expected, valueExpr.pos));
			return EBlock({
				stmts: [RLet("__hx_dyn", false, null, compiled)],
				tail: EIf(ECall(EField(EPath("__hx_dyn"), "is_null"), []), nullAccessThrow(), ERaw("__hx_dyn.downcast_ref::<" + tyStr + ">().unwrap().clone()"))
			});
		}

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
			// so `valueExpr.t` can appear *anonymous* even though the expression is a concrete class
			// instance. Prefer the expression shape (`TNew`) when available.
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

			var actualExpr = unwrapMetaParenCast(valueExpr);
			var actualCls:Null<ClassType> = switch (actualExpr.expr) {
				case TNew(clsRef, _, _): clsRef.get();
				case _:
					switch (followType(valueExpr.t)) {
						case TInst(clsRef, _): clsRef.get();
						case _: null;
					}
			};

			if (expectedAnon != null && expectedAnon.fields != null && actualCls != null) {
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
						var modName = rustModuleNameForClass(actualCls);
						var path = "crate::" + modName + "::" + rustTypeNameForClass(actualCls) + "::" + rustMethodName(actualCls, actualMethod);
						ECall(EPath(path), [EUnary("&", EUnary("*", EPath(recvName)))].concat(callArgs));
					};

					var isVoid = TypeHelper.isVoid(sig.ret);
					var body:RustBlock = isVoid ? {stmts: [RSemi(call)], tail: null} : {stmts: [], tail: call};

					var argTys = [for (p in sig.params) rustTypeToString(toRustType(p.t, valueExpr.pos))];
					var fnSig = "dyn Fn(" + argTys.join(", ") + ")";
					if (!TypeHelper.isVoid(sig.ret)) {
						fnSig += " -> " + rustTypeToString(toRustType(sig.ret, valueExpr.pos));
					}
					fnSig += " + Send + Sync";

					var rcTy:RustType = RPath(rcBasePath() + "<" + fnSig + ">");
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

		// Upcast concrete class references (`HxRef<T>`) into trait-object references (`HxRc<dyn Trait>`)
		// when the surrounding context expects an interface / polymorphic base type.
		//
		// This primarily matters for upstream stdlib code where concrete values are returned as
		// interface types (e.g. `Sys.stdin(): Input` returning `new Stdin()`).
		if (!isNullConstExpr(valueExpr) && (isInterfaceType(expected) || isPolymorphicClassType(expected))) {
			function rustTypeIsHxRef(rt:RustType):Bool {
				return switch (rt) {
					case RPath(p): StringTools.startsWith(p, "crate::HxRef<");
					case _: false;
				}
			}

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
			var actualIsHxRef = rustTypeIsHxRef(actualRustTy) || switch (actualExpr.expr) {
				case TNew(_, _, _): true;
				case _: false;
			};

			if (!actualIsHxRef)
				return compiled;

			var opt = ECall(EField(EPath("__tmp"), "as_arc_opt"), []);
			var arms:Array<RustMatchArm> = [
				{pat: PTupleStruct("Some", [PBind("__rc")]), expr: ECall(EField(EPath("__rc"), "clone"), [])},
				{pat: PPath("None"), expr: nullAccessThrow()}
			];

			return EBlock({
				stmts: [
					RLet("__tmp", false, null, compiled),
					RLet("__up", false, toRustType(expected, valueExpr.pos), EMatch(opt, arms))
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
			case "haxe.ds.Option" | "haxe.functional.Result" | "rust.Option" | "rust.Result" | "haxe.io.Error": true;
			case _: false;
		}
	}

	function rustEnumVariantPath(en:EnumType, variant:String):String {
		return switch (enumKey(en)) {
			case "haxe.ds.Option" | "rust.Option":
				"Option::" + variant;
			case "rust.Result":
				"Result::" + variant;
			// Map Haxe's `Result.Error` to Rust's `Result.Err`.
			case "haxe.functional.Result":
				"Result::" + (variant == "Error" ? "Err" : variant);
			case "haxe.io.Error":
				"hxrt::io::Error::" + variant;
			case _:
				"crate::" + rustModuleNameForEnum(en) + "::" + rustTypeNameForEnum(en) + "::" + variant;
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
			return ERaw("todo!()");
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
			return ERaw("todo!()");
		}

		var argc = enumFieldArgCount(ef);
		if (index < 0 || index >= argc) {
			#if eval
			Context.error("TEnumParameter index out of bounds: " + index, pos);
			#end
			return ERaw("todo!()");
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
				compileExpr(e);
		}
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
		// POC: support `super()` as a no-op (base init semantics will be expanded later).
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
					ensureAsyncPreviewAllowed(fullExpr.pos);
					var fieldName = field.getHaxeName();
					switch (fieldName) {
						case "await": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.await args");
								if (!currentFunctionIsAsync) {
									#if eval
									Context.error("`Async.await(...)` / `@:await` is only allowed inside `@:async` / `@:rustAsync` functions.", fullExpr.pos);
									#end
								}
								return EAwait(compileExpr(args[0]));
							}
						case "blockOn": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.blockOn args");
								if (currentFunctionIsAsync) {
									#if eval
									Context.error("`Async.blockOn(...)` is not allowed inside async functions. Use `await` instead.", fullExpr.pos);
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
									Context.error("`Async.await(...)` / `@:await` is only allowed inside `@:async` / `@:rustAsync` functions.", fullExpr.pos);
									#end
								}
								return EAwait(compileExpr(args[0]));
							}
						case "block_on": {
								if (args.length != 1)
									return unsupported(fullExpr, "Async.blockOn args");
								if (currentFunctionIsAsync) {
									#if eval
									Context.error("`Async.blockOn(...)` is not allowed inside async functions. Use `await` instead.", fullExpr.pos);
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
						case "indexOf":
							if (compiledArgs.length != 2)
								return unsupported(fullExpr, "String.indexOf args");
							return ECall(EPath("hxrt::string::index_of"), [asStr, argAsStr(0), compiledArgs[1]]);
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

								var stringClassId = ERaw(typeIdLiteralForKey(".String"));

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
											var modulePath = c.module;
											var parts = modulePath.split(".");
											var modTail = parts.length > 0 ? parts[parts.length - 1] : modulePath;
											modTail == c.name ? modulePath : (modulePath + "." + c.name);
										}
									case _: null;
								};
								if (name != null) {
									return ECall(EPath("String::from"), [ELitString(name)]);
								}

								// Runtime class handles (e.g. from `Type.typeof`) are not fully implemented yet.
								// Keep compilation working for upstream stdlib code; throw/behavior is unspecified.
								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("_", false, null, compileExpr(t)));
								return EBlock({
									stmts: stmts,
									tail: ECall(EPath("String::from"), [ELitString("<unknown class>")])
								});
							}

						case "getEnumName": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.getEnumName args");
								var t = args[0];
								var name = switch (t.expr) {
									case TTypeExpr(TEnumDecl(enRef)): {
											var en = enRef.get();
											var modulePath = en.module;
											var parts = modulePath.split(".");
											var modTail = parts.length > 0 ? parts[parts.length - 1] : modulePath;
											modTail == en.name ? modulePath : (modulePath + "." + en.name);
										}
									case _: null;
								};
								if (name != null) {
									return ECall(EPath("String::from"), [ELitString(name)]);
								}

								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("_", false, null, compileExpr(t)));
								return EBlock({
									stmts: stmts,
									tail: ECall(EPath("String::from"), [ELitString("<unknown enum>")])
								});
							}

						case "resolveClass": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.resolveClass args");
								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("_", false, null, compileExpr(args[0])));
								return EBlock({stmts: stmts, tail: ERaw("0u32")});
							}

						case "resolveEnum": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.resolveEnum args");
								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("_", false, null, compileExpr(args[0])));
								return EBlock({stmts: stmts, tail: ERaw("0u32")});
							}

						case "createEmptyInstance": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.createEmptyInstance args");
								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("_", false, null, compileExpr(args[0])));
								// `Type.createEmptyInstance` is used by upstream `haxe.Unserializer` to allocate an
								// object that `unserializeObject(o:{})` can populate.
								//
								// For now we only support the `{}` shape by returning an empty runtime `Anon`.
								// Full class-by-handle instantiation requires a type registry and is tracked separately.
								if (isAnonObjectType(fullExpr.t)) {
									return EBlock({
										stmts: stmts,
										tail: ECall(EPath("crate::HxRef::new"), [ECall(EPath("hxrt::anon::Anon::new"), [])])
									});
								}
								if (mapsToRustDynamic(fullExpr.t, fullExpr.pos)) {
									return EBlock({
										stmts: stmts,
										tail: rustDynamicNullExpr()
									});
								}
								return EBlock({
									stmts: stmts,
									tail: ECall(EPath("hxrt::exception::throw"), [
										ECall(EPath("hxrt::dynamic::from"), [
											ECall(EPath("String::from"), [ELitString("Type.createEmptyInstance not supported")])
										])
									])
								});
							}

						case "getEnumConstructs": {
								if (args.length != 1)
									return unsupported(fullExpr, "Type.getEnumConstructs args");
								var stmts:Array<RustStmt> = [];
								stmts.push(RLet("_", false, null, compileExpr(args[0])));
								return EBlock({
									stmts: stmts,
									tail: ECall(EPath("hxrt::array::Array::<String>::new"), [])
								});
							}

						case "createEnum": {
								// Full enum creation requires runtime type info; implement later.
								// Keep upstream `haxe.Unserializer` compiling for non-enum payloads.
								if (args.length < 2 || args.length > 3)
									return unsupported(fullExpr, "Type.createEnum args");
								var stmts:Array<RustStmt> = [];
								for (a in args)
									stmts.push(RLet("_", false, null, compileExpr(a)));
								return EBlock({stmts: stmts, tail: ERaw("todo!()")});
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
														var tyStr = rustTypeToString(toRustType(cf.type, fullExpr.pos));
														var getter = "get::<" + tyStr + ">";
														value = ECall(EField(borrowed, getter), [ELitString(cf.getHaxeName())]);
													} else {
														// KeyValue structural record etc: direct field read (clone non-Copy to avoid moves).
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

								return unsupported(fullExpr, "Reflect.hasField (unsupported receiver)");
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
									// `{ let _ = enc; Rc::new(RefCell::new(Bytes::of_string(...))) }`
									var asStr = ECall(EField(compileExpr(s), "as_str"), []);
									var inner = ECall(EPath("hxrt::bytes::Bytes::of_string"), [asStr]);
									var wrapped = ECall(EPath("crate::HxRef::new"), [inner]);
									return EBlock({stmts: [RLet("_", false, null, enc)], tail: wrapped});
								}
								var asStr = ECall(EField(compileExpr(s), "as_str"), []);
								var inner = ECall(EPath("hxrt::bytes::Bytes::of_string"), [asStr]);
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
							case _:
						}
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

								// Generic `Null<T>` return values:
								//
								// Some upstream/std helpers are declared as returning `Null<T>` where `T` is a type
								// parameter (e.g. `Deque<T>.pop(): Null<T>`). In Rust we must represent that as
								// `Option<T>` because `T` can be a non-nullable value type (like `i32`).
								//
								// However, when the generic type parameter is instantiated to a Rust type that
								// already has an explicit null sentinel (notably `HxRef<T>`, `Array<T>`, and
								// `HxDynRef<dyn Fn...>`), Haxe will often treat `Null<T>` as just `T` and the typed
								// call expression will be `T`. In that case we must coerce `Option<T>` -> `T` by
								// mapping `None` to the type's explicit null value.
								//
								// This keeps callsites type-correct and matches Haxe's "reference types are nullable"
								// behavior without requiring pervasive `Option<...>` in user-facing APIs.
								if (!mapsToRustDynamic(fullExpr.t, fullExpr.pos)) {
									var ret0:Null<Type> = switch (followType(cf.type)) {
										case TFun(_, r): r;
										case _: null;
									};
									if (ret0 != null && nullOptionInnerType(ret0, fullExpr.pos) != null) {
										// Apply receiver type parameters so we can see whether the instantiated
										// return type would *not* require an `Option<...>` wrapper.
										var retApplied:Type = ret0;
										if (owner != null && owner.params != null && owner.params.length > 0) {
											switch (followType(obj.t)) {
												case TInst(_, actualParams) if (actualParams != null
													&& actualParams.length == owner.params.length):
													retApplied = TypeTools.applyTypeParameters(retApplied, owner.params, actualParams);
												case _:
											}
										}

										if (nullOptionInnerType(retApplied, fullExpr.pos) == null) {
											function explicitNullExprForExpected(t:Type, pos:haxe.macro.Expr.Position):Null<RustExpr> {
												var rust = rustTypeToString(toRustType(t, pos));
												if (isRustDynamicPath(rust))
													return rustDynamicNullExpr();
												if (isCoreClassOrEnumHandleType(t))
													return ERaw("0u32");
												if (StringTools.startsWith(rust, "crate::HxRef<"))
													return ECall(EPath("crate::HxRef::null"), []);
												if (StringTools.startsWith(rust, "hxrt::array::Array<"))
													return ECall(EPath("hxrt::array::Array::null"), []);
												if (StringTools.startsWith(rust, dynRefBasePath() + "<"))
													return ECall(EPath(dynRefBasePath() + "::null"), []);
												return null;
											}

											var nullExpr = explicitNullExprForExpected(fullExpr.t, fullExpr.pos);
											if (nullExpr != null) {
												call = EBlock({
													stmts: [RLet("__hx_opt", false, null, call)],
													tail: EMatch(EPath("__hx_opt"), [
														{pat: PTupleStruct("Some", [PBind("__v")]), expr: EPath("__v")},
														{pat: PPath("None"), expr: nullExpr}
													])
												});
											}
										}
									}
								}

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

		var nullableFnInner = nullInnerType(callExpr.t);
		var fnTypeForParams:Type = (nullableFnInner != null ? nullableFnInner : callExpr.t);
		// Prefer the declared field type when available so we don't lose Rusty ref-wrapper types
		// (e.g. `rust.Ref<T>`) via aggressive type following.
		//
		// This is especially important for stdlib helpers like `rust.VecTools.len(get)` which take
		// `Ref<Vec<T>>` and must lower to `&Vec<T>` at call sites.
		if (nullableFnInner == null) {
			switch (callExpr.expr) {
				case TField(_, FStatic(_, fieldRef)):
					{
						var cf = fieldRef.get();
						if (cf != null)
							fnTypeForParams = cf.type;
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

		function defaultExprIsCallsiteSafe(e:TypedExpr):Bool {
			var u = unwrapMetaParen(e);
			return switch (u.expr) {
				case TConst(_): true;
				case TArrayDecl(values):
					values == null ? true : Lambda.fold(values, (x, acc) -> acc && defaultExprIsCallsiteSafe(x), true);
				case TObjectDecl(fields):
					fields == null ? true : Lambda.fold(fields, (f, acc) -> acc && defaultExprIsCallsiteSafe(f.expr), true);
				case TBinop(_, x, y): defaultExprIsCallsiteSafe(x) && defaultExprIsCallsiteSafe(y);
				case TUnop(_, _, x):
					defaultExprIsCallsiteSafe(x);
				case TCall(f2, a2): defaultExprIsCallsiteSafe(f2) && (a2 == null ? true : Lambda.fold(a2, (x, acc) -> acc && defaultExprIsCallsiteSafe(x),
						true));
				case TNew(_, _, a2):
					a2 == null ? true : Lambda.fold(a2, (x, acc) -> acc && defaultExprIsCallsiteSafe(x), true);
				case TCast(inner, _):
					defaultExprIsCallsiteSafe(inner);
				case TParenthesis(inner):
					defaultExprIsCallsiteSafe(inner);
				case TMeta(_, inner):
					defaultExprIsCallsiteSafe(inner);
				case TTypeExpr(_):
					true;
				// Disallow locals/`this`/control flow: those defaults must be lowered inside the callee.
				case _:
					false;
			};
		}

		// Fill omitted optional arguments:
		// - `?x:T` (typed as `Null<T>`) => `None`
		// - `x = <expr>` => default expression (best-effort)
		if (paramDefs != null && args.length < paramDefs.length) {
			for (i in args.length...paramDefs.length) {
				if (!paramDefs[i].opt)
					break;
				var def:Null<TypedExpr> = (paramDefaultExprs != null && i < paramDefaultExprs.length) ? paramDefaultExprs[i] : null;
				if (def != null && defaultExprIsCallsiteSafe(def)) {
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
				case RRef(_, _): true;
				case _: false;
			}

			// Haxe Arrays are reusable and behave like shared values; avoid Rust moves by cloning locals
			// when we pass them by value.
			if (!isByRef && isArrayType(argExpr.t) && isLocalExpr(argExpr) && !isObviousTemporaryExpr(argExpr)) {
				compiled = ECall(EField(compiled, "clone"), []);
			}
			if (!isByRef && isRcBackedType(argExpr.t) && isLocalExpr(argExpr) && !isObviousTemporaryExpr(argExpr)) {
				compiled = ECall(EField(compiled, "clone"), []);
			}
			if (!isByRef
				&& mapsToRustDynamic(argExpr.t, argExpr.pos)
				&& isLocalExpr(argExpr)
				&& !isObviousTemporaryExpr(argExpr)
				&& !isCloneExpr(compiled)) {
				compiled = ECall(EField(compiled, "clone"), []);
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

						var argTys = [for (p in sig.params) rustTypeToString(toRustType(p.t, argExpr.pos))];
						var fnSig = "dyn Fn(" + argTys.join(", ") + ")";
						if (!TypeHelper.isVoid(sig.ret)) {
							fnSig += " -> " + rustTypeToString(toRustType(sig.ret, argExpr.pos));
						}
						fnSig += " + Send + Sync";

						var rcTy:RustType = RPath(rcBasePath() + "<" + fnSig + ">");
						var rcExpr:RustExpr = ECall(EPath(rcBasePath() + "::new"), [compiled]);
						compiled = EBlock({
							stmts: [RLet("__rc", false, rcTy, rcExpr)],
							tail: ECall(EPath(dynRefBasePath() + "::new"), [EPath("__rc")])
						});
					}
				}
			case _:
		}

		compiled = coerceExprToExpected(compiled, argExpr, paramType);
		return wrapBorrowIfNeeded(compiled, rustParamTy, argExpr);
	}

	function wrapBorrowIfNeeded(expr:RustExpr, ty:RustType, valueExpr:TypedExpr):RustExpr {
		return switch (ty) {
			case RRef(_, mutable):
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

	function isDirectRustRefValue(e:TypedExpr):Bool {
		var cur = unwrapMetaParen(e);
		switch (cur.expr) {
			case TCast(inner, _):
				{
					// Casts are often used for implicit `@:from` conversions to `Ref/MutRef`, where we still
					// want to emit `&`/`&mut`.
					//
					// However, for Rusty “ref-to-ref” coercions (e.g. `MutRef<Vec<T>> -> MutSlice<T>`),
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

					// Static vars are stored in module-level lazy cells (`__hx_static_get_*`).
					switch (cf.kind) {
						case FVar(_, _): {
								var modName = rustModuleNameForClass(cls);
								var rustName = rustMethodName(cls, cf);
								var getterFn = rustStaticVarHelperName("__hx_static_get", rustName);
								return ECall(EPath("crate::" + modName + "::" + getterFn), []);
							}
						case _:
					}

					if (mainClassKey != null && currentClassKey != null && key == currentClassKey && key == mainClassKey) {
						EPath(rustMethodName(cls, cf));
					} else {
						var modName = rustModuleNameForClass(cls);
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
					// Structural iterator/keyvalue records remain direct field access.
					if (cf != null && isAnonObjectType(obj.t)) {
						var recv = compileExpr(obj);
						var borrowed = ECall(EField(recv, "borrow"), []);
						var tyStr = rustTypeToString(toRustType(cf.type, fullExpr.pos));
						var getter = "get::<" + tyStr + ">";
						return ECall(EField(borrowed, getter), [ELitString(cf.getHaxeName())]);
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
		// `this.method` inside a concrete method would capture `&RefCell<Self>`; that reference cannot be
		// stored in our baseline `'static` function-value representation (`HxDynRef<dyn Fn...>`).
		//
		// For now we only support binding non-`this` receivers.
		if (isThisExpr(obj))
			return unsupported(fullExpr, "method value (this)");

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
		} else if (isInterfaceType(obj.t) || isPolymorphicClassType(obj.t)) {
			ECall(EField(EPath(recvName), rustMethodName(owner, cf)), callArgs);
		} else {
			var modName = rustModuleNameForClass(owner);
			var path = "crate::" + modName + "::" + rustTypeNameForClass(owner) + "::" + rustMethodName(owner, cf);
			ECall(EPath(path), [EUnary("&", EUnary("*", EPath(recvName)))].concat(callArgs));
		};

		var isVoid = TypeHelper.isVoid(sig.ret);
		var body:RustBlock = isVoid ? {stmts: [RSemi(call)], tail: null} : {stmts: [], tail: call};

		var argTys = [for (p in sig.params) rustTypeToString(toRustType(p.t, fullExpr.pos))];
		var fnSig = "dyn Fn(" + argTys.join(", ") + ")";
		if (!TypeHelper.isVoid(sig.ret)) {
			fnSig += " -> " + rustTypeToString(toRustType(sig.ret, fullExpr.pos));
		}
		fnSig += " + Send + Sync";

		var rcTy:RustType = RPath(rcBasePath() + "<" + fnSig + ">");
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

		function varHasStorage(prop:ClassField):Bool {
			// `@:isVar` forces storage even when accessors are `get/set`.
			for (m in prop.meta.get())
				if (m.name == ":isVar")
					return true;
			return switch (prop.kind) {
				case FVar(read, write):
					switch ([read, write]) {
						case [AccNormal | AccNo | AccCtor, _] | [_, AccNormal | AccNo | AccCtor]:
							true;
						case _:
							false;
					}
				case _:
					false;
			}
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
						var skipLower = varHasStorage(cf)
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

							var modName = rustModuleNameForClass(recvCls);
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

		function varHasStorage(prop:ClassField):Bool {
			for (m in prop.meta.get())
				if (m.name == ":isVar")
					return true;
			return switch (prop.kind) {
				case FVar(read, write):
					switch ([read, write]) {
						case [AccNormal | AccNo | AccCtor, _] | [_, AccNormal | AccNo | AccCtor]:
							true;
						case _:
							false;
					}
				case _:
					false;
			}
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
						var skipLower = varHasStorage(cf)
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

							var modName = rustModuleNameForClass(recvCls);
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
			var assigned = fieldIsOptionWrapped ? (rhsIsNullish ? ERaw("None") : ECall(EPath("Some"),
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
		var assigned = fieldIsOptionWrapped ? (rhsIsNullish ? ERaw("None") : ECall(EPath("Some"),
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
						("crate::" + rustModuleNameForClass(cls) + "::" + rustTypeNameForClass(cls));
				}
			case _: null;
		}
	}

	function classNameFromClass(cls:ClassType):String {
		return isMainClass(cls) ? rustTypeNameForClass(cls) : ("crate::" + rustModuleNameForClass(cls) + "::" + rustTypeNameForClass(cls));
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
					addSpec({traitPath: s});
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
							var spec:RustImplSpec = {traitPath: traitPath};
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
					var spec:RustImplSpec = {traitPath: traitPath};
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
				var spec:RustImplSpec = {traitPath: traitPath};
				if (body != null)
					spec.body = body;
				addSpec(spec);
				continue;
			}
		}

		// Stable ordering for snapshots.
		out.sort((a, b) -> Reflect.compare(a.traitPath, b.traitPath));
		return out;
	}

	function renderRustImplBlock(spec:RustImplSpec, implGenerics:Array<String>, forType:String):String {
		var header = "impl";
		if (implGenerics != null && implGenerics.length > 0)
			header += "<" + implGenerics.join(", ") + ">";
		header += " " + spec.traitPath + " for " + (spec.forType != null ? spec.forType : forType) + " {";

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
		var genericSuffix = generics.length > 0 ? "<" + generics.join(", ") + ">" : "";
		var lines:Array<String> = [];
		lines.push("pub trait " + traitName + genericSuffix + ": Send + Sync {");

		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			var ty = rustTypeToString(toRustType(cf.type, cf.pos));
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
		var modName = rustModuleNameForClass(classType);
		var traitPathBase = "crate::" + modName + "::" + rustTypeNameForClass(classType) + "Trait";
		var rustSelfType = rustTypeNameForClass(classType);
		var rustSelfInst = rustClassTypeInst(classType);
		var generics = rustGenericDeclsForClass(classType);
		var genericNames = rustGenericNamesFromDecls(generics);
		var turbofish = genericNames.length > 0 ? ("::<" + genericNames.join(", ") + ">") : "";
		var traitArgs = genericNames.length > 0 ? "<" + genericNames.join(", ") + ">" : "";
		var implGenerics = generics.length > 0 ? "<" + generics.join(", ") + ">" : "";

		var lines:Array<String> = [];
		lines.push("impl" + implGenerics + " " + traitPathBase + traitArgs + " for " + refCellBasePath() + "<" + rustSelfInst + "> {");

		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			var ty = rustTypeToString(toRustType(cf.type, cf.pos));

			lines.push("\tfn " + rustGetterName(classType, cf) + "(&self) -> " + ty + " {");
			if (shouldOptionWrapStructFieldType(cf.type)) {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf) + ".as_ref().unwrap().clone()");
			} else if (isCopyType(cf.type)) {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf));
			} else {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf) + ".clone()");
			}
			lines.push("\t}");

			lines.push("\tfn " + rustSetterName(classType, cf) + "(&self, v: " + ty + ") {");
			if (shouldOptionWrapStructFieldType(cf.type)) {
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
		var baseMod = rustModuleNameForClass(baseType);
		var baseTraitPathBase = "crate::" + baseMod + "::" + rustTypeNameForClass(baseType) + "Trait";
		var rustSubType = rustTypeNameForClass(subType);
		var rustSubInst = rustClassTypeInst(subType);
		var subGenerics = rustGenericDeclsForClass(subType);
		var subGenericNames = rustGenericNamesFromDecls(subGenerics);
		var subTurbofish = subGenericNames.length > 0 ? ("::<" + subGenericNames.join(", ") + ">") : "";
		var subImplGenerics = subGenerics.length > 0 ? "<" + subGenerics.join(", ") + ">" : "";

		function findSuperParams(sub:ClassType, base:ClassType):Array<Type> {
			var cur:Null<ClassType> = sub;
			while (cur != null) {
				if (cur.superClass != null) {
					var sup = cur.superClass.t.get();
					if (sup != null && classKey(sup) == classKey(base)) {
						return cur.superClass.params != null ? cur.superClass.params : [];
					}
				}
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
			return [];
		}

		var baseArgs = findSuperParams(subType, baseType);
		var baseTraitArgs = baseArgs.length > 0 ? ("<" + [for (p in baseArgs) rustTypeToString(toRustType(p, subType.pos))].join(", ") + ">") : "";

		var overrides = new Map<String, ClassFuncData>();
		for (f in subFuncFields) {
			if (f.isStatic)
				continue;
			if (f.field.getHaxeName() == "new")
				continue;
			if (f.expr == null)
				continue;
			overrides.set(f.field.getHaxeName() + "/" + f.args.length, f);
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

		for (cf in getAllInstanceVarFieldsForStruct(baseType)) {
			var ty = rustTypeToString(toRustType(cf.type, cf.pos));

			lines.push("\tfn " + rustGetterName(baseType, cf) + "(&self) -> " + ty + " {");
			if (shouldOptionWrapStructFieldType(cf.type)) {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf) + ".as_ref().unwrap().clone()");
			} else if (isCopyType(cf.type)) {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf));
			} else {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf) + ".clone()");
			}
			lines.push("\t}");

			lines.push("\tfn " + rustSetterName(baseType, cf) + "(&self, v: " + ty + ") {");
			if (shouldOptionWrapStructFieldType(cf.type)) {
				lines.push("\t\tself.borrow_mut()." + rustFieldName(subType, cf) + " = Some(v);");
			} else {
				lines.push("\t\tself.borrow_mut()." + rustFieldName(subType, cf) + " = v;");
			}
			lines.push("\t}");
		}

		// Base traits include inherited methods (see `emitClassTrait` using `effectiveFuncFields`).
		// Implement the same surface here: baseType declared methods with bodies plus inherited base bodies.
		var baseTraitMethods:Array<ClassField> = [];
		var baseTraitSeen:Map<String, Bool> = [];

		function considerBaseTraitMethod(cf:ClassField):Void {
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
					baseTraitMethods.push(cf);
				case _:
			}
		}

		for (cf in baseType.fields.get())
			considerBaseTraitMethod(cf);
		var curBase:Null<ClassType> = baseType.superClass != null ? baseType.superClass.t.get() : null;
		while (curBase != null) {
			for (cf in curBase.fields.get())
				considerBaseTraitMethod(cf);
			curBase = curBase.superClass != null ? curBase.superClass.t.get() : null;
		}

		function baseTraitKey(cf:ClassField):String {
			var ft = followType(cf.type);
			var argc = switch (ft) {
				case TFun(a, _): a.length;
				case _: 0;
			};
			return cf.getHaxeName() + "/" + argc;
		}
		baseTraitMethods.sort((a, b) -> Reflect.compare(baseTraitKey(a), baseTraitKey(b)));

		for (cf in baseTraitMethods) {
			switch (cf.kind) {
				case FMethod(_):
					{
						var ft = followType(cf.type);
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
						if (overrides.exists(key)) {
							var overrideFunc = overrides.get(key);
							var call = rustSubType + subTurbofish + "::" + rustMethodName(subType, overrideFunc.field) + "(" + callArgs.join(", ") + ")";

							function rustTypeIsHxRef(rt:RustType):Bool {
								return switch (rt) {
									case RPath(p): StringTools.startsWith(p, "crate::HxRef<");
									case _: false;
								}
							}

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
						} else {
							// Stub: keep signatures warning-free under `#![deny(warnings)]`.
							// `_` patterns avoid `unused_variables` even when the body is `todo!()`.
							lines.pop();
							var stubSigArgs:Array<String> = ["&self"];
							for (a in args) {
								stubSigArgs.push("_: " + rustTypeToString(toRustType(a.t, cf.pos)));
							}
							lines.push("\tfn " + rustMethodName(baseType, cf) + "(" + stubSigArgs.join(", ") + ") -> " + ret + " {");
							lines.push("\t\ttodo!()");
						}
						lines.push("\t}");
					}
				case _:
			}
		}

		var subMod = rustModuleNameForClass(subType);
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

	function getAllInstanceVarFieldsForStruct(classType:ClassType):Array<ClassField> {
		var out:Array<ClassField> = [];
		var seen = new Map<String, Bool>();

		function isPhysicalVarField(cls:ClassType, cf:ClassField):Bool {
			// Haxe `var x(get,set)` style properties are not stored fields unless explicitly marked `@:isVar`
			// or declared with default-like access (e.g. `default`, `null`, `ctor`).
			if (cf.meta != null && cf.meta.has(":isVar"))
				return true;
			return switch (cf.kind) {
				case FVar(read, write):
					switch ([read, write]) {
						// A backing field exists when at least one side uses direct field access (`default`)
						// or constructor-only init access (`ctor`). `null`/`no` by itself does not imply storage.
						case [AccNormal | AccCtor, _]: true;
						case [_, AccNormal | AccCtor]: true;
						// `var x(get, null)` is a common pattern for "custom getter + stored field" (write access
						// is restricted, but storage still exists for internal usage).
						case [AccNo, _]: true;
						case [_, AccNo]: true;
						case _: false;
					}
				case _:
					false;
			};
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
							out.push(cf);
						}
					case _:
				}
			}
		}

		return out;
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
			var ft = followType(cf.type);
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

	function compileBinop(op:Binop, e1:TypedExpr, e2:TypedExpr, fullExpr:TypedExpr):RustExpr {
		return switch (op) {
			case OpAssign:
				switch (e1.expr) {
					case TLocal(v) if (isNullOptionType(v.t, e1.pos) && !isNullType(e2.t) && !isNullConstExpr(e2)): {
							// Assignment to `Null<T>` (Option<T>) from a non-null `T`:
							// `{ let __tmp = rhs; lhs = Some(__tmp.clone()); __tmp }`
							var stmts:Array<RustStmt> = [];
							stmts.push(RLet("__tmp", false, null, compileExpr(e2)));

							var rhsVal:RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
							var wrapped = ECall(EPath("Some"), [rhsVal]);
							stmts.push(RSemi(EAssign(compileExpr(e1), wrapped)));

							return EBlock({stmts: stmts, tail: EPath("__tmp")});
						}
					case TLocal(_): {
							// Assignment into a local: coerce the RHS into the local's storage type.
							// This handles trait upcasts and structural typedef adapters (TypeResolver).
							var rhsExpr = compileExpr(e2);
							rhsExpr = maybeCloneForReuseValue(rhsExpr, e2);
							rhsExpr = coerceExprToExpected(rhsExpr, e2, e1.t);
							return EAssign(compileExpr(e1), rhsExpr);
						}
					case TArray(arr, index): {
							compileArrayIndexAssign(arr, index, e2);
						}
					case TField(obj, FAnon(cfRef)): {
							// Assignment into anonymous-object fields:
							// `{ let __obj = obj.clone(); let __tmp = rhs; __obj.borrow_mut().set("field", __tmp.clone()); __tmp }`
							//
							// Only supported for general anonymous objects, not iterator/keyvalue structural types.
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
									return ERaw("None");
								var innerRust = rustTypeToString(toRustType(inner, pos));
								return ERaw("Option::<" + innerRust + ">::None");
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
										var modName = rustModuleNameForClass(owner);
										var setterFn = rustStaticVarHelperName("__hx_static_set", rustName);
										var setter = "crate::" + modName + "::" + setterFn;

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

						var u = unwrapMetaParen(p);
						switch (u.expr) {
							case TConst(TString(s)):
								return ELitString(s);
							case TLocal(_):
								return EUnary("&", compileExpr(p));
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
													return compileExpr(p);
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

						return compileExpr(p);
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
						EBinary("+", compileExpr(e1), compileExpr(e2));
					}
				}

			case OpSub: {
					if (TypeHelper.isFloat(followType(fullExpr.t))) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("-", lhs, rhs);
					} else {
						EBinary("-", compileExpr(e1), compileExpr(e2));
					}
				}
			case OpMult: {
					if (TypeHelper.isFloat(followType(fullExpr.t))) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("*", lhs, rhs);
					} else {
						EBinary("*", compileExpr(e1), compileExpr(e2));
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
						EBinary("/", compileExpr(e1), compileExpr(e2));
					}
				}
			case OpMod: {
					if (TypeHelper.isFloat(followType(fullExpr.t))) {
						var floatTy = Context.getType("Float");
						var lhs = coerceExprToExpected(compileExpr(e1), e1, floatTy);
						var rhs = coerceExprToExpected(compileExpr(e2), e2, floatTy);
						EBinary("%", lhs, rhs);
					} else {
						EBinary("%", compileExpr(e1), compileExpr(e2));
					}
				}

			// Bitwise ops (Int).
			case OpAnd: EBinary("&", compileExpr(e1), compileExpr(e2));
			case OpOr: EBinary("|", compileExpr(e1), compileExpr(e2));
			case OpXor: EBinary("^", compileExpr(e1), compileExpr(e2));
			case OpShl: EBinary("<<", compileExpr(e1), compileExpr(e2));
			case OpShr: EBinary(">>", compileExpr(e1), compileExpr(e2));
			case OpUShr: {
					// Unsigned shift-right (`>>>`) uses `u32` then casts back to `i32`.
					// This matches Haxe's `Int` semantics for `>>>` (logical shift).
					var lhs = ECast(compileExpr(e1), "u32");
					var rhs = ECast(compileExpr(e2), "u32");
					ECast(EBinary(">>", lhs, rhs), "i32");
				}

			case OpEq: {
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
											return EBinary("==", lhs, ERaw("0u32"));
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
											return EBinary("==", rhs, ERaw("0u32"));
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
											return EBinary("!=", lhs, ERaw("0u32"));
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
											return EBinary("!=", rhs, ERaw("0u32"));
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

					if (TypeHelper.isFloat(ft1) && TypeHelper.isInt(ft2)) {
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
					// POC: support locals (common in loops/desugarings). More complex lvalues
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
						case TLocal(_): {
								// `{ x = x <op> rhs; x }`
								//
								// Special-case Strings: Rust `String` is non-Copy and `x += y` must not move out of `x`
								// (Haxe strings are reusable). Implement as `x = format!("{}{}", x, rhs); x.clone()`.
								var lhs = compileExpr(e1);
								var rhsExpr = maybeCloneForReuseValue(compileExpr(e2), e2);
								var stringy = inner == OpAdd
									&& (isStringType(followType(fullExpr.t))
										|| isStringType(followType(e1.t))
										|| isStringType(followType(e2.t)));
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
						case TArray(arr, index): {
								// Compound assignment on an array element: `arr[index] <op>= rhs`.
								//
								// Preserve evaluation order (arr -> index -> rhs) and ensure arr/index are evaluated once.
								// POC: only support Copy element types (mirrors instance-field support).
								if (!isCopyType(e1.t)) {
									return unsupported(fullExpr, "assignop array lvalue (non-copy)");
								}

								var arrName = "__hx_arr";
								var idxName = "__hx_idx";
								var rhsName = "__rhs";
								var tmpName = "__tmp";

								var stmts:Array<RustStmt> = [];
								stmts.push(RLet(arrName, false, null, maybeCloneForReuseValue(compileExpr(arr), arr)));
								stmts.push(RLet(idxName, false, null, ECast(compileExpr(index), "usize")));
								stmts.push(RLet(rhsName, false, null, compileExpr(e2)));

								var read = ECall(EField(EPath(arrName), "get_unchecked"), [EPath(idxName)]);
								stmts.push(RLet(tmpName, false, null, EBinary(opStr, read, EPath(rhsName))));
								stmts.push(RSemi(ECall(EField(EPath(arrName), "set"), [EPath(idxName), EPath(tmpName)])));

								EBlock({stmts: stmts, tail: EPath(tmpName)});
							}
						case TField(obj, FInstance(clsRef, _, cfRef)): {
								// Compound assignment on a concrete instance field: `obj.field <op>= rhs`.
								//
								// Like field ++/--, we must avoid overlapping `RefCell` borrows:
								// evaluate rhs first -> read via borrow() -> write via borrow_mut().
								var owner = clsRef.get();
								var cf = cfRef.get();
								switch (cf.kind) {
									case FVar(_, _): {
											if (!isCopyType(e1.t)) {
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
												var modName = rustModuleNameForClass(recvCls);
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
												var modName = rustModuleNameForClass(recvCls);
												var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
												return ECall(EPath(path), [EUnary("&", recvExpr), value]);
											}

											var recvName = "__hx_obj";
											var recvExpr:RustExpr = isThisExpr(obj) ? EPath("self_") : EPath(recvName);

											var fieldName = rustFieldName(owner, cf);
											var rhsName = "__rhs";
											var tmpName = "__tmp";

											var stmts:Array<RustStmt> = [];
											if (!isThisExpr(obj)) {
												// Evaluate receiver once and keep it alive across borrows.
												var base = compileExpr(obj);
												stmts.push(RLet(recvName, false, null, ECall(EField(base, "clone"), [])));
											}

											// Evaluate rhs before taking a mutable borrow of the receiver.
											stmts.push(RLet(rhsName, false, null, compileExpr(e2)));

											var usesAccessors = (read == AccCall) || (write == AccCall);
											if (usesAccessors) {
												var recvCls = receiverClassForField(obj, owner);
												var curVal = (read == AccCall) ? getterCall(recvCls,
													recvExpr) : EField(ECall(EField(recvExpr, "borrow"), []), fieldName);
												stmts.push(RLet(tmpName, false, null, EBinary(opStr, curVal, EPath(rhsName))));
												var assigned = (write == AccCall) ? setterCall(recvCls, recvExpr, EPath(tmpName)) : EBlock({
													stmts: [
														RSemi(EAssign(EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName), EPath(tmpName)))
													],
													tail: EPath(tmpName)
												});
												stmts.push(RLet("__assigned", false, null, assigned));
												return EBlock({stmts: stmts, tail: EPath("__assigned")});
											} else {
												if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
													return unsupported(fullExpr, "assignop field lvalue (polymorphic)");
												}
												var read = EField(ECall(EField(recvExpr, "borrow"), []), fieldName);
												var rhs = EPath(rhsName);
												stmts.push(RLet(tmpName, false, null, EBinary(opStr, read, rhs)));

												var writeField = EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName);
												stmts.push(RSemi(EAssign(writeField, EPath(tmpName))));

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
								// Preserve evaluation order (obj -> rhs) and avoid overlapping `RefCell` borrows:
								// evaluate rhs first -> read via borrow() -> write via borrow_mut().
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
								stmts.push(RLet(rhsName, false, null, compileExpr(e2)));

								var tyStr = rustTypeToString(toRustType(cf.type, fullExpr.pos));
								var borrowRead = ECall(EField(EPath(recvName), "borrow"), []);
								var getter = "get::<" + tyStr + ">";
								var read = ECall(EField(borrowRead, getter), [ELitString(fieldName)]);
								stmts.push(RLet(tmpName, false, null, EBinary(opStr, read, EPath(rhsName))));

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
			// POC: support ++/-- for locals (needed for Haxe's for-loop lowering).
			return switch (expr.expr) {
				case TLocal(v): {
						var name = rustLocalRefIdent(v);
						var delta:RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
						var binop = (op == OpIncrement) ? "+" : "-";
						if (postFix) {
							EBlock({
								stmts: [
									RLet("__tmp", false, null, EPath(name)),
									RSemi(EAssign(EPath(name), EBinary(binop, EPath(name), delta)))
								],
								tail: EPath("__tmp")
							});
						} else {
							EBlock({
								stmts: [RSemi(EAssign(EPath(name), EBinary(binop, EPath(name), delta)))],
								tail: EPath(name)
							});
						}
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
											var modName = rustModuleNameForClass(recvCls);
											var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, getter);
											return ECall(EPath(path), [EUnary("&", recvExpr)]);
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
											var modName = rustModuleNameForClass(recvCls);
											var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
											return ECall(EPath(path), [EUnary("&", recvExpr), value]);
										}
										var fieldName = rustFieldName(owner, cf);
										var writeField = EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName);
										return EBlock({stmts: [RSemi(EAssign(writeField, value))], tail: value});
									}

									// If either side uses accessors, treat as a property-like operation.
									var usesAccessors = (read == AccCall) || (write == AccCall);
									if (usesAccessors) {
										if (!isCopyType(expr.t)) {
											return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " property unop (non-copy)");
										}

										var recvCls = receiverClassForField(obj, owner);
										var recvName = "__hx_obj";
										var recvExpr:RustExpr = isThisExpr(obj) ? EPath("self_") : EPath(recvName);
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

									// Polymorphic (trait object) field access uses getter/setter methods; keep it unsupported for now.
									if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
										return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " field unop (polymorphic)");
									}

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
		Context.error('Unsupported $what for Rust POC: ' + Std.string(e.expr), e.pos);
		#end
		return ERaw("todo!()");
	}

	function toRustType(t:Type, pos:haxe.macro.Expr.Position):reflaxe.rust.ast.RustAST.RustType {
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
						var innerStr = rustTypeToString(inner);

						// Some Rust representations already have an explicit null value (no extra `Option<...>` needed).
						// `Dynamic` already carries its own null sentinel (`Dynamic::null()`).
						if (isRustDynamicPath(innerStr)) {
							return inner;
						}
						// Portable/idiomatic `String` uses `HxString`, which already models null.
						if (innerStr == "hxrt::string::HxString") {
							return inner;
						}
						// Core `Class<T>` / `Enum<T>` handles are represented as `u32` ids with `0u32` as null sentinel.
						if (isCoreClassOrEnumHandleType(innerType)) {
							return inner;
						}
						if (StringTools.startsWith(innerStr, "crate::HxRef<")
							|| StringTools.startsWith(innerStr, "hxrt::array::Array<")
							|| StringTools.startsWith(innerStr, dynRefBasePath() + "<")) {
							return inner;
						}

						return RPath("Option<" + innerStr + ">");
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
			return useNullableStringRepresentation() ? RPath(rustStringTypePath()) : RString;
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
					return RPath(rustDynamicPath());
				}
			case _:
		}

		switch (ft) {
			case TDynamic(_):
				return RPath(rustDynamicPath());
			case _:
		}

		switch (ft) {
			case TFun(params, ret):
				{
					var argTys = [for (p in params) rustTypeToString(toRustType(p.t, pos))];
					var retTy = toRustType(ret, pos);
					var sig = "dyn Fn(" + argTys.join(", ") + ")";
					if (!TypeHelper.isVoid(ret)) {
						sig += " -> " + rustTypeToString(retTy);
					}
					sig += " + Send + Sync";
					return RPath(dynRefBasePath() + "<" + sig + ">");
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
						return RPath("crate::HxRef<" + rustTypeToString(inner) + ">");
					}
					if (key == "rust.Ref" && params.length == 1) {
						return RRef(toRustType(params[0], pos), false);
					}
					if (key == "rust.MutRef" && params.length == 1) {
						return RRef(toRustType(params[0], pos), true);
					}
					if (key == "rust.Str" && params.length == 0) {
						return RRef(RPath("str"), false);
					}
					if (key == "rust.Slice" && params.length == 1) {
						var inner = toRustType(params[0], pos);
						return RRef(RPath("[" + rustTypeToString(inner) + "]"), false);
					}
					if (key == "rust.MutSlice" && params.length == 1) {
						var inner = toRustType(params[0], pos);
						return RRef(RPath("[" + rustTypeToString(inner) + "]"), true);
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
								return RPath("u32");
							case ".Enum":
								// Same representation strategy as `Class<T>`.
								return RPath("u32");
							case _ if (key == dynamicCoreTypeKey):
								return RPath(rustDynamicPath());
							case _:
						}
						if (key == "haxe.io.BytesData") {
							// Target-private storage type backing `haxe.io.Bytes`.
							// For Rust we treat it as a plain byte vector.
							return RPath("Vec<u8>");
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
						return RPath(rustDynamicPath());
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

		// StdTypes: Iterator<T> / KeyValueIterator<K,V> are typedefs to structural types.
		// We lower them to owned Rust iterators for codegen simplicity (primarily used in `for` loops).
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
						var keyField:Null<ClassField> = null;
						var valueField:Null<ClassField> = null;

						for (cf in anon.fields) {
							switch (cf.getHaxeName()) {
								case "hasNext": hasNext = cf;
								case "next": next = cf;
								case "key": keyField = cf;
								case "value": valueField = cf;
								case _:
							}
						}

						// Iterator<T> (structural): { hasNext():Bool, next():T }
						if (hasNext != null && next != null) {
							var nextRet:Type = switch (followType(next.type)) {
								case TFun(_, r): r;
								case _: next.type;
							}
							var item = toRustType(nextRet, pos);
							return RPath("hxrt::iter::Iter<" + rustTypeToString(item) + ">");
						}

						// KeyValue record used by KeyValueIterator<K,V>: { key:K, value:V }
						if (keyField != null && valueField != null) {
							var k = toRustType(keyField.type, pos);
							var v = toRustType(valueField.type, pos);
							return RPath("hxrt::iter::KeyValue<" + rustTypeToString(k) + ", " + rustTypeToString(v) + ">");
						}
					}

					// General anonymous object / structural record.
					// Represent as a reference value to preserve Haxe aliasing + mutability semantics.
					return RPath("crate::HxRef<hxrt::anon::Anon>");
				}
			case _:
		}

		if (isArrayType(ft)) {
			var elem = arrayElementType(ft);
			var elemRust = toRustType(elem, pos);
			return RPath("hxrt::array::Array<" + rustTypeToString(elemRust) + ">");
		}

		return switch (ft) {
			case TEnum(enumRef, params): {
					var en = enumRef.get();
					var key = en.pack.join(".") + "." + en.name;
					if ((key == "haxe.ds.Option" || key == "rust.Option") && params.length == 1) {
						var t = toRustType(params[0], pos);
						RPath("Option<" + rustTypeToString(t) + ">");
					} else if ((key == "haxe.functional.Result" || key == "rust.Result") && params.length >= 1) {
						var okT = toRustType(params[0], pos);
						var errT = params.length >= 2 ? toRustType(params[1],
							pos) : (useNullableStringRepresentation() ? RPath(rustStringTypePath()) : RString);
						RPath("Result<" + rustTypeToString(okT) + ", " + rustTypeToString(errT) + ">");
					} else if (key == "haxe.io.Error") {
						RPath("hxrt::io::Error");
					} else {
						var modName = rustModuleNameForEnum(en);
						RPath("crate::" + modName + "::" + rustTypeNameForEnum(en));
					}
				}
			case TInst(clsRef, params): {
					var cls = clsRef.get();
					if (isRustAsyncFutureClass(cls)) {
						if (params == null || params.length != 1) {
							#if eval
							Context.error("`rust.async.Future<T>` requires exactly one type parameter.", pos);
							#end
							return RPath("hxrt::async_::HxFuture<()>");
						}
						var inner = toRustType(params[0], pos);
						return RPath("hxrt::async_::HxFuture<" + rustTypeToString(inner) + ">");
					}
					switch (cls.kind) {
						case KTypeParameter(_):
							return RPath(cls.name);
						case _:
					}
					if (isBytesClass(cls)) {
						return RPath("crate::HxRef<hxrt::bytes::Bytes>");
					}
					if (cls.isExtern) {
						var base = rustExternBasePath(cls);
						var path = base != null ? base : cls.name;
						if (params.length > 0) {
							var rustParams = [for (p in params) rustTypeToString(toRustType(p, pos))];
							path = path + "<" + rustParams.join(", ") + ">";
						}
						return RPath(path);
					}
					var typeParams = params != null
						&& params.length > 0 ? ("<" + [for (p in params) rustTypeToString(toRustType(p, pos))].join(", ") + ">") : "";
					if (cls.isInterface) {
						var modName = rustModuleNameForClass(cls);
						RPath(rcBasePath() + "<dyn crate::" + modName + "::" + rustTypeNameForClass(cls) + typeParams + " + Send + Sync>");
					} else if (classHasSubclasses(cls)) {
						var modName = rustModuleNameForClass(cls);
						RPath(rcBasePath() + "<dyn crate::" + modName + "::" + rustTypeNameForClass(cls) + "Trait" + typeParams + " + Send + Sync>");
					} else {
						var modName = rustModuleNameForClass(cls);
						RPath("crate::HxRef<crate::" + modName + "::" + rustTypeNameForClass(cls) + typeParams + ">");
					}
				}
			case _: {
					#if eval
					Context.error("Unsupported Rust type in POC: " + Std.string(t), pos);
					#end
					RUnit;
				}
		}
	}

	function isCopyType(t:Type):Bool {
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
		return switch (toRustType(t, pos)) {
			case RPath(p): isRustDynamicPath(p);
			case _: false;
		}
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
					// Arrays are represented as `hxrt::array::Array<T>`, not `HxRef<_>`.
					if (cls.pack.length == 0 && cls.module == "Array" && cls.name == "Array")
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
		return isHxRefValueType(t) || isRustHxRefType(t) || isAnonObjectType(t) || isInterfaceType(t) || isPolymorphicClassType(t);
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
		return switch (t) {
			case RUnit: "()";
			case RBool: "bool";
			case RI32: "i32";
			case RF64: "f64";
			case RString: rustStringTypePath();
			case RRef(inner, mutable): "&" + (mutable ? "mut " : "") + rustTypeToString(inner);
			case RPath(path): path;
		}
	}
}
#end
