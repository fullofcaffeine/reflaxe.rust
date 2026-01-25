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
import reflaxe.helpers.TypeHelper;
import reflaxe.rust.macros.CargoMetaRegistry;
import reflaxe.rust.macros.RustExtraSrcRegistry;
import reflaxe.rust.naming.RustNaming;

using reflaxe.helpers.BaseTypeHelper;
using reflaxe.helpers.ClassFieldHelper;

enum RustProfile {
	Portable;
	Idiomatic;
	Rusty;
}

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
	var didEmitMain: Bool = false;
	var crateName: String = "hx_app";
	var mainBaseType: Null<BaseType> = null;
	var mainClassKey: Null<String> = null;
	var currentClassKey: Null<String> = null;
	var currentClassName: Null<String> = null;
	var extraRustSrcDir: Null<String> = null;
	var extraRustSrcFiles: Array<{ module: String, fileName: String, fullPath: String }> = [];
	var classHasSubclass: Null<Map<String, Bool>> = null;
		var frameworkStdDir: Null<String> = null;
		var frameworkRuntimeDir: Null<String> = null;
		var profile: RustProfile = Portable;
		var currentMutatedLocals: Null<Map<Int, Bool>> = null;
		var currentArgNames: Null<Map<String, String>> = null;
		var currentLocalNames: Null<Map<Int, String>> = null;
		var currentLocalUsed: Null<Map<String, Bool>> = null;
		var currentEnumParamBinds: Null<Map<String, String>> = null;
		var rustNamesByClass: Map<String, { fields: Map<String, String>, methods: Map<String, String> }> = [];

	public function new() {
		super();
	}

	public function createCompilationContext(): CompilationContext {
		return new CompilationContext(crateName);
	}

	public function generateOutputIterator(): Iterator<DataAndFileInfo<StringOrBytes>> {
		return new RustOutputIterator(this);
	}

	override public function onCompileStart() {
		// Reset cached class hierarchy info per compilation.
		classHasSubclass = null;
		frameworkStdDir = null;
		frameworkRuntimeDir = null;

		// Optional profile selection.
		// - default: portable semantics
		// - `-D rust_idiomatic` or `-D reflaxe_rust_profile=idiomatic`: prefer cleaner Rust output
		// - `-D reflaxe_rust_profile=rusty`: opt into Rust-native APIs/interop (still framework-first)
		var profileDefine = Context.definedValue("reflaxe_rust_profile");
		var wantsRusty = profileDefine != null && profileDefine == "rusty";
		var wantsIdiomatic = Context.defined("rust_idiomatic") || (profileDefine != null && profileDefine == "idiomatic");
		profile = wantsRusty ? Rusty : (wantsIdiomatic ? Idiomatic : Portable);

		// Collect Cargo dependencies declared via `@:rustCargo(...)` metadata.
		CargoMetaRegistry.collectFromContext();

		// Collect extra Rust sources declared via metadata (framework code can bring its own modules).
		RustExtraSrcRegistry.collectFromContext();

		// Allow overriding crate name with -D rust_crate=<name>
		var v = Context.definedValue("rust_crate");
		if (v != null && v.length > 0) crateName = v;

		// Compute this haxelib's `std/` directory, if available, so we can emit framework wrappers.
		// (These should compile even when building from a different working directory.)
		try {
			var compilerPath = Context.resolvePath("reflaxe/rust/RustCompiler.hx");
			var rustDir = Path.directory(compilerPath); // .../src/reflaxe/rust
			var reflaxeDir = Path.directory(rustDir);   // .../src/reflaxe
			var srcDir = Path.directory(reflaxeDir);    // .../src
			var libraryRoot = Path.directory(srcDir);   // .../
			frameworkStdDir = Path.normalize(Path.join([libraryRoot, "std"]));
			frameworkRuntimeDir = Path.normalize(Path.join([libraryRoot, "runtime", "hxrt"]));
		} catch (e: haxe.Exception) {
			frameworkStdDir = null;
			frameworkRuntimeDir = null;
		}

		extraRustSrcFiles = [];
		var seenExtraRustModules = new Map<String, String>();
		function addExtraRustSrc(moduleName: String, fileName: String, fullPath: String, pos: haxe.macro.Expr.Position): Void {
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
					if (!StringTools.endsWith(entry, ".rs")) continue;
					if (entry == "main.rs" || entry == "lib.rs") continue;

					var full = Path.join([extraRustSrcDir, entry]);
					if (FileSystem.isDirectory(full)) continue;

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
			var gitignore = [
				"/target",
				"**/*.rs.bk",
			].join("\n") + "\n";
			setExtraFile(OutputPath.fromStr(".gitignore"), gitignore);
		}

		// Emit any extra Rust sources requested by `-D rust_extra_src=<dir>`.
		for (f in extraRustSrcFiles) {
			var content = File.getContent(f.fullPath);
			if (!StringTools.endsWith(content, "\n")) content += "\n";
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
				if (!StringTools.endsWith(content, "\n")) content += "\n";
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
				if (depsExtra.length > 0 && !StringTools.endsWith(depsExtra, "\n")) depsExtra += "\n";
			}
		} else {
			var depsInline = Context.definedValue("rust_cargo_deps");
			if (depsInline != null && depsInline.length > 0) depsExtra = depsInline + "\n";
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

	function emitRuntimeCrate(): Void {
		if (frameworkRuntimeDir == null) return;

		var root = normalizePath(frameworkRuntimeDir);
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root)) return;

		function walk(relDir: String): Void {
			var dirPath = relDir == "" ? root : normalizePath(Path.join([root, relDir]));
			for (entry in FileSystem.readDirectory(dirPath)) {
				if (entry == "target" || entry == "Cargo.lock") continue;
				var full = normalizePath(Path.join([dirPath, entry]));
				var rel = relDir == "" ? entry : normalizePath(Path.join([relDir, entry]));
				if (FileSystem.isDirectory(full)) {
					walk(rel);
				} else {
					var content = File.getContent(full);
					if (!StringTools.endsWith(content, "\n")) content += "\n";
					setExtraFile(OutputPath.fromStr("hxrt/" + rel), content);
				}
			}
		}

		walk("");
	}

	public function compileClassImpl(classType: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Null<RustFile> {
		var isMain = isMainClass(classType);
		if (!shouldEmitClass(classType, isMain)) return null;

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

		var items: Array<RustItem> = [];
		items.push(RRaw("// Generated by reflaxe.rust (POC)"));

			if (isMain) {
				var headerLines: Array<String> = [];

				var modLines: Array<String> = [];
				var seenMods = new Map<String, Bool>();
				function addMod(name: String) {
					if (seenMods.exists(name)) return;
					seenMods.set(name, true);
					modLines.push("mod " + name + ";");
				}

				// Extra modules (hand-written Rust sources)
				for (f in extraRustSrcFiles) addMod(f.module);

				// User classes
				var otherUserClasses = getUserClassesForModules();
				var lintLines: Array<String> = [];
				if (Context.defined("rust_deny_warnings")) {
					lintLines.push("#![deny(warnings)]");
				}
				lintLines.push("#![allow(dead_code)]");

				headerLines = headerLines.concat(lintLines.concat([
					"",
					"type HxRef<T> = std::rc::Rc<std::cell::RefCell<T>>;",
					""
				]));

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
				if (headerLines.length > 0) items.push(RRaw(headerLines.join("\n")));
			} else if (classType.isInterface) {
			// Interfaces compile to Rust traits (no struct allocation).
			items.push(RRaw("// Haxe interface -> Rust trait"));

			var traitLines: Array<String> = [];
			traitLines.push("pub trait " + classType.name + ": std::fmt::Debug {");
			for (f in funcFields) {
				if (f.isStatic) continue;
				if (f.expr != null) continue;

					var args: Array<String> = [];
					args.push("&self");
					var usedArgNames: Map<String, Bool> = [];
					for (a in f.args) {
						var baseName = a.getName();
						if (baseName == null || baseName.length == 0) baseName = "a";
						var argName = RustNaming.stableUnique(RustNaming.snakeIdent(baseName), usedArgNames);
						args.push(argName + ": " + rustTypeToString(toRustType(a.type, f.field.pos)));
					}

				var ret = rustTypeToString(toRustType(f.ret, f.field.pos));
				var sig = "\tfn " + rustMethodName(classType, f.field) + "(" + args.join(", ") + ") -> " + ret + ";";
				traitLines.push(sig);
			}
			traitLines.push("}");
			items.push(RRaw(traitLines.join("\n")));
			} else {
				// Stable RTTI id for this class (portable-mode baseline).
				items.push(RRaw("pub const __HX_TYPE_ID: u32 = " + typeIdLiteralForClass(classType) + ";"));

			var derives = mergeUniqueStrings(["Debug"], rustDerivesFromMeta(classType.meta));
			items.push(RRaw("#[derive(" + derives.join(", ") + ")]"));

			var structFields: Array<reflaxe.rust.ast.RustAST.RustStructField> = [];
			for (cf in getAllInstanceVarFieldsForStruct(classType)) {
				structFields.push({
					name: rustFieldName(classType, cf),
					ty: toRustType(cf.type, cf.pos),
					isPub: cf.isPublic
				});
			}

			items.push(RStruct({
				name: classType.name,
				isPub: true,
				fields: structFields
			}));

			var implFunctions: Array<reflaxe.rust.ast.RustAST.RustFunction> = [];

			// Constructor (`new`)
			var ctor = findConstructor(funcFields);
			if (ctor != null) {
				implFunctions.push(compileConstructor(classType, varFields, ctor));
			}

			// Instance methods
			for (f in funcFields) {
				if (f.isStatic) continue;
				if (f.field.getHaxeName() == "new") continue;
				if (f.expr == null) continue;
				implFunctions.push(compileInstanceMethod(classType, f));
			}

			// Static methods (associated functions on the type).
			for (f in funcFields) {
				if (!f.isStatic) continue;
				if (f.expr == null) continue;
				if (f.field.getHaxeName() == "main") continue;
				implFunctions.push(compileStaticMethod(classType, f));
			}

			items.push(RImpl({
				forType: classType.name,
				functions: implFunctions
			}));

			// Base-class polymorphism: if this class has subclasses, emit a trait for it.
			if (classHasSubclasses(classType)) {
				items.push(RRaw(emitClassTrait(classType, funcFields)));
				items.push(RRaw(emitClassTraitImplForSelf(classType, funcFields)));
			}

			// If this class has polymorphic base classes, implement their traits for this type.
			var base = classType.superClass != null ? classType.superClass.t.get() : null;
			while (base != null) {
				if (classHasSubclasses(base)) {
					items.push(RRaw(emitBaseTraitImplForSubclass(base, classType, funcFields)));
				}
				base = base.superClass != null ? base.superClass.t.get() : null;
			}

			// Implement any Haxe interfaces as Rust traits on `RefCell<Class>`.
			for (iface in classType.interfaces) {
				var ifaceType = iface.t.get();
				if (ifaceType == null) continue;
				if (!shouldEmitClass(ifaceType, false)) continue;

				var ifaceMod = rustModuleNameForClass(ifaceType);
				var traitPath = "crate::" + ifaceMod + "::" + ifaceType.name;

					var implLines: Array<String> = [];
					implLines.push("impl " + traitPath + " for std::cell::RefCell<" + classType.name + "> {");
					for (f in funcFields) {
						if (f.isStatic) continue;
						if (f.field.getHaxeName() == "new") continue;
						if (f.expr == null) continue;

					// Only include methods that match interface methods by name/arity.
					var matchesInterface = false;
					for (ifaceFieldName in ifaceType.fields.get().map(cf -> cf.getHaxeName())) {
						if (ifaceFieldName == f.field.getHaxeName()) {
							matchesInterface = true;
							break;
						}
					}
					if (!matchesInterface) continue;

						var sigArgs: Array<String> = ["&self"];
						var callArgs: Array<String> = ["self"];
						var usedArgNames: Map<String, Bool> = [];
						for (a in f.args) {
							var baseName = a.getName();
							if (baseName == null || baseName.length == 0) baseName = "a";
							var argName = RustNaming.stableUnique(RustNaming.snakeIdent(baseName), usedArgNames);
							sigArgs.push(argName + ": " + rustTypeToString(toRustType(a.type, f.field.pos)));
							callArgs.push(argName);
						}

					var ret = rustTypeToString(toRustType(f.ret, f.field.pos));
					var ifaceRustName = rustMethodName(ifaceType, f.field);
					var implRustName = rustMethodName(classType, f.field);
					implLines.push("\tfn " + ifaceRustName + "(" + sigArgs.join(", ") + ") -> " + ret + " {");
					implLines.push("\t\t" + classType.name + "::" + implRustName + "(" + callArgs.join(", ") + ")");
					implLines.push("\t}");
				}
				implLines.push("}");
				items.push(RRaw(implLines.join("\n")));
			}
		}

		if (isMain) {
				// Emit any additional static functions so user code can call them from `main`.
				for (f in funcFields) {
					if (!f.isStatic) continue;
					if (f.expr == null) continue;

					var haxeName = f.field.getHaxeName();
					if (haxeName == "main") continue;

					var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
					var body = { stmts: [], tail: null };
					withFunctionContext(f.expr, [for (a in f.args) a.getName()], () -> {
						for (a in f.args) {
							args.push({
								name: rustArgIdent(a.getName()),
								ty: toRustType(a.type, f.field.pos)
							});
						}
						body = compileFunctionBody(f.expr, f.ret);
					});

					items.push(RFn({
						name: rustMethodName(classType, f.field),
						isPub: false,
						args: args,
						ret: toRustType(f.ret, f.field.pos),
						body: body
					}));
				}

				var mainFunc = findStaticMain(funcFields);
				// Rust `fn main()` is always unit-returning; compile as void to avoid accidental tail expressions.
				var body: RustBlock = (mainFunc != null && mainFunc.expr != null) ? compileVoidBodyWithContext(mainFunc.expr, []) : defaultMainBody();

			items.push(RFn({
				name: "main",
				isPub: false,
				args: [],
				ret: RUnit,
				body: body
			}));
		}

		currentClassKey = null;
		currentClassName = null;
		return { items: items };
	}

	public function compileEnumImpl(enumType: EnumType, options: Array<EnumOptionData>): Null<RustFile> {
		if (!shouldEmitEnum(enumType)) return null;

		setOutputFileDir("src");
		setOutputFileName(rustModuleNameForEnum(enumType));

			var items: Array<RustItem> = [];
			items.push(RRaw("// Generated by reflaxe.rust (POC)"));

			var variants: Array<reflaxe.rust.ast.RustAST.RustEnumVariant> = [];

			for (opt in options) {
				var argTypes: Array<reflaxe.rust.ast.RustAST.RustType> = [];
				for (a in opt.args) {
					var rt = toRustType(a.type, opt.field.pos);
					argTypes.push(rt);
				}
				variants.push({ name: opt.name, args: argTypes });
			}

			var derives = mergeUniqueStrings(["Clone", "Debug", "PartialEq"], rustDerivesFromMeta(enumType.meta));
		items.push(REnum({
			name: enumType.name,
			isPub: true,
			derives: derives,
			variants: variants
		}));

		return { items: items };
	}

	override public function compileTypedefImpl(typedefType: DefType): Null<RustFile> {
		return null;
	}

	override public function compileAbstractImpl(abstractType: AbstractType): Null<RustFile> {
		return null;
	}

	public function compileExpressionImpl(expr: TypedExpr, topLevel: Bool): Null<RustExpr> {
		return compileExpr(expr);
	}

	function isMainClass(classType: ClassType): Bool {
		var m = getMainModule();
		return switch (m) {
			case TClassDecl(clsRef): {
				var mainCls = clsRef.get();
				(mainCls.module == classType.module && mainCls.name == classType.name && mainCls.pack.join(".") == classType.pack.join("."));
			}
			case _: false;
		}
	}

	function findStaticMain(funcFields: Array<ClassFuncData>): Null<ClassFuncData> {
		for (f in funcFields) {
			if (!f.isStatic) continue;
			if (f.field.getHaxeName() != "main") continue;
			return f;
		}
		return null;
	}

	function defaultMainBody(): RustBlock {
		return {
			stmts: [
				RSemi(EMacroCall("println", [ELitString("hi")]))
			],
			tail: null
		};
	}

	function shouldEmitClass(classType: ClassType, isMain: Bool): Bool {
		if (isMain) return true;
		if (classType.isExtern) return false;
		var file = Context.getPosInfos(classType.pos).file;
		return isUserProjectFile(file) || isFrameworkStdFile(file);
	}

	function shouldEmitEnum(enumType: EnumType): Bool {
		if (enumType.isExtern) return false;
		if (isBuiltinEnum(enumType)) return false;
		var file = Context.getPosInfos(enumType.pos).file;
		return isUserProjectFile(file) || isFrameworkStdFile(file);
	}

	function isUserProjectFile(file: String): Bool {
		var cwd = normalizePath(Sys.getCwd());
		var full = file;
		if (!Path.isAbsolute(full)) {
			full = Path.join([cwd, full]);
		}
		full = normalizePath(full);
		return StringTools.startsWith(full, ensureTrailingSlash(cwd));
	}

	function isFrameworkStdFile(file: String): Bool {
		if (frameworkStdDir == null) return false;
		var stdRoot = ensureTrailingSlash(normalizePath(frameworkStdDir));

		var cwd = normalizePath(Sys.getCwd());
		var full = file;
		if (!Path.isAbsolute(full)) {
			full = Path.join([cwd, full]);
		}
		full = normalizePath(full);

		return StringTools.startsWith(full, stdRoot);
	}

	function ensureTrailingSlash(path: String): String {
		return StringTools.endsWith(path, "/") ? path : (path + "/");
	}

	function normalizePath(path: String): String {
		return Path.normalize(path).split("\\").join("/");
	}

	function classKey(classType: ClassType): String {
		return classType.pack.join(".") + "." + classType.name;
	}

	function rustModuleNameForClass(classType: ClassType): String {
		var base = (classType.pack.length > 0 ? (classType.pack.join("_") + "_") : "") + classType.name;
		return RustNaming.snakeIdent(base);
	}

	function rustModuleNameForEnum(enumType: EnumType): String {
		var base = (enumType.pack.length > 0 ? (enumType.pack.join("_") + "_") : "") + enumType.name;
		return RustNaming.snakeIdent(base);
	}

	function isValidRustIdent(name: String): Bool {
		return RustNaming.isValidIdent(name);
	}

	function isRustKeyword(name: String): Bool {
		return RustNaming.isKeyword(name);
	}

		function rustMemberBaseIdent(haxeName: String): String {
			return RustNaming.snakeIdent(haxeName);
		}

	function ensureRustNamesForClass(classType: ClassType): Void {
		var key = classKey(classType);
		if (rustNamesByClass.exists(key)) return;

		var fieldUsed: Map<String, Bool> = [];
		var methodUsed: Map<String, Bool> = [];
		var fieldMap: Map<String, String> = [];
		var methodMap: Map<String, String> = [];

		// Instance fields that become struct fields.
		var fieldNames: Array<String> = [];
		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			fieldNames.push(cf.getHaxeName());
		}
		for (name in fieldNames) {
			var base = rustMemberBaseIdent(name);
			fieldMap.set(name, RustNaming.stableUnique(base, fieldUsed));
		}

		// Methods (instance + static).
		var methodNames: Array<String> = [];
		for (cf in classType.fields.get()) {
			switch (cf.kind) {
				case FMethod(_):
					methodNames.push(cf.getHaxeName());
				case _:
			}
		}
		for (cf in classType.statics.get()) {
			switch (cf.kind) {
				case FMethod(_):
					methodNames.push(cf.getHaxeName());
				case _:
			}
		}
		methodNames.sort(Reflect.compare);
		for (name in methodNames) {
			var base = rustMemberBaseIdent(name);
			methodMap.set(name, RustNaming.stableUnique(base, methodUsed));
		}

		rustNamesByClass.set(key, { fields: fieldMap, methods: methodMap });
	}

	function rustFieldName(classType: ClassType, cf: ClassField): String {
		ensureRustNamesForClass(classType);
		var entry = rustNamesByClass.get(classKey(classType));
		var name = cf.getHaxeName();
		return entry != null && entry.fields.exists(name) ? entry.fields.get(name) : rustMemberBaseIdent(name);
	}

	function rustMethodName(classType: ClassType, cf: ClassField): String {
		ensureRustNamesForClass(classType);
		var entry = rustNamesByClass.get(classKey(classType));
		var name = cf.getHaxeName();
		return entry != null && entry.methods.exists(name) ? entry.methods.get(name) : rustMemberBaseIdent(name);
	}

	function rustGetterName(classType: ClassType, cf: ClassField): String {
		return "__hx_get_" + rustFieldName(classType, cf);
	}

	function rustSetterName(classType: ClassType, cf: ClassField): String {
		return "__hx_set_" + rustFieldName(classType, cf);
	}

	function resolveToAbsolutePath(p: String): String {
		var full = p;
		if (!Path.isAbsolute(full)) {
			full = Path.join([Sys.getCwd(), full]);
		}
		return Path.normalize(full);
	}

	function getUserClassesForModules(): Array<ClassType> {
		var out: Array<ClassType> = [];
		var seen = new Map<String, Bool>();

		for (mt in Context.getAllModuleTypes()) {
			switch (mt) {
				case TClassDecl(clsRef): {
					var cls = clsRef.get();
					if (cls == null) continue;
					if (isMainClass(cls)) continue;
					if (!shouldEmitClass(cls, false)) continue;

					var key = classKey(cls);
					if (seen.exists(key)) continue;
					seen.set(key, true);
					out.push(cls);
				}
				case _:
			}
		}

		out.sort((a, b) -> Reflect.compare(classKey(a), classKey(b)));
		return out;
	}

	function getUserEnumsForModules(): Array<EnumType> {
		var out: Array<EnumType> = [];
		var seen = new Map<String, Bool>();

		for (mt in Context.getAllModuleTypes()) {
			switch (mt) {
				case TEnumDecl(enumRef): {
					var en = enumRef.get();
					if (en == null) continue;
					if (!shouldEmitEnum(en)) continue;

					var key = en.pack.join(".") + "." + en.name;
					if (seen.exists(key)) continue;
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
		if (!didEmitMain) return;
		if (output == null || output.outputDir == null) return;

		var outDir = output.outputDir;
		var manifest = Path.join([outDir, "Cargo.toml"]);
		if (!FileSystem.exists(manifest)) return;

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
			if (cargoCmd == null || cargoCmd.length == 0) cargoCmd = "cargo";

			var subcommand = Context.definedValue("rust_cargo_subcommand");
			if (subcommand == null || subcommand.length == 0) subcommand = "build";

			var targetDir = Context.definedValue("rust_cargo_target_dir");
			if (targetDir != null && targetDir.length > 0) {
				Sys.putEnv("CARGO_TARGET_DIR", targetDir);
			}

			var args = [subcommand, "--manifest-path", manifest];

			if (Context.defined("rust_cargo_quiet")) args.push("-q");
			if (Context.defined("rust_cargo_locked")) args.push("--locked");
			if (Context.defined("rust_cargo_offline")) args.push("--offline");
			if (Context.defined("rust_cargo_no_default_features")) args.push("--no-default-features");
			if (Context.defined("rust_cargo_all_features")) args.push("--all-features");

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

	function findConstructor(funcFields: Array<ClassFuncData>): Null<ClassFuncData> {
		for (f in funcFields) {
			if (f.isStatic) continue;
			if (f.field.getHaxeName() != "new") continue;
			return f;
		}
		return null;
	}

	function defaultValueForType(t: Type, pos: haxe.macro.Expr.Position): String {
		if (TypeHelper.isBool(t)) return "false";
		if (TypeHelper.isInt(t)) return "0";
		if (TypeHelper.isFloat(t)) return "0.0";
		if (isStringType(t)) return "String::new()";
		if (isArrayType(t)) {
			var elem = arrayElementType(t);
			var elemRust = toRustType(elem, pos);
			return "Vec::<" + rustTypeToString(elemRust) + ">::new()";
		}

		#if eval
		Context.error("Unsupported field type in class POC: " + Std.string(t), pos);
		#end
		return "Default::default()";
	}

		function compileConstructor(classType: ClassType, varFields: Array<ClassVarData>, f: ClassFuncData): reflaxe.rust.ast.RustAST.RustFunction {
			var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
			var modName = rustModuleNameForClass(classType);
			var selfRefTy = RPath("crate::HxRef<crate::" + modName + "::" + classType.name + ">");

			var fieldInits: Array<String> = [];
			for (cf in getAllInstanceVarFieldsForStruct(classType)) {
				fieldInits.push(rustFieldName(classType, cf) + ": " + defaultValueForType(cf.type, cf.pos));
			}
		var structInit = classType.name + " { " + fieldInits.join(", ") + " }";
		var allocExpr = "std::rc::Rc::new(std::cell::RefCell::new(" + structInit + "))";

			var stmts: Array<RustStmt> = [];
			if (f.expr != null) {
				withFunctionContext(f.expr, [for (a in f.args) a.getName()], () -> {
					for (a in f.args) {
						args.push({
							name: rustArgIdent(a.getName()),
							ty: toRustType(a.type, f.field.pos)
						});
					}

					stmts.push(RLet(
						"self_",
						false,
						selfRefTy,
						ERaw(allocExpr)
					));

					var bodyBlock = compileFunctionBody(f.expr, f.ret);
					for (s in bodyBlock.stmts) stmts.push(s);
					if (bodyBlock.tail != null) stmts.push(RSemi(bodyBlock.tail));

					stmts.push(RReturn(EPath("self_")));
				});
			}

			return {
				name: "new",
				isPub: true,
				args: args,
				ret: selfRefTy,
				body: { stmts: stmts, tail: null }
			};
		}

		function compileInstanceMethod(classType: ClassType, f: ClassFuncData): reflaxe.rust.ast.RustAST.RustFunction {
			var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
			var generics = rustGenericParamsFromFieldMeta(f.field.meta, [for (p in f.field.params) p.name]);
			var selfName = exprUsesThis(f.expr) ? "self_" : "_self_";
			args.push({
				name: selfName,
				ty: RPath("&std::cell::RefCell<" + classType.name + ">")
			});
			var body = { stmts: [], tail: null };
			withFunctionContext(f.expr, [for (a in f.args) a.getName()], () -> {
				for (a in f.args) {
					args.push({
						name: rustArgIdent(a.getName()),
						ty: toRustType(a.type, f.field.pos)
					});
				}
				body = compileFunctionBody(f.expr, f.ret);
			});

			return {
				name: rustMethodName(classType, f.field),
				isPub: f.field.isPublic,
			generics: generics,
			args: args,
			ret: toRustType(f.ret, f.field.pos),
			body: body
		};
	}

		function compileStaticMethod(classType: ClassType, f: ClassFuncData): reflaxe.rust.ast.RustAST.RustFunction {
			var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
			var generics = rustGenericParamsFromFieldMeta(f.field.meta, [for (p in f.field.params) p.name]);
			var body = { stmts: [], tail: null };
			withFunctionContext(f.expr, [for (a in f.args) a.getName()], () -> {
				for (a in f.args) {
					args.push({
						name: rustArgIdent(a.getName()),
						ty: toRustType(a.type, f.field.pos)
					});
				}
				body = compileFunctionBody(f.expr, f.ret);
			});

			return {
				name: rustMethodName(classType, f.field),
				isPub: f.field.isPublic,
			generics: generics,
			args: args,
			ret: toRustType(f.ret, f.field.pos),
			body: body
		};
	}

	function rustGenericParamsFromFieldMeta(meta: haxe.macro.Type.MetaAccess, fallback: Array<String>): Array<String> {
		var out: Array<String> = [];
		var found = false;

		for (entry in meta.get()) {
			if (entry.name != ":rustGeneric") continue;
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
				case EArrayDecl(values): {
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

	function compileFunctionBody(e: TypedExpr, expectedReturn: Null<Type> = null): RustBlock {
		var allowTail = true;
		if (expectedReturn != null && TypeHelper.isVoid(expectedReturn)) {
			allowTail = false;
		}

		return switch (e.expr) {
			case TBlock(exprs): compileBlock(exprs, allowTail);
			case _: {
				// Single-expression function body
				{ stmts: [compileStmt(e)], tail: null };
			}
		}
	}

		function compileBlock(exprs: Array<TypedExpr>, allowTail: Bool = true): RustBlock {
			var stmts: Array<RustStmt> = [];
			var tail: Null<RustExpr> = null;

			for (i in 0...exprs.length) {
				var e = exprs[i];
				var isLast = (i == exprs.length - 1);

				if (allowTail && isLast && !TypeHelper.isVoid(e.t) && !isStmtOnlyExpr(e)) {
					tail = compileExpr(e);
					break;
				}

				stmts.push(compileStmt(e));

				// Avoid emitting Rust code that is statically unreachable (and triggers `unreachable_code` warnings).
				// Haxe may type-check expressions after `throw`/`return` even when they can never run.
				if (exprAlwaysDiverges(e)) break;
			}

			return { stmts: stmts, tail: tail };
		}

		function isStmtOnlyExpr(e: TypedExpr): Bool {
			return switch (e.expr) {
				case TVar(_, _): true;
				case TReturn(_): true;
				case TWhile(_, _, _): true;
				case TFor(_, _, _): true;
				case TBreak: true;
				case TContinue: true;
				case _: false;
			}
		}

		function exprAlwaysDiverges(e: TypedExpr): Bool {
			var cur = unwrapMetaParen(e);
			return switch (cur.expr) {
				case TThrow(_): true;
				case TReturn(_): true;
				case TBreak: true;
				case TContinue: true;
				case _: false;
			}
		}

		function compileStmt(e: TypedExpr): RustStmt {
			return switch (e.expr) {
				case TBlock(exprs): {
					// Haxe desugars `for (x in iterable)` into:
					// `{ var it = iterable.iterator(); while (it.hasNext()) { var x = it.next(); body } }`
					//
					// For Rusty surfaces (Vec/Slice), lower this back to a Rust `for` loop and avoid
					// having to represent Haxe's `Iterator<T>` type in the backend.
					function iterClonedExpr(x: TypedExpr): RustExpr {
						var base = ECall(EField(compileExpr(x), "iter"), []);
						return ECall(EField(base, iterBorrowMethod(x.t)), []);
					}

					function matchesFieldName(fa: FieldAccess, expected: String): Bool {
						return switch (fa) {
							case FInstance(_, _, cfRef):
								var cf = cfRef.get();
								cf != null && cf.getHaxeName() == expected;
							case FAnon(cfRef):
								var cf = cfRef.get();
								cf != null && cf.getHaxeName() == expected;
							case FClosure(_, cfRef):
								var cf = cfRef.get();
								cf != null && cf.getHaxeName() == expected;
							case FDynamic(name):
								name == expected;
							case _:
								false;
						}
					}

					function extractRustForIterable(init: TypedExpr): Null<RustExpr> {
						function unwrapMetaParenCast(e: TypedExpr): TypedExpr {
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

										// HashMap-style iterators (`keys()` / `values()`) are already valid Rust
										// iterables; use them directly (borrowed items, no cloning).
										if (matchesFieldName(fa, "keys") || matchesFieldName(fa, "values")) {
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

					function tryLowerDesugaredFor(exprs: Array<TypedExpr>): Null<RustStmt> {
						if (exprs == null || exprs.length < 2) return null;

						// Statement-position blocks often include stray `null` expressions; ignore them
						// so we can pattern-match the canonical `for` desugaring shape.
						function stripNulls(es: Array<TypedExpr>): Array<TypedExpr> {
							var out: Array<TypedExpr> = [];
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
						if (es.length != 2) return null;

						var first = unwrapMetaParen(es[0]);
						var second = unwrapMetaParen(es[1]);

						var itVar: Null<TVar> = null;
						var itInit: Null<TypedExpr> = null;
						switch (first.expr) {
							case TVar(v, init) if (init != null):
								itVar = v;
								itInit = init;
							case _:
								return null;
						}

						switch (second.expr) {
							case TWhile(cond, body, normalWhile) if (normalWhile): {
								function isIterMethodCall(callExpr: TypedExpr, expected: String): Bool {
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
									case TCall(callExpr, []) : {
										if (!isIterMethodCall(callExpr, "hasNext")) return null;
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
								if (bodyExprs.length == 0) return null;

								var head = unwrapMetaParen(bodyExprs[0]);
								var loopVar: Null<TVar> = null;
								switch (head.expr) {
									case TVar(v, init) if (init != null): {
										// init must be it.next()
										var initU = unwrapMetaParen(init);
										switch (initU.expr) {
											case TCall(callExpr, []):
												if (!isIterMethodCall(callExpr, "next")) return null;
												loopVar = v;
											case _:
												return null;
										}
									}
									case _:
										return null;
								}
								if (loopVar == null) return null;

								var it = extractRustForIterable(itInit);
								if (it == null) return null;

								var bodyBlock = compileBlock(bodyExprs.slice(1), false);
								return RFor(rustLocalDeclIdent(loopVar), it, bodyBlock);
							}
							case _:
								return null;
						}
					}

					var lowered = tryLowerDesugaredFor(exprs);
					if (lowered != null) return lowered;

					// Fallback: treat block as a statement-position expression.
					RSemi(EBlock(compileBlock(exprs, false)));
				}
				case TVar(v, init): {
					var name = rustLocalDeclIdent(v);
					var rustTy = toRustType(v.t, e.pos);
					var initExpr = init != null ? compileExpr(init) : null;
					if (initExpr != null) {
						switch (followType(v.t)) {
							// Function values require coercion into our function representation.
							case TFun(_, _):
								initExpr = coerceArgForParam(initExpr, init, v.t);
							case _:
								initExpr = wrapBorrowIfNeeded(initExpr, rustTy, init);
						}
					}
					var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(v.id);
					RLet(name, mutable, rustTy, initExpr);
				}
			case TParenthesis(e1):
				compileStmt(e1);
			case TMeta(_, e1):
				compileStmt(e1);
			case TSwitch(switchExpr, cases, edef):
				// Statement-position switch: force void arms.
				RSemi(compileSwitch(switchExpr, cases, edef, Context.getType("Void")));
			case TWhile(cond, body, normalWhile): {
				if (normalWhile) {
					RWhile(compileExpr(cond), compileVoidBody(body));
				} else {
					// do/while: `loop { body; if !cond { break; } }`
					var b = compileVoidBody(body);
					var stmts = b.stmts.copy();
					if (b.tail != null) stmts.push(RSemi(b.tail));
					stmts.push(RSemi(EIf(
						EUnary("!", compileExpr(cond)),
						EBlock({ stmts: [RSemi(ERaw("break"))], tail: null }),
						null
					)));
					RLoop({ stmts: stmts, tail: null });
				}
			}
				case TFor(v, iterable, body): {
					function iterCloned(x: TypedExpr): RustExpr {
						var base = ECall(EField(compileExpr(x), "iter"), []);
						return ECall(EField(base, iterBorrowMethod(x.t)), []);
					}

					var it: RustExpr = switch (unwrapMetaParen(iterable).expr) {
						// Many custom iterables typecheck by providing `iterator()`. We lower specific
						// rusty surfaces to Rust iterators to avoid moving values (Haxe values are reusable).
						case TCall(call, []) : switch (unwrapMetaParen(call).expr) {
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
				var ex = ret != null ? compileExpr(ret) : null;
				RReturn(ex);
			}
			case _: {
				RSemi(compileExpr(e));
			}
		}
	}

		function compileVoidBody(e: TypedExpr): RustBlock {
			return switch (e.expr) {
				case TBlock(exprs):
					compileBlock(exprs, false);
				case _:
					{ stmts: [compileStmt(e)], tail: null };
			}
		}

		function withFunctionContext<T>(bodyExpr: TypedExpr, argNames: Array<String>, fn: () -> T): T {
			var prevMutated = currentMutatedLocals;
			var prevArgNames = currentArgNames;
			var prevLocalNames = currentLocalNames;
			var prevLocalUsed = currentLocalUsed;
			var prevEnumParamBinds = currentEnumParamBinds;

			currentMutatedLocals = collectMutatedLocals(bodyExpr);
			currentArgNames = [];
			currentLocalNames = [];
			currentLocalUsed = [];
			currentEnumParamBinds = null;

			// Reserve internal temporaries to avoid collisions with user locals.
			for (n in ["self_", "__tmp", "__hx_ok", "__hx_ex", "__hx_box", "__p"]) {
				currentLocalUsed.set(n, true);
			}

			// Pre-allocate argument names so we can use them consistently in the signature + body.
			if (argNames == null) argNames = [];
			for (n in argNames) {
				var base = RustNaming.snakeIdent(n);
				var rust = RustNaming.stableUnique(base, currentLocalUsed);
				currentArgNames.set(n, rust);
			}

			var out = fn();

			currentMutatedLocals = prevMutated;
			currentArgNames = prevArgNames;
			currentLocalNames = prevLocalNames;
			currentLocalUsed = prevLocalUsed;
			currentEnumParamBinds = prevEnumParamBinds;
			return out;
		}

		function rustArgIdent(name: String): String {
			if (currentArgNames != null && currentArgNames.exists(name)) {
				return currentArgNames.get(name);
			}
			return RustNaming.snakeIdent(name);
		}

		function rustLocalDeclIdent(v: TVar): String {
			if (v == null) return "_";

			// If we're inside a function context, ensure stable/unique snake_case naming.
			if (currentLocalNames != null && currentLocalUsed != null) {
				if (currentLocalNames.exists(v.id)) return currentLocalNames.get(v.id);
				var base = RustNaming.snakeIdent(v.name);
				var rust = RustNaming.stableUnique(base, currentLocalUsed);
				currentLocalNames.set(v.id, rust);
				return rust;
			}

			return RustNaming.snakeIdent(v.name);
		}

		function rustLocalRefIdent(v: TVar): String {
			if (v == null) return "_";

			// If already declared/seen, reuse the assigned name.
			if (currentLocalNames != null && currentLocalNames.exists(v.id)) {
				return currentLocalNames.get(v.id);
			}

			// Function arguments are referenced as locals in the typed AST.
			if (currentArgNames != null && currentArgNames.exists(v.name)) {
				var rust = currentArgNames.get(v.name);
				if (currentLocalNames != null) currentLocalNames.set(v.id, rust);
				return rust;
			}

			// Fallback: treat as a local.
			return rustLocalDeclIdent(v);
		}

		function compileFunctionBodyWithContext(e: TypedExpr, expectedReturn: Null<Type>, argNames: Array<String>): RustBlock {
			return withFunctionContext(e, argNames, () -> compileFunctionBody(e, expectedReturn));
		}

		function compileVoidBodyWithContext(e: TypedExpr, argNames: Array<String>): RustBlock {
			return withFunctionContext(e, argNames, () -> compileVoidBody(e));
		}

		function collectMutatedLocals(root: TypedExpr): Map<Int, Bool> {
			var mutated: Map<Int, Bool> = [];

			function unwrapToLocal(e: TypedExpr): Null<TVar> {
				var cur = unwrapMetaParen(e);

				while (true) {
					switch (cur.expr) {
						case TCast(inner, _):
							cur = unwrapMetaParen(inner);
							continue;

						// Handle `@:from` conversions that appear as calls (common for `rust.Ref` / `rust.MutRef`).
						case TCall(callExpr, args) if (args.length == 1): {
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

			function markLocal(e: TypedExpr): Void {
				var v = unwrapToLocal(e);
				if (v != null) mutated.set(v.id, true);
			}

		function isRustMutRefType(t: Type): Bool {
			return switch (followType(t)) {
				case TAbstract(absRef, _): {
					var abs = absRef.get();
					abs.pack.join(".") + "." + abs.name == "rust.MutRef";
				}
				case _:
					false;
			}
		}

		function isMutatingMethod(cf: ClassField): Bool {
			for (m in cf.meta.get()) {
				if (m.name == ":rustMutating" || m.name == "rustMutating") return true;
			}
			return false;
		}

		function scan(e: TypedExpr): Void {
			switch (e.expr) {
				case TVar(v, init) if (init != null && isRustMutRefType(v.t)):
					// Taking a `rust.MutRef<T>` from a local requires the source binding to be `mut`.
					markLocal(init);

					case TBinop(OpAssign, lhs, _): {
						switch (lhs.expr) {
							case TLocal(v):
								mutated.set(v.id, true);
							case TArray(arr, _): {
								switch (arr.expr) {
									case TLocal(v):
										mutated.set(v.id, true);
									case _:
								}
							}
							case _:
						}
					}

					case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement): {
						switch (inner.expr) {
							case TLocal(v):
								mutated.set(v.id, true);
							case _:
						}
					}

				case TCall(callExpr, _) : {
					// If we call a known mutating method, require `let mut <receiver>`.
					switch (callExpr.expr) {
						case TField(obj, FInstance(_, _, cfRef)): {
							var cf = cfRef.get();
							if (cf != null && isMutatingMethod(cf)) {
								markLocal(obj);
							}

							// Heuristic: common Array mutations (portable arrays map to Rust Vec).
							if (isArrayType(obj.t)) {
								var name = cf != null ? cf.getHaxeName() : "";
								switch (name) {
									case "push" | "pop" | "shift" | "unshift" | "insert" | "remove" | "reverse" | "sort" | "splice":
										markLocal(obj);
									case _:
								}
							}
						}
						case _:
					}
				}

				case _:
			}

			TypedExprTools.iter(e, scan);
		}

		scan(root);
		return mutated;
	}

	function compileExpr(e: TypedExpr): RustExpr {
			// Target code injection: __rust__("...{0}...", arg0, ...)
			var injected = TargetCodeInjection.checkTargetCodeInjectionGeneric(options.targetCodeInjectionName ?? "__rust__", e, this);
			if (injected != null) {
				// `checkTargetCodeInjectionGeneric` returns an empty list when there are no `{0}` placeholders.
				// In that case, the injected code is just the first (string) argument verbatim.
				if (injected.length == 0) {
					var literal: Null<String> = switch (e.expr) {
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
						case Left(s): rendered.add(s);
						case Right(expr): rendered.add(reflaxe.rust.ast.RustASTPrinter.printExprForInjection(expr));
					}
				}
				return ERaw(rendered.toString());
			}

			return switch (e.expr) {
			case TConst(c): switch (c) {
				case TInt(v): ELitInt(v);
				case TFloat(s): ELitFloat(Std.parseFloat(s));
				case TString(s): ECall(EPath("String::from"), [ELitString(s)]);
				case TBool(b): ELitBool(b);
				case TNull: ERaw("None");
				case TThis: EPath("self_");
				case _: unsupported(e, "const");
			}

			case TArrayDecl(values): {
				// Haxe `Array<T>` literal: `[]` or `[a, b]` -> `Vec::<T>::new()` or `vec![...]`
				if (values.length == 0) {
					var elem = arrayElementType(e.t);
					var elemRust = toRustType(elem, e.pos);
					ECall(ERaw("Vec::<" + rustTypeToString(elemRust) + ">::new"), []);
				} else {
					EMacroCall("vec", [for (v in values) compileExpr(v)]);
				}
			}

			case TArray(arr, index): {
				var idx = ECast(compileExpr(index), "usize");
				var access = EIndex(compileExpr(arr), idx);
				if (isCopyType(e.t)) {
					access;
				} else {
					ECall(EField(access, "clone"), []);
				}
			}

				case TLocal(v):
					EPath(rustLocalRefIdent(v));

			case TBinop(op, e1, e2):
				compileBinop(op, e1, e2, e);

			case TUnop(op, postFix, expr):
				compileUnop(op, postFix, expr, e);

			case TIf(cond, eThen, eElse):
				EIf(compileExpr(cond), compileBranchExpr(eThen), eElse != null ? compileBranchExpr(eElse) : null);

			case TBlock(exprs):
				EBlock(compileBlock(exprs));

			case TCall(callExpr, args):
				compileCall(callExpr, args, e);

				case TNew(clsRef, _, args): {
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
						"crate::" + rustModuleNameForClass(cls) + "::" + cls.name;
					} else {
						"todo!()";
					}
					ECall(EPath(ctorBase + "::new"), [for (x in args) compileExpr(x)]);
				}

			case TTypeExpr(mt):
				compileTypeExpr(mt, e);

			case TField(obj, fa):
				compileField(obj, fa, e);

			case TWhile(_, _, _) | TFor(_, _, _):
				// Loops are statements in Rust; if they appear in expression position, wrap in a block.
				EBlock({ stmts: [compileStmt(e)], tail: null });

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

			case TMeta(_, e1):
				compileExpr(e1);

			case TFunction(fn): {
				// Lower a Haxe function literal to a Rust `Rc<dyn Fn(...) -> ...>`.
				// NOTE: This is a baseline: we emit a `move` closure and rely on captured values
				// being owned (cloned) so the closure can be `'static` for storage/passing.
				var baseArgNames: Array<String> = [];
				for (a in fn.args) {
					var n = (a.v != null && a.v.name != null && a.v.name.length > 0) ? a.v.name : "a";
					baseArgNames.push(n);
				}

				var argParts: Array<String> = [];
				var body: RustBlock = { stmts: [], tail: null };

				withFunctionContext(fn.expr, baseArgNames, () -> {
					for (i in 0...fn.args.length) {
						var a = fn.args[i];
						var baseName = baseArgNames[i];
						var rustName = rustArgIdent(baseName);
						argParts.push(rustName + ": " + rustTypeToString(toRustType(a.v.t, e.pos)));
					}
					body = compileFunctionBody(fn.expr, fn.t);
				});

				ECall(EPath("std::rc::Rc::new"), [EClosure(argParts, body, true)]);
			}

			case TCast(e1, _): {
				var inner = compileExpr(e1);
				var fromT = followType(e1.t);
				var toT = followType(e.t);

				// Numeric casts (`Int` <-> `Float`) must be explicit in Rust.
				if ((TypeHelper.isInt(fromT) || TypeHelper.isFloat(fromT)) && (TypeHelper.isInt(toT) || TypeHelper.isFloat(toT))) {
					var target = rustTypeToString(toRustType(toT, e.pos));
					ECast(inner, target);
				} else {
					inner;
				}
			}

			default:
				unsupported(e, "expr");
		}
	}

	function compileTypeExpr(mt: ModuleType, fullExpr: TypedExpr): RustExpr {
		return switch (mt) {
			case TClassDecl(clsRef): {
				var cls = clsRef.get();
				var modName = rustModuleNameForClass(cls);
				EPath("crate::" + modName + "::__HX_TYPE_ID");
			}
			case _: unsupported(fullExpr, "type expr");
		}
	}

	function compileSwitch(switchExpr: TypedExpr, cases: Array<{ values: Array<TypedExpr>, expr: TypedExpr }>, edef: Null<TypedExpr>, expectedReturn: Type): RustExpr {
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

	function compileExprToBlock(e: TypedExpr, expectedReturn: Type): RustBlock {
		var allowTail = !TypeHelper.isVoid(expectedReturn);
		return switch (e.expr) {
			case TBlock(exprs):
				compileBlock(exprs, allowTail);
			case _:
				if (allowTail && !isStmtOnlyExpr(e)) {
					{ stmts: [], tail: compileExpr(e) };
				} else {
					{ stmts: [compileStmt(e)], tail: null };
				}
		}
	}

	function compileThrow(thrown: TypedExpr, pos: haxe.macro.Expr.Position): RustExpr {
		var payload = ECall(EPath("hxrt::dynamic::from"), [compileExpr(thrown)]);
		return ECall(EPath("hxrt::exception::throw"), [payload]);
	}

		function compileTry(tryExpr: TypedExpr, catches: Array<{ v: TVar, expr: TypedExpr }>, fullExpr: TypedExpr): RustExpr {
		var expectedReturn = fullExpr.t;
		var tryBlock = compileExprToBlock(tryExpr, expectedReturn);
		var attempt = ECall(EPath("hxrt::exception::catch_unwind"), [EClosure([], tryBlock, false)]);

		var okName = "__hx_ok";
		var exName = "__hx_ex";

		var arms: Array<RustMatchArm> = [
			{ pat: PTupleStruct("Ok", [PBind(okName)]), expr: EPath(okName) },
			{ pat: PTupleStruct("Err", [PBind(exName)]), expr: compileCatchDispatch(exName, catches, expectedReturn) }
		];

			return EMatch(attempt, arms);
		}

		function localIdUsedInExpr(localId: Int, expr: TypedExpr): Bool {
			var used = false;
			function scan(e: TypedExpr): Void {
				if (used) return;
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

		function compileCatchDispatch(exVarName: String, catches: Array<{ v: TVar, expr: TypedExpr }>, expectedReturn: Type): RustExpr {
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
				return EBlock({ stmts: stmts, tail: body.tail });
			}

		var rustTy = toRustType(c.v.t, c.expr.pos);
		var downcast = ECall(ERaw(exVarName + ".downcast::<" + rustTypeToString(rustTy) + ">"), []);

			var okBody = compileExprToBlock(c.expr, expectedReturn);
			var okStmts = okBody.stmts.copy();
			var needsVar = localIdUsedInExpr(c.v.id, c.expr);
			var boxedPat: RustPattern = needsVar ? PBind("__hx_box") : PWildcard;
			if (needsVar) {
				var name = rustLocalDeclIdent(c.v);
				var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(c.v.id);
				okStmts.unshift(RLet(name, mutable, rustTy, EUnary("*", EPath("__hx_box"))));
			}
			var okExpr: RustExpr = EBlock({ stmts: okStmts, tail: okBody.tail });

			var errExpr = compileCatchDispatch(exVarName, rest, expectedReturn);

			return EMatch(downcast, [
				{ pat: PTupleStruct("Ok", [boxedPat]), expr: okExpr },
				{ pat: PTupleStruct("Err", [PBind(exVarName)]), expr: errExpr }
			]);
		}

	function compileGenericSwitch(switchExpr: TypedExpr, cases: Array<{ values: Array<TypedExpr>, expr: TypedExpr }>, edef: Null<TypedExpr>, expectedReturn: Type): RustExpr {
		var scrutinee = compileMatchScrutinee(switchExpr);
		var arms: Array<reflaxe.rust.ast.RustAST.RustMatchArm> = [];

		function enumParamKey(localId: Int, variant: String, index: Int): String {
			return localId + ":" + variant + ":" + index;
		}

		function withEnumParamBinds<T>(binds: Null<Map<String, String>>, fn: () -> T): T {
			var prev = currentEnumParamBinds;
			currentEnumParamBinds = binds;
			var out = fn();
			currentEnumParamBinds = prev;
			return out;
		}

		function enumParamBindsForCase(values: Array<TypedExpr>): Null<Map<String, String>> {
			var scrutLocalId: Null<Int> = null;
			switch (unwrapMetaParen(switchExpr).expr) {
				case TLocal(v):
					scrutLocalId = v.id;
				case _:
			}
			if (scrutLocalId == null) return null;
			if (values == null || values.length != 1) return null;

			var v0 = unwrapMetaParen(values[0]);
			return switch (v0.expr) {
				case TCall(callExpr, args): switch (unwrapMetaParen(callExpr).expr) {
					case TField(_, FEnum(enumRef, ef)): {
						var argc = args != null ? args.length : 0;
						if (argc == 0) return null;

						var m: Map<String, String> = [];
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

		for (c in cases) {
			var patterns: Array<reflaxe.rust.ast.RustAST.RustPattern> = [];
			for (v in c.values) {
				var p = compilePattern(v);
				if (p == null) {
					return unsupported(c.expr, "switch pattern");
				}
				patterns.push(p);
			}

			if (patterns.length == 0) continue;
			var pat = patterns.length == 1 ? patterns[0] : POr(patterns);
			var binds = enumParamBindsForCase(c.values);
			var armExpr = withEnumParamBinds(binds, () -> compileSwitchArmExpr(c.expr, expectedReturn));
			arms.push({ pat: pat, expr: armExpr });
		}

		arms.push({ pat: PWildcard, expr: edef != null ? compileSwitchArmExpr(edef, expectedReturn) : defaultSwitchArmExpr(expectedReturn) });
		return EMatch(scrutinee, arms);
	}

	function compileEnumIndexSwitch(enumExpr: TypedExpr, cases: Array<{ values: Array<TypedExpr>, expr: TypedExpr }>, edef: Null<TypedExpr>, expectedReturn: Type): RustExpr {
		var en = enumTypeFromType(enumExpr.t);
		if (en == null) return unsupported(enumExpr, "enum switch");

		var scrutinee = ECall(EField(compileExpr(enumExpr), "clone"), []);
		var arms: Array<reflaxe.rust.ast.RustAST.RustMatchArm> = [];
		var matchedVariants = new Map<String, Bool>();

		function enumParamKey(localId: Int, variant: String, index: Int): String {
			return localId + ":" + variant + ":" + index;
		}

		function withEnumParamBinds<T>(binds: Null<Map<String, String>>, fn: () -> T): T {
			var prev = currentEnumParamBinds;
			currentEnumParamBinds = binds;
			var out = fn();
			currentEnumParamBinds = prev;
			return out;
		}

		function enumParamBindsForSingleVariant(ef: EnumField): Null<Map<String, String>> {
			var scrutLocalId: Null<Int> = null;
			switch (unwrapMetaParen(enumExpr).expr) {
				case TLocal(v):
					scrutLocalId = v.id;
				case _:
			}
			if (scrutLocalId == null) return null;

			var argc = enumFieldArgCount(ef);
			if (argc == 0) return null;

			var m: Map<String, String> = [];
			for (i in 0...argc) {
				var bindName = argc == 1 ? "__p" : "__p" + i;
				m.set(enumParamKey(scrutLocalId, ef.name, i), bindName);
			}
			return m;
		}

		for (c in cases) {
			var patterns: Array<reflaxe.rust.ast.RustAST.RustPattern> = [];
			var singleEf: Null<EnumField> = null;
			for (v in c.values) {
				var idx = switchValueToInt(v);
				if (idx == null) return unsupported(v, "enum switch value");

				var ef = enumFieldByIndex(en, idx);
				if (ef == null) return unsupported(v, "enum switch index");

				if (c.values.length == 1) singleEf = ef;
				matchedVariants.set(ef.name, true);
				var pat = enumFieldToPattern(en, ef);
				patterns.push(pat);
			}

			if (patterns.length == 0) continue;
			var pat = patterns.length == 1 ? patterns[0] : POr(patterns);
			var binds = singleEf != null ? enumParamBindsForSingleVariant(singleEf) : null;
			var armExpr = withEnumParamBinds(binds, () -> compileSwitchArmExpr(c.expr, expectedReturn));
			arms.push({ pat: pat, expr: armExpr });
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

	function compileSwitchArmExpr(expr: TypedExpr, expectedReturn: Type): RustExpr {
		if (TypeHelper.isVoid(expectedReturn)) {
			return EBlock(compileVoidBody(expr));
		}

		return switch (expr.expr) {
			case TBlock(_):
				EBlock(compileFunctionBody(expr, expectedReturn));
			case _:
				compileExpr(expr);
		}
	}

	function defaultSwitchArmExpr(expectedReturn: Type): RustExpr {
		return if (TypeHelper.isVoid(expectedReturn)) {
			EBlock({ stmts: [], tail: null });
		} else {
			ERaw("todo!()");
		}
	}

	function compilePattern(value: TypedExpr): Null<reflaxe.rust.ast.RustAST.RustPattern> {
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
						var fields: Array<reflaxe.rust.ast.RustAST.RustPattern> = [];
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

	function compileMatchScrutinee(e: TypedExpr): RustExpr {
		var ft = followType(e.t);
		if (isStringType(ft)) {
			return ECall(EField(compileExpr(e), "as_str"), []);
		}
		if (isCopyType(ft)) {
			return compileExpr(e);
		}
		return ECall(EField(compileExpr(e), "clone"), []);
	}

	function unwrapMetaParen(e: TypedExpr): TypedExpr {
		return switch (e.expr) {
			case TParenthesis(e1): unwrapMetaParen(e1);
			case TMeta(_, e1): unwrapMetaParen(e1);
			case _: e;
		}
	}

	function isStringLiteralExpr(e: TypedExpr): Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TConst(TString(_)): true;
			case _: false;
		}
	}

	function isArrayLiteralExpr(e: TypedExpr): Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TArrayDecl(_): true;
			case _: false;
		}
	}

	function switchValueToInt(e: TypedExpr): Null<Int> {
		var v = unwrapMetaParen(e);
		return switch (v.expr) {
			case TConst(TInt(i)): i;
			case _: null;
		}
	}

	function enumKey(en: EnumType): String {
		return en.pack.join(".") + "." + en.name;
	}

	function isBuiltinEnum(en: EnumType): Bool {
		// Enums that are represented by Rust built-ins and should not be emitted as Rust enums.
		return switch (enumKey(en)) {
			case "haxe.ds.Option" | "haxe.functional.Result" | "rust.Option" | "rust.Result": true;
			case _: false;
		}
	}

		function rustEnumVariantPath(en: EnumType, variant: String): String {
			return switch (enumKey(en)) {
				case "haxe.ds.Option" | "rust.Option":
					"Option::" + variant;
				case "rust.Result":
					"Result::" + variant;
				// Map Haxe's `Result.Error` to Rust's `Result.Err`.
				case "haxe.functional.Result":
					"Result::" + (variant == "Error" ? "Err" : variant);
				case _:
					"crate::" + rustModuleNameForEnum(en) + "::" + en.name + "::" + variant;
			}
		}

	function enumTypeFromType(t: Type): Null<EnumType> {
		var ft = followType(t);
		return switch (ft) {
			case TEnum(enumRef, _): enumRef.get();
			case _: null;
		}
	}

	function enumFieldByIndex(en: EnumType, idx: Int): Null<EnumField> {
		for (name in en.constructs.keys()) {
			var ef = en.constructs.get(name);
			if (ef != null && ef.index == idx) return ef;
		}
		return null;
	}

	function enumFieldArgCount(ef: EnumField): Int {
		var ft = followType(ef.type);
		return switch (ft) {
			case TFun(args, _): args.length;
			case _: 0;
		}
	}

	function enumFieldToPattern(en: EnumType, ef: EnumField): reflaxe.rust.ast.RustAST.RustPattern {
		var n = enumFieldArgCount(ef);
		var path = rustEnumVariantPath(en, ef.name);
		if (n == 0) return PPath(path);
		if (n == 1) return PTupleStruct(path, [PBind("__p")]);
		var fields: Array<reflaxe.rust.ast.RustAST.RustPattern> = [];
		for (i in 0...n) fields.push(PBind("__p" + i));
		return PTupleStruct(path, fields);
	}

	function compileEnumIndex(e1: TypedExpr, pos: haxe.macro.Expr.Position): RustExpr {
		var en = enumTypeFromType(e1.t);
		if (en == null) {
			#if eval
			Context.error("TEnumIndex on non-enum type: " + Std.string(e1.t), pos);
			#end
			return ERaw("todo!()");
		}

		var scrutinee = ECall(EField(compileExpr(e1), "clone"), []);
		var arms: Array<reflaxe.rust.ast.RustAST.RustMatchArm> = [];

		for (name in en.constructs.keys()) {
			var ef = en.constructs.get(name);
			if (ef == null) continue;
			arms.push({
				pat: enumFieldToPattern(en, ef),
				expr: ELitInt(ef.index)
			});
		}

		arms.push({ pat: PWildcard, expr: EMacroCall("unreachable", []) });
		return EMatch(scrutinee, arms);
	}

	function compileEnumParameter(e1: TypedExpr, ef: EnumField, index: Int, valueType: Type, pos: haxe.macro.Expr.Position): RustExpr {
		switch (unwrapMetaParen(e1).expr) {
			case TLocal(v) if (currentEnumParamBinds != null): {
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
		var fields: Array<reflaxe.rust.ast.RustAST.RustPattern> = [];
		for (i in 0...argc) {
			fields.push(i == index ? PBind(bindName) : PWildcard);
		}

		var scrutinee = ECall(EField(compileExpr(e1), "clone"), []);
		var pat = PTupleStruct(rustEnumVariantPath(en, ef.name), fields);

		return EMatch(scrutinee, [
			{ pat: pat, expr: EPath(bindName) },
			{ pat: PWildcard, expr: EMacroCall("unreachable", []) }
		]);
	}

	function compileBranchExpr(e: TypedExpr): RustExpr {
		return switch (e.expr) {
			case TBlock(_):
				EBlock(compileFunctionBody(e));
			case _:
				compileExpr(e);
		}
	}

	function compileCall(callExpr: TypedExpr, args: Array<TypedExpr>, fullExpr: TypedExpr): RustExpr {
		// Special-case: super(...) in constructors.
		// POC: support `super()` as a no-op (base init semantics will be expanded later).
		switch (callExpr.expr) {
			case TConst(TSuper):
				if (args.length > 0) return unsupported(fullExpr, "super(args)");
				return EBlock({ stmts: [], tail: null });
			case _:
		}

		// Special-case: Std.*
		switch (callExpr.expr) {
			case TField(_, FStatic(clsRef, fieldRef)):
				var cls = clsRef.get();
				var field = fieldRef.get();
				if (cls.pack.length == 0 && cls.name == "Std") {
					switch (field.name) {
						case "isOfType": {
							if (args.length != 2) return unsupported(fullExpr, "Std.isOfType args");

							var valueExpr = args[0];
							var typeExpr = args[1];

							var expectedClass: Null<ClassType> = switch (typeExpr.expr) {
								case TTypeExpr(TClassDecl(cls2Ref)): cls2Ref.get();
								case _: null;
							};

							var actualClass: Null<ClassType> = switch (followType(valueExpr.t)) {
								case TInst(cls2Ref, _): cls2Ref.get();
								case _: null;
							};

							if (expectedClass != null && actualClass != null && isClassSubtype(actualClass, expectedClass)) {
								return ELitBool(true);
							}

							// If the value is represented as a trait object, we can do a simple RTTI id equality check.
							// This is partial (exact-type only), but useful for common `Std.isOfType(a, SubClass)` checks.
							if (isPolymorphicClassType(valueExpr.t)) {
								var actualId = ECall(EField(compileExpr(valueExpr), "__hx_type_id"), []);
								return EBinary("==", actualId, compileExpr(typeExpr));
							}

							return ELitBool(false);
						}

						case "string": {
							if (args.length != 1) return unsupported(fullExpr, "Std.string args");
							var value = args[0];
							var ft = followType(value.t);
							if (isStringType(ft)) {
								return ECall(EField(compileExpr(value), "clone"), []);
							} else if (isCopyType(ft)) {
								return ECall(EField(compileExpr(value), "to_string"), []);
							} else {
								return EMacroCall("format", [ELitString("{:?}"), compileExpr(value)]);
							}
						}

						case "parseFloat": {
							if (args.length != 1) return unsupported(fullExpr, "Std.parseFloat args");
							var s = args[0];
							var asStr = ECall(EField(compileExpr(s), "as_str"), []);
							return ECall(EPath("hxrt::string::parse_float"), [asStr]);
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
						case "getClassName": {
							if (args.length != 1) return unsupported(fullExpr, "Type.getClassName args");
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
							if (name == null) return unsupported(fullExpr, "Type.getClassName");
							return ECall(EPath("String::from"), [ELitString(name)]);
						}

						case "getEnumName": {
							if (args.length != 1) return unsupported(fullExpr, "Type.getEnumName args");
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
							if (name == null) return unsupported(fullExpr, "Type.getEnumName");
							return ECall(EPath("String::from"), [ELitString(name)]);
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
						case "field": {
							if (args.length != 2) return unsupported(fullExpr, "Reflect.field args");

							var obj = args[0];
							var nameExpr = args[1];
							var fieldName: Null<String> = switch (nameExpr.expr) {
								case TConst(TString(s)): s;
								case _: null;
							};
							if (fieldName == null) return unsupported(fullExpr, "Reflect.field non-const");

							var cf: Null<ClassField> = null;
							switch (followType(obj.t)) {
								case TInst(cls2Ref, _): {
									var cls2 = cls2Ref.get();
									for (f in cls2.fields.get()) {
										if (f.name == fieldName || f.getHaxeName() == fieldName) {
											cf = f;
											break;
										}
									}
								}
								case _:
							}
							if (cf == null) return unsupported(fullExpr, "Reflect.field (unsupported receiver/field)");

							var owner = switch (followType(obj.t)) {
								case TInst(cls2Ref, _): cls2Ref.get();
								case _: null;
							};
							if (owner == null) return unsupported(fullExpr, "Reflect.field owner");

							var value = compileInstanceFieldRead(obj, owner, cf, fullExpr);
							return ECall(EPath("hxrt::dynamic::from"), [value]);
						}

						case "setField": {
							if (args.length != 3) return unsupported(fullExpr, "Reflect.setField args");

							var obj = args[0];
							var nameExpr = args[1];
							var valueExpr = args[2];
							var fieldName: Null<String> = switch (nameExpr.expr) {
								case TConst(TString(s)): s;
								case _: null;
							};
							if (fieldName == null) return unsupported(fullExpr, "Reflect.setField non-const");

							var cf: Null<ClassField> = null;
							switch (followType(obj.t)) {
								case TInst(cls2Ref, _): {
									var cls2 = cls2Ref.get();
									for (f in cls2.fields.get()) {
										if (f.name == fieldName || f.getHaxeName() == fieldName) {
											cf = f;
											break;
										}
									}
								}
								case _:
							}
							if (cf == null) return unsupported(fullExpr, "Reflect.setField (unsupported receiver/field)");

							var owner = switch (followType(obj.t)) {
								case TInst(cls2Ref, _): cls2Ref.get();
								case _: null;
							};
							if (owner == null) return unsupported(fullExpr, "Reflect.setField owner");

							var assigned = compileInstanceFieldAssign(obj, owner, cf, valueExpr);
							return EBlock({ stmts: [RSemi(assigned)], tail: null });
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
							if (args.length != 1) return unsupported(fullExpr, "Bytes.alloc args");
							var size = ECast(compileExpr(args[0]), "usize");
							var inner = ECall(EPath("hxrt::bytes::Bytes::alloc"), [size]);
								return ECall(EPath("std::rc::Rc::new"), [ECall(EPath("std::cell::RefCell::new"), [inner])]);
						}
						case "ofString": {
							if (args.length != 1) return unsupported(fullExpr, "Bytes.ofString args");
							var s = args[0];
							var asStr = ECall(EField(compileExpr(s), "as_str"), []);
							var inner = ECall(EPath("hxrt::bytes::Bytes::of_string"), [asStr]);
								return ECall(EPath("std::rc::Rc::new"), [ECall(EPath("std::cell::RefCell::new"), [inner])]);
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
					var value = args.length > 0 ? compileExpr(args[0]) : ELitString("");
					return compileTrace(value, args.length > 0 ? args[0].t : fullExpr.t);
				}
			case _:
		}

		// Instance method call: obj.method(args...) => Class::method(&obj, args...)
		switch (callExpr.expr) {
			case TField(obj, FInstance(clsRef, _, cfRef)): {
				var owner = clsRef.get();
				var cf = cfRef.get();
				if (isBytesType(obj.t)) {
					switch (cf.getHaxeName()) {
						case "get": {
							if (args.length != 1) return unsupported(fullExpr, "Bytes.get args");
							var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
							return ECall(EField(borrowed, "get"), [compileExpr(args[0])]);
						}
						case "set": {
							if (args.length != 2) return unsupported(fullExpr, "Bytes.set args");
							var borrowed = ECall(EField(compileExpr(obj), "borrow_mut"), []);
							return ECall(EField(borrowed, "set"), [compileExpr(args[0]), compileExpr(args[1])]);
						}
						case "toString": {
							if (args.length != 0) return unsupported(fullExpr, "Bytes.toString args");
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
							var paramTypes: Null<Array<Type>> = switch (followType(cf.type)) {
								case TFun(params, _): [for (p in params) p.t];
								case _: null;
							};
							var callArgs: Array<RustExpr> = [];
							for (i in 0...args.length) {
								var arg = args[i];
								var compiled = compileExpr(arg);
								if (paramTypes != null && i < paramTypes.length) {
									compiled = coerceArgForParam(compiled, arg, paramTypes[i]);
								}
								callArgs.push(compiled);
							}
							return ECall(EField(recv, rustExternFieldName(cf)), callArgs);
						}

						// `this` inside concrete methods is always `&RefCell<Concrete>`; keep static dispatch.
						if (!isThisExpr(obj) && (isInterfaceType(obj.t) || isPolymorphicClassType(obj.t))) {
							// Interface/base-typed receiver: dynamic dispatch via trait method call.
							var recv = compileExpr(obj);
							var callArgs: Array<RustExpr> = [for (x in args) compileExpr(x)];
							return ECall(EField(recv, rustMethodName(owner, cf)), callArgs);
						}

						var clsName = classNameFromType(obj.t);
						var objCls: Null<ClassType> = switch (followType(obj.t)) {
							case TInst(objClsRef, _): objClsRef.get();
							case _: null;
						}
						if (clsName == null) return unsupported(fullExpr, "instance method call");
						var callArgs: Array<RustExpr> = [EUnary("&", compileExpr(obj))];
						for (x in args) callArgs.push(compileExpr(x));
						var rustName = rustMethodName(objCls != null ? objCls : owner, cf);
						return ECall(EPath(clsName + "::" + rustName), callArgs);
					}
					case _:
				}
			}
			case _:
		}

		var f = compileExpr(callExpr);
		var paramTypes: Null<Array<Type>> = switch (followType(callExpr.t)) {
			case TFun(params, _): [for (p in params) p.t];
			case _: null;
		};

		var a: Array<RustExpr> = [];
		for (i in 0...args.length) {
			var arg = args[i];
			var compiled = compileExpr(arg);

			if (paramTypes != null && i < paramTypes.length) {
				compiled = coerceArgForParam(compiled, arg, paramTypes[i]);
			}

			a.push(compiled);
		}
		return ECall(f, a);
	}

	function coerceArgForParam(compiled: RustExpr, argExpr: TypedExpr, paramType: Type): RustExpr {
		// Passing into `Dynamic` should not move the source value (Haxe values are reusable).
		if (isDynamicType(paramType) && !isDynamicType(argExpr.t)) {
			var needsClone = !isCopyType(argExpr.t);
			// Avoid cloning obvious temporaries (literals) that won't be re-used after the call.
			if (needsClone && isStringLiteralExpr(argExpr)) needsClone = false;
			if (needsClone && isArrayLiteralExpr(argExpr)) needsClone = false;
			if (needsClone) {
				compiled = ECall(EField(compiled, "clone"), []);
			}
			compiled = ECall(EPath("hxrt::dynamic::from"), [compiled]);
		} else if (isStringType(paramType)) {
			// Haxe Strings are immutable and commonly re-used after calls; avoid Rust moves by cloning.
			if (!isStringLiteralExpr(argExpr)) {
				compiled = ECall(EField(compiled, "clone"), []);
			}
		}

		// Function values: coerce function items/paths into our function representation.
		// Baseline representation is `std::rc::Rc<dyn Fn(...) -> ...>`.
		switch (followType(paramType)) {
			case TFun(params, ret): {
				function isRcNew(e: RustExpr): Bool {
					return switch (e) {
						case ECall(EPath("std::rc::Rc::new"), _): true;
						case _: false;
					}
				}

				if (!isRcNew(compiled)) {
					var argParts: Array<String> = [];
					var callArgs: Array<RustExpr> = [];
					for (i in 0...params.length) {
						var p = params[i];
						var name = "a" + i;
						argParts.push(name + ": " + rustTypeToString(toRustType(p.t, argExpr.pos)));
						callArgs.push(EPath(name));
					}

					var callExpr = ECall(compiled, callArgs);
					var retTy = toRustType(ret, argExpr.pos);
					var body: RustBlock = {
						stmts: [],
						tail: TypeHelper.isVoid(ret) ? null : callExpr
					};
					if (TypeHelper.isVoid(ret)) {
						body.stmts.push(RSemi(callExpr));
					}

					compiled = ECall(EPath("std::rc::Rc::new"), [EClosure(argParts, body, true)]);
				}
			}
			case _:
		}

		var rustParamTy = toRustType(paramType, argExpr.pos);
		return wrapBorrowIfNeeded(compiled, rustParamTy, argExpr);
	}

	function wrapBorrowIfNeeded(expr: RustExpr, ty: RustType, valueExpr: TypedExpr): RustExpr {
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

	function rustRefKind(t: Type): Null<String> {
		return switch (followType(t)) {
			case TAbstract(absRef, _): {
				var abs = absRef.get();
				var key = abs.pack.join(".") + "." + abs.name;
				if (key == "rust.Ref") "ref"
				else if (key == "rust.MutRef") "mutref"
				else if (key == "rust.Str") "str"
				else if (key == "rust.Slice") "slice"
				else null;
			}
			case _:
				null;
		}
	}

	function isDirectRustRefValue(e: TypedExpr): Bool {
		// If we see a cast at the top-level, assume it's an implicit conversion to `Ref/MutRef`
		// and still emit the borrow operator.
		var cur = unwrapMetaParen(e);
		switch (cur.expr) {
			case TCast(_, _):
				return false;
			case _:
		}

		// `Ref<T>` / `MutRef<T>` locals and fields compile to `&T` / `&mut T` already.
		return rustRefKind(cur.t) != null;
	}

	function isClassSubtype(actual: ClassType, expected: ClassType): Bool {
		if (classKey(actual) == classKey(expected)) return true;
		var cur = actual.superClass != null ? actual.superClass.t.get() : null;
		while (cur != null) {
			if (classKey(cur) == classKey(expected)) return true;
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}
		return false;
	}

			function compileTrace(valueExpr: RustExpr, valueType: Type): RustExpr {
				// Use `{}` for common primitives/strings; fall back to `{:?}`.
				var t = followType(valueType);
				var fmt = if (isStringType(t) || TypeHelper.isInt(t) || TypeHelper.isFloat(t) || TypeHelper.isBool(t)) {
					"{}";
				} else {
					"{:?}";
				}
				return EMacroCall("println", [ELitString(fmt), valueExpr]);
			}

		function exprUsesThis(e: TypedExpr): Bool {
			var used = false;
			function scan(x: TypedExpr): Void {
				if (used) return;
				switch (unwrapMetaParen(x).expr) {
					case TConst(TThis):
						used = true;
						return;
					case _:
				}
				TypedExprTools.iter(x, scan);
			}
			scan(e);
			return used;
		}

		function isThisExpr(e: TypedExpr): Bool {
			return switch (e.expr) {
				case TConst(TThis): true;
				case _: false;
			}
		}

	function compileField(obj: TypedExpr, fa: FieldAccess, fullExpr: TypedExpr): RustExpr {
		return switch (fa) {
			case FStatic(clsRef, cfRef): {
				var cls = clsRef.get();
				var cf = cfRef.get();
				var key = cls.pack.join(".") + "." + cls.name;

				// Extern static access maps to a Rust path, optionally overridden via `@:native(...)`.
				if (cls.isExtern) {
					var base = rustExternBasePath(cls);
					return EPath((base != null ? base : cls.name) + "::" + rustExternFieldName(cf));
				}

				if (mainClassKey != null && currentClassKey != null && key == currentClassKey && key == mainClassKey) {
					EPath(rustMethodName(cls, cf));
				} else {
					var modName = rustModuleNameForClass(cls);
					EPath("crate::" + modName + "::" + cls.name + "::" + rustMethodName(cls, cf));
				}
			}
			case FEnum(enumRef, efRef): {
				var en = enumRef.get();
				var ef = efRef;
				EPath(rustEnumVariantPath(en, ef.name));
			}
			case FInstance(clsRef, _, cfRef): {
				var owner = clsRef.get();
				var cf = cfRef.get();

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

				switch (cf.kind) {
					case FMethod(_):
						unsupported(fullExpr, "method value");
					case _:
						compileInstanceFieldRead(obj, owner, cf, fullExpr);
				}
			}
			case FAnon(cfRef): {
				var cf = cfRef.get();
				EField(compileExpr(obj), cf.getHaxeName());
			}
			case FDynamic(name): EField(compileExpr(obj), name);
			case _: unsupported(fullExpr, "field");
		}
	}

	function compileInstanceFieldRead(obj: TypedExpr, owner: ClassType, cf: ClassField, fullExpr: TypedExpr): RustExpr {
		if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
			return ECall(EField(compileExpr(obj), rustGetterName(owner, cf)), []);
		}

		var recv = compileExpr(obj);
		var borrowed = ECall(EField(recv, "borrow"), []);
		var access = EField(borrowed, rustFieldName(owner, cf));

		// For non-Copy types, cloning is the simplest POC rule.
		if (!TypeHelper.isBool(fullExpr.t) && !TypeHelper.isInt(fullExpr.t) && !TypeHelper.isFloat(fullExpr.t)) {
			return ECall(EField(access, "clone"), []);
		}

		return access;
	}

	function compileInstanceFieldAssign(obj: TypedExpr, owner: ClassType, cf: ClassField, rhs: TypedExpr): RustExpr {
		if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
			// Haxe assignment returns the RHS value.
			// `{ let __tmp = rhs; obj.__hx_set_field(__tmp.clone()); __tmp }`
			var stmts: Array<RustStmt> = [];
			stmts.push(RLet("__tmp", false, null, compileExpr(rhs)));

			var rhsVal: RustExpr = isCopyType(cf.type) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
			stmts.push(RSemi(ECall(EField(compileExpr(obj), rustSetterName(owner, cf)), [rhsVal])));

			return EBlock({ stmts: stmts, tail: EPath("__tmp") });
		}

		// Important: evaluate RHS before taking a mutable borrow to avoid RefCell borrow panics.
		// `{ let __tmp = rhs; obj.borrow_mut().field = __tmp.clone(); __tmp }`
		var stmts: Array<RustStmt> = [];

		stmts.push(RLet("__tmp", false, null, compileExpr(rhs)));

		var recv = compileExpr(obj);
		var borrowed = ECall(EField(recv, "borrow_mut"), []);
		var access = EField(borrowed, rustFieldName(owner, cf));
		var rhsClone = ECall(EField(EPath("__tmp"), "clone"), []);
		stmts.push(RSemi(EAssign(access, rhsClone)));

		return EBlock({
			stmts: stmts,
			tail: EPath("__tmp")
		});
	}

	function compileArrayIndexAssign(arr: TypedExpr, index: TypedExpr, rhs: TypedExpr): RustExpr {
		// Haxe assignment returns the RHS value.
		// `{ let __tmp = rhs; arr[idx] = __tmp.clone(); __tmp }`
		var stmts: Array<RustStmt> = [];
		stmts.push(RLet("__tmp", false, null, compileExpr(rhs)));

		var idx = ECast(compileExpr(index), "usize");
		var lhs = EIndex(compileExpr(arr), idx);
		var rhsClone = ECall(EField(EPath("__tmp"), "clone"), []);
		stmts.push(RSemi(EAssign(lhs, rhsClone)));

		return EBlock({ stmts: stmts, tail: EPath("__tmp") });
	}

		function classNameFromType(t: Type): Null<String> {
			var ft = TypeTools.follow(t);
			return switch (ft) {
				case TInst(clsRef, _): {
					var cls = clsRef.get();
					if (cls == null) null else if (isMainClass(cls)) cls.name else ("crate::" + rustModuleNameForClass(cls) + "::" + cls.name);
				}
				case _: null;
			}
		}

	function isExternInstanceType(t: Type): Bool {
		return switch (followType(t)) {
			case TInst(clsRef, _): clsRef.get().isExtern;
			case _: false;
		}
	}

	function rustExternBasePath(cls: ClassType): Null<String> {
		for (entry in cls.meta.get()) {
			if (entry.name != ":native") continue;
			if (entry.params == null || entry.params.length == 0) continue;
			try {
				var v: Dynamic = ExprTools.getValue(entry.params[0]);
				if (Std.isOfType(v, String)) return cast v;
			} catch (_: Dynamic) {}
		}
		return null;
	}

	function rustExternFieldName(cf: ClassField): String {
		for (entry in cf.meta.get()) {
			if (entry.name != ":native") continue;
			if (entry.params == null || entry.params.length == 0) continue;
			try {
				var v: Dynamic = ExprTools.getValue(entry.params[0]);
				if (Std.isOfType(v, String)) return cast v;
			} catch (_: Dynamic) {}
		}
		// For extern fields, Haxe may rewrite the field name and store the original name in `:realPath`.
		// Use the actual (post-metadata) identifier by default.
		return cf.name;
	}

	function rustDerivesFromMeta(meta: haxe.macro.Type.MetaAccess): Array<String> {
		var derives: Array<String> = [];

		for (entry in meta.get()) {
			if (entry.name != ":rustDerive") continue;

			if (entry.params == null || entry.params.length == 0) {
				#if eval
				Context.error("`@:rustDerive` requires a single parameter.", entry.pos);
				#end
				continue;
			}

			switch (entry.params[0].expr) {
				case EConst(CString(s, _)):
					derives.push(s);
				case EArrayDecl(values): {
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

	function mergeUniqueStrings(base: Array<String>, extra: Array<String>): Array<String> {
		var seen = new Map<String, Bool>();
		var out: Array<String> = [];

		for (s in base) {
			if (seen.exists(s)) continue;
			seen.set(s, true);
			out.push(s);
		}

		for (s in extra) {
			if (seen.exists(s)) continue;
			seen.set(s, true);
			out.push(s);
		}

		return out;
	}

	function isInterfaceType(t: Type): Bool {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, _): clsRef.get().isInterface;
			case _: false;
		}
	}

	function isPolymorphicClassType(t: Type): Bool {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, _): {
				var cls = clsRef.get();
				!cls.isInterface && classHasSubclasses(cls);
			}
			case _: false;
		}
	}

	function ensureSubclassIndex() {
		if (classHasSubclass != null) return;
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

	function classHasSubclasses(cls: ClassType): Bool {
		ensureSubclassIndex();
		return classHasSubclass != null && classHasSubclass.exists(classKey(cls));
	}

	function emitClassTrait(classType: ClassType, funcFields: Array<ClassFuncData>): String {
		var traitName = classType.name + "Trait";
		var lines: Array<String> = [];
		lines.push("pub trait " + traitName + ": std::fmt::Debug {");

		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			var ty = rustTypeToString(toRustType(cf.type, cf.pos));
			lines.push("\tfn " + rustGetterName(classType, cf) + "(&self) -> " + ty + ";");
			lines.push("\tfn " + rustSetterName(classType, cf) + "(&self, v: " + ty + ");");
		}

			for (f in funcFields) {
				if (f.isStatic) continue;
				if (f.field.getHaxeName() == "new") continue;
				if (f.expr == null) continue;

				var sigArgs: Array<String> = ["&self"];
				var usedArgNames: Map<String, Bool> = [];
				for (a in f.args) {
					var baseName = a.getName();
					if (baseName == null || baseName.length == 0) baseName = "a";
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

		function emitClassTraitImplForSelf(classType: ClassType, funcFields: Array<ClassFuncData>): String {
			var modName = rustModuleNameForClass(classType);
			var traitPath = "crate::" + modName + "::" + classType.name + "Trait";

			var lines: Array<String> = [];
			lines.push("impl " + traitPath + " for std::cell::RefCell<" + classType.name + "> {");

		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			var ty = rustTypeToString(toRustType(cf.type, cf.pos));

			lines.push("\tfn " + rustGetterName(classType, cf) + "(&self) -> " + ty + " {");
			if (isCopyType(cf.type)) {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf));
			} else {
				lines.push("\t\tself.borrow()." + rustFieldName(classType, cf) + ".clone()");
			}
			lines.push("\t}");

			lines.push("\tfn " + rustSetterName(classType, cf) + "(&self, v: " + ty + ") {");
			lines.push("\t\tself.borrow_mut()." + rustFieldName(classType, cf) + " = v;");
			lines.push("\t}");
		}

			for (f in funcFields) {
				if (f.isStatic) continue;
				if (f.field.getHaxeName() == "new") continue;
				if (f.expr == null) continue;

				var sigArgs: Array<String> = ["&self"];
				var callArgs: Array<String> = ["self"];
				var usedArgNames: Map<String, Bool> = [];
				for (a in f.args) {
					var baseName = a.getName();
					if (baseName == null || baseName.length == 0) baseName = "a";
					var argName = RustNaming.stableUnique(RustNaming.snakeIdent(baseName), usedArgNames);
					sigArgs.push(argName + ": " + rustTypeToString(toRustType(a.type, f.field.pos)));
					callArgs.push(argName);
				}
				var ret = rustTypeToString(toRustType(f.ret, f.field.pos));
				var rustName = rustMethodName(classType, f.field);
				lines.push("\tfn " + rustName + "(" + sigArgs.join(", ") + ") -> " + ret + " {");
				lines.push("\t\t" + classType.name + "::" + rustName + "(" + callArgs.join(", ") + ")");
			lines.push("\t}");
		}

		lines.push("\tfn __hx_type_id(&self) -> u32 {");
		lines.push("\t\tcrate::" + modName + "::__HX_TYPE_ID");
		lines.push("\t}");

		lines.push("}");
		return lines.join("\n");
	}

		function emitBaseTraitImplForSubclass(baseType: ClassType, subType: ClassType, subFuncFields: Array<ClassFuncData>): String {
			var baseMod = rustModuleNameForClass(baseType);
			var baseTraitPath = "crate::" + baseMod + "::" + baseType.name + "Trait";

		var overrides = new Map<String, ClassFuncData>();
		for (f in subFuncFields) {
			if (f.isStatic) continue;
			if (f.field.getHaxeName() == "new") continue;
			if (f.expr == null) continue;
			overrides.set(f.field.getHaxeName() + "/" + f.args.length, f);
		}

			var lines: Array<String> = [];
			lines.push("impl " + baseTraitPath + " for std::cell::RefCell<" + subType.name + "> {");

		for (cf in getAllInstanceVarFieldsForStruct(baseType)) {
			var ty = rustTypeToString(toRustType(cf.type, cf.pos));

			lines.push("\tfn " + rustGetterName(baseType, cf) + "(&self) -> " + ty + " {");
			if (isCopyType(cf.type)) {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf));
			} else {
				lines.push("\t\tself.borrow()." + rustFieldName(subType, cf) + ".clone()");
			}
			lines.push("\t}");

			lines.push("\tfn " + rustSetterName(baseType, cf) + "(&self, v: " + ty + ") {");
			lines.push("\t\tself.borrow_mut()." + rustFieldName(subType, cf) + " = v;");
			lines.push("\t}");
		}

		for (cf in baseType.fields.get()) {
			if (cf.getHaxeName() == "new") continue;
			switch (cf.kind) {
				case FMethod(_): {
					var ft = followType(cf.type);
					var args = switch (ft) {
						case TFun(a, _): a;
						case _: [];
					}

						var sigArgs: Array<String> = ["&self"];
						var callArgs: Array<String> = ["self"];
						var usedArgNames: Map<String, Bool> = [];
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
						lines.push("\t\t" + subType.name + "::" + rustMethodName(subType, overrideFunc.field) + "(" + callArgs.join(", ") + ")");
					} else {
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

	function typeIdLiteralForClass(cls: ClassType): String {
		var id = fnv1a32(classKey(cls));
		var hex = StringTools.hex(id, 8).toLowerCase();
		return "0x" + hex + "u32";
	}

	function fnv1a32(s: String): Int {
		var hash = 0x811C9DC5;
		for (i in 0...s.length) {
			hash = hash ^ s.charCodeAt(i);
			hash = hash * 0x01000193;
		}
		return hash;
	}

	function getAllInstanceVarFieldsForStruct(classType: ClassType): Array<ClassField> {
		var out: Array<ClassField> = [];
		var seen = new Map<String, Bool>();

		// Walk base -> derived so field layout is deterministic.
		var chain: Array<ClassType> = [];
		var cur: Null<ClassType> = classType;
		while (cur != null) {
			chain.unshift(cur);
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}

		for (cls in chain) {
			for (cf in cls.fields.get()) {
				switch (cf.kind) {
					case FVar(_, _): {
						var name = cf.getHaxeName();
						if (seen.exists(name)) continue;
						seen.set(name, true);
						out.push(cf);
					}
					case _:
				}
			}
		}

		return out;
	}

	function compileBinop(op: Binop, e1: TypedExpr, e2: TypedExpr, fullExpr: TypedExpr): RustExpr {
		return switch (op) {
			case OpAssign:
				switch (e1.expr) {
					case TArray(arr, index): {
						compileArrayIndexAssign(arr, index, e2);
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
						EAssign(compileExpr(e1), compileExpr(e2));
				}

			case OpAdd:
				var ft = followType(fullExpr.t);
				if (isStringType(ft) || isStringType(followType(e1.t)) || isStringType(followType(e2.t))) {
					// POC: string concatenation via `format!`.
					EMacroCall("format", [ELitString("{}{}"), compileExpr(e1), compileExpr(e2)]);
				} else {
					EBinary("+", compileExpr(e1), compileExpr(e2));
				}

			case OpSub: EBinary("-", compileExpr(e1), compileExpr(e2));
			case OpMult: EBinary("*", compileExpr(e1), compileExpr(e2));
			case OpDiv: EBinary("/", compileExpr(e1), compileExpr(e2));

			case OpEq: EBinary("==", compileExpr(e1), compileExpr(e2));
			case OpNotEq: EBinary("!=", compileExpr(e1), compileExpr(e2));
			case OpLt: EBinary("<", compileExpr(e1), compileExpr(e2));
			case OpLte: EBinary("<=", compileExpr(e1), compileExpr(e2));
			case OpGt: EBinary(">", compileExpr(e1), compileExpr(e2));
			case OpGte: EBinary(">=", compileExpr(e1), compileExpr(e2));
			case OpBoolAnd: EBinary("&&", compileExpr(e1), compileExpr(e2));
			case OpBoolOr: EBinary("||", compileExpr(e1), compileExpr(e2));

			case OpInterval:
				ERange(compileExpr(e1), compileExpr(e2));

			default:
				unsupported(fullExpr, "binop" + Std.string(op));
		}
	}

	function compileUnop(op: Unop, postFix: Bool, expr: TypedExpr, fullExpr: TypedExpr): RustExpr {
		if (op == OpIncrement || op == OpDecrement) {
			// POC: support ++/-- for locals (needed for Haxe's for-loop lowering).
				return switch (expr.expr) {
					case TLocal(v): {
						var name = rustLocalRefIdent(v);
						var delta: RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
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
								stmts: [
									RSemi(EAssign(EPath(name), EBinary(binop, EPath(name), delta)))
								],
								tail: EPath(name)
							});
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
			default: unsupported(fullExpr, "unop" + Std.string(op));
		}
	}

	function followType(t: Type): Type {
		#if eval
		return Context.followWithAbstracts(TypeTools.follow(t));
		#else
		return TypeTools.follow(t);
		#end
	}

	function isStringType(t: Type): Bool {
		var ft = followType(t);
		if (TypeHelper.isString(ft)) return true;
		return switch (ft) {
			case TInst(clsRef, []): {
				var cls = clsRef.get();
				var isNameString = cls.meta.has(":native") || cls.name == "String";
				isNameString && cls.module == "String" && cls.pack.length == 0;
			}
			case TAbstract(absRef, []): {
				var abs = absRef.get();
				abs.module == "StdTypes" && abs.name == "String";
			}
			case _: false;
		}
	}

	function unsupported(e: TypedExpr, what: String): RustExpr {
		#if eval
		Context.error('Unsupported $what for Rust POC: ' + Std.string(e.expr), e.pos);
		#end
		return ERaw("todo!()");
	}

	function toRustType(t: Type, pos: haxe.macro.Expr.Position): reflaxe.rust.ast.RustAST.RustType {
		var ft = TypeTools.follow(t);
		if (TypeHelper.isVoid(t)) return RUnit;
		if (TypeHelper.isBool(t)) return RBool;
		if (TypeHelper.isInt(t)) return RI32;
		if (TypeHelper.isFloat(t)) return RF64;
		if (isStringType(ft)) return RString;

		switch (ft) {
			case TDynamic(_):
				return RPath("hxrt::dynamic::Dynamic");
			case _:
		}

		switch (ft) {
			case TFun(params, ret): {
				var argTys = [for (p in params) rustTypeToString(toRustType(p.t, pos))];
				var retTy = toRustType(ret, pos);
				var sig = "dyn Fn(" + argTys.join(", ") + ")";
				if (!TypeHelper.isVoid(ret)) {
					sig += " -> " + rustTypeToString(retTy);
				}
				return RPath("std::rc::Rc<" + sig + ">");
			}
			case _:
		}

		switch (ft) {
			case TAbstract(absRef, params): {
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

				// General abstract fallback: treat as its underlying type.
				// (Most Haxe abstracts are compile-time-only; runtime representation is the backing type.)
				var underlying: Type = abs.type;
				if (abs.params != null && abs.params.length > 0 && params != null && params.length == abs.params.length) {
					underlying = TypeTools.applyTypeParameters(underlying, abs.params, params);
				}
				return toRustType(underlying, pos);
			}
			case _:
		}

		if (isArrayType(ft)) {
			var elem = arrayElementType(ft);
			var elemRust = toRustType(elem, pos);
			return RPath("Vec<" + rustTypeToString(elemRust) + ">");
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
					var errT = params.length >= 2 ? toRustType(params[1], pos) : RString;
					RPath("Result<" + rustTypeToString(okT) + ", " + rustTypeToString(errT) + ">");
					} else {
						var modName = rustModuleNameForEnum(en);
						RPath("crate::" + modName + "::" + en.name);
					}
				}
				case TInst(clsRef, params): {
					var cls = clsRef.get();
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
				if (cls.isInterface) {
					var modName = rustModuleNameForClass(cls);
					RPath("std::rc::Rc<dyn crate::" + modName + "::" + cls.name + ">");
					} else if (classHasSubclasses(cls)) {
						var modName = rustModuleNameForClass(cls);
						RPath("std::rc::Rc<dyn crate::" + modName + "::" + cls.name + "Trait>");
					} else {
						var modName = rustModuleNameForClass(cls);
						RPath("crate::HxRef<crate::" + modName + "::" + cls.name + ">");
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

	function isCopyType(t: Type): Bool {
		var ft = followType(t);
		return TypeHelper.isBool(ft) || TypeHelper.isInt(ft) || TypeHelper.isFloat(ft);
	}

	function isDynamicType(t: Type): Bool {
		return switch (followType(t)) {
			case TDynamic(_): true;
			case _: false;
		}
	}

	function isBytesClass(cls: ClassType): Bool {
		return cls.pack.join(".") == "haxe.io" && cls.name == "Bytes";
	}

	function isBytesType(t: Type): Bool {
		return switch (followType(t)) {
			case TInst(clsRef, _): isBytesClass(clsRef.get());
			case _: false;
		}
	}

	function isArrayType(t: Type): Bool {
		var ft = followType(t);
		return switch (ft) {
			case TInst(clsRef, _): {
				var cls = clsRef.get();
				cls.pack.length == 0 && cls.module == "Array" && cls.name == "Array";
			}
			case _: false;
		}
	}

	function isRustVecType(t: Type): Bool {
		return switch (followType(t)) {
			case TInst(clsRef, params): {
				var cls = clsRef.get();
				cls != null
					&& cls.isExtern
					&& cls.name == "Vec"
					&& (cls.pack.join(".") == "rust" || cls.module == "rust.Vec")
					&& params.length == 1;
			}
			case _:
				false;
		}
	}

	function isRustSliceType(t: Type): Bool {
		return switch (followType(t)) {
			case TAbstract(absRef, params): {
				var abs = absRef.get();
				abs != null
					&& abs.name == "Slice"
					&& (abs.pack.join(".") == "rust" || abs.module == "rust.Slice")
					&& params.length == 1;
			}
			case _:
				false;
		}
	}

	function isRustHashMapType(t: Type): Bool {
		return switch (followType(t)) {
			case TInst(clsRef, params): {
				var cls = clsRef.get();
				var externPath = cls != null ? rustExternBasePath(cls) : null;
				var isRealRustHashMap = false;
				if (cls != null) {
					for (m in cls.meta.get()) {
						if (m.name != ":realPath" && m.name != "realPath") continue;
						if (m.params == null || m.params.length != 1) continue;
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
					&& (isRealRustHashMap || cls.pack.join(".") == "rust" || cls.module == "rust.HashMap" || externPath == "std::collections::HashMap")
					&& params.length == 2;
			}
			case _:
				false;
		}
	}

	function isRustIterType(t: Type): Bool {
		return switch (followType(t)) {
			case TInst(clsRef, params): {
				var cls = clsRef.get();
				var isRealRustIter = false;
				if (cls != null) {
					for (m in cls.meta.get()) {
						if (m.name != ":realPath" && m.name != "realPath") continue;
						if (m.params == null || m.params.length != 1) continue;
						switch (m.params[0].expr) {
							case EConst(CString(s, _)):
								if (s == "rust.Iter") isRealRustIter = true;
							case _:
						}
					}
				}

				cls != null
					&& cls.isExtern
					&& isRealRustIter
					&& params.length == 1;
			}
			case _:
				false;
		}
	}

	function arrayElementType(t: Type): Type {
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

	function iterBorrowMethod(t: Type): String {
		var elem: Null<Type> = null;
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

	function rustTypeToString(t: reflaxe.rust.ast.RustAST.RustType): String {
		return switch (t) {
			case RUnit: "()";
			case RBool: "bool";
			case RI32: "i32";
			case RF64: "f64";
			case RString: "String";
			case RRef(inner, mutable): "&" + (mutable ? "mut " : "") + rustTypeToString(inner);
			case RPath(path): path;
		}
	}
}

#end
