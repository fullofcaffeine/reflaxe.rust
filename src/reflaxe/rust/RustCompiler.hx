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

private typedef RustImplSpec = {
	var traitPath: String;
	@:optional var forType: String;
	@:optional var body: String;
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
	var didEmitMain: Bool = false;
	var crateName: String = "hx_app";
	var mainBaseType: Null<BaseType> = null;
	var mainClassKey: Null<String> = null;
	var currentClassKey: Null<String> = null;
	var currentClassName: Null<String> = null;
	var currentClassType: Null<ClassType> = null;
	// When compiling an inherited method shim (base method body on a subclass), `this` dispatch should
	// use `currentClassType`, but `super` resolution should use the class that defined the body.
	var currentMethodOwnerType: Null<ClassType> = null;
	// The method currently being compiled (used for property accessor special-casing, e.g. `default,set` setters).
	var currentMethodField: Null<ClassField> = null;
	// Per-class compilation state: when a method body uses `super`, we synthesize a "super thunk"
	// method on the current class so `super.method(...)` can call the base implementation with a
	// `&RefCell<Current>` receiver.
	var currentNeededSuperThunks: Null<Map<String, { owner: ClassType, field: ClassField }>> = null;
	var extraRustSrcDir: Null<String> = null;
	var extraRustSrcFiles: Array<{ module: String, fileName: String, fullPath: String }> = [];
	var classHasSubclass: Null<Map<String, Bool>> = null;
		var frameworkStdDir: Null<String> = null;
		var frameworkRuntimeDir: Null<String> = null;
		var profile: RustProfile = Portable;
		// When inlining constructor `super(...)` bodies, we need to substitute base-ctor parameter locals.
		// Map is keyed by Haxe local name and returns a Rust expression to use in place of that local.
		var inlineLocalSubstitutions: Null<Map<String, RustExpr>> = null;
		var currentMutatedLocals: Null<Map<Int, Bool>> = null;
		var currentLocalReadCounts: Null<Map<Int, Int>> = null;
		var currentArgNames: Null<Map<String, String>> = null;
		var currentLocalNames: Null<Map<Int, String>> = null;
		var currentLocalUsed: Null<Map<String, Bool>> = null;
	var currentEnumParamBinds: Null<Map<String, String>> = null;
	var currentFunctionReturn: Null<Type> = null;
	var rustNamesByClass: Map<String, { fields: Map<String, String>, methods: Map<String, String> }> = [];
	var inCodeInjectionArg: Bool = false;

	inline function wantsPreludeAliases(): Bool {
		return profile == Idiomatic || profile == Rusty;
	}

	inline function rcBasePath(): String {
		return wantsPreludeAliases() ? "crate::HxRc" : "std::rc::Rc";
	}

	inline function refCellBasePath(): String {
		return wantsPreludeAliases() ? "crate::HxRefCell" : "std::cell::RefCell";
	}

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
		var inheritedInstanceMethods: Array<{ owner: ClassType, f: ClassFuncData }> = collectInheritedInstanceMethodShims(classType, funcFields);
		var effectiveFuncFields: Array<ClassFuncData> = funcFields.concat([for (x in inheritedInstanceMethods) x.f]);
		var inheritedOwnerById: Map<String, ClassType> = [];
		for (x in inheritedInstanceMethods) inheritedOwnerById.set(x.f.id, x.owner);

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

				var preludeLines: Array<String> = wantsPreludeAliases()
					? [
						"type HxRc<T> = std::rc::Rc<T>;",
						"type HxRefCell<T> = std::cell::RefCell<T>;",
						"type HxRef<T> = HxRc<HxRefCell<T>>;"
					]
					: ["type HxRef<T> = std::rc::Rc<std::cell::RefCell<T>>;"];

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
				if (headerLines.length > 0) items.push(RRaw(headerLines.join("\n")));
			} else if (classType.isInterface) {
			// Interfaces compile to Rust traits (no struct allocation).
			items.push(RRaw("// Haxe interface -> Rust trait"));

			var traitLines: Array<String> = [];
			var traitGenerics = classGenericDecls;
			var traitGenericSuffix = traitGenerics.length > 0 ? "<" + traitGenerics.join(", ") + ">" : "";
			traitLines.push("pub trait " + rustSelfType + traitGenericSuffix + " {");
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

				var ret = rustTypeToString(rustReturnTypeForField(f.field, f.ret, f.field.pos));
				var sig = "\tfn " + rustMethodName(classType, f.field) + "(" + args.join(", ") + ") -> " + ret + ";";
				traitLines.push(sig);
			}
			traitLines.push("}");
			items.push(RRaw(traitLines.join("\n")));
			} else {
				// If this class has a base class, bring base traits into scope. This matters when we inline
				// constructor `super(...)` bodies: base-typed method calls can compile to trait methods that
				// need the trait to be in scope for method-call syntax on concrete receivers.
				function baseCtorCallsThisMethods(base: ClassType): Bool {
					if (base == null) return false;
					if (base.constructor == null) return false;
					var ctorField = base.constructor.get();
					if (ctorField == null) return false;
					var ex = ctorField.expr();
					if (ex == null) return false;
					var body = switch (ex.expr) {
						case TFunction(fn): fn.expr;
						case _: ex;
					};

					var found = false;
					function scan(e: TypedExpr): Void {
						if (found) return;
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

				var seenBaseUses: Map<String, Bool> = [];
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
			if (classNeedsPhantomForUnusedTypeParams(classType)) {
				var decls = rustGenericDeclsForClass(classType);
				var names = rustGenericNamesFromDecls(decls);
				var phantomTy = names.length == 1
					? ("std::marker::PhantomData<" + names[0] + ">")
					: ("std::marker::PhantomData<(" + names.join(", ") + ")>");
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

			var implFunctions: Array<reflaxe.rust.ast.RustAST.RustFunction> = [];

			// Constructor (`new`)
			var ctor = findConstructor(funcFields);
			if (ctor != null) {
				implFunctions.push(compileConstructor(classType, varFields, ctor));
			}

			// Instance methods
			for (f in effectiveFuncFields) {
				if (f.isStatic) continue;
				if (f.field.getHaxeName() == "new") continue;
				if (f.expr == null) continue;
				// Inherited shims need `super` resolution based on the class that defined the body.
				var owner = inheritedOwnerById.exists(f.id) ? inheritedOwnerById.get(f.id) : classType;
				implFunctions.push(compileInstanceMethod(classType, f, owner));
			}

			// Static methods (associated functions on the type).
			for (f in effectiveFuncFields) {
				if (!f.isStatic) continue;
				if (f.expr == null) continue;
				if (f.field.getHaxeName() == "main") continue;
				implFunctions.push(compileStaticMethod(classType, f));
			}

			// Emit any needed "super thunks" (discovered while compiling instance method bodies).
			//
			// A super thunk is a method on `classType` that contains the base method body, but is typed
			// as `fn(&RefCell<classType>, ...)`, so `super.method(...)` can call the base implementation
			// without attempting to pass `&RefCell<Sub>` to `Base::method(&RefCell<Base>)`.
			if (currentNeededSuperThunks != null) {
				var emitted: Map<String, Bool> = [];
				var progress = true;
				while (progress) {
					progress = false;
					var keys: Array<String> = [];
					for (k in currentNeededSuperThunks.keys()) keys.push(k);
					keys.sort(Reflect.compare);
					for (k in keys) {
						if (emitted.exists(k)) continue;
						var spec = currentNeededSuperThunks.get(k);
						if (spec == null) continue;
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

			// Implement any Haxe interfaces as Rust traits on `RefCell<Class>`.
			for (iface in classType.interfaces) {
				var ifaceType = iface.t.get();
				if (ifaceType == null) continue;
				if (!shouldEmitClass(ifaceType, false)) continue;

				var ifaceMod = rustModuleNameForClass(ifaceType);
				var traitPath = "crate::" + ifaceMod + "::" + rustTypeNameForClass(ifaceType);
				var ifaceTypeArgs = iface.params != null && iface.params.length > 0
					? ("<" + [for (p in iface.params) rustTypeToString(toRustType(p, classType.pos))].join(", ") + ">")
					: "";
				var implGenerics = classGenericDecls.length > 0 ? "<" + classGenericDecls.join(", ") + ">" : "";
				var implGenericNames = rustGenericNamesFromDecls(classGenericDecls);
				var implTurbofish = implGenericNames.length > 0 ? ("::<" + implGenericNames.join(", ") + ">") : "";

					var implLines: Array<String> = [];
					implLines.push("impl" + implGenerics + " " + traitPath + ifaceTypeArgs + " for " + refCellBasePath() + "<" + rustSelfTypeInst + "> {");
					for (f in effectiveFuncFields) {
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
					implLines.push("\t\t" + rustSelfType + implTurbofish + "::" + implRustName + "(" + callArgs.join(", ") + ")");
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
					withFunctionContext(f.expr, [for (a in f.args) a.getName()], f.ret, () -> {
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
		currentClassType = null;
		currentMethodOwnerType = null;
		currentNeededSuperThunks = null;
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

			var rustImpls = rustImplsFromMeta(enumType.meta);
			for (spec in rustImpls) {
				items.push(RRaw(renderRustImplBlock(spec, [], enumType.name)));
			}

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
		// Framework-only helpers: `Lambda` is used heavily at compile-time (including by Haxe's own macro
		// stdlib via `using Lambda`), but we treat it as an inline/macro-time helper and avoid emitting a
		// Rust module for it.
		if (classType.pack.length == 0 && classType.name == "Lambda") return false;
		// Same idea as `Lambda`: this is an inline-only helper surface.
		if (classType.pack.length == 0 && classType.name == "ArrayTools") return false;
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

	function rustTypeNameForClass(classType: ClassType): String {
		return RustNaming.typeIdent(classType.name);
	}

	function rustTypeNameForEnum(enumType: EnumType): String {
		return RustNaming.typeIdent(enumType.name);
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

		// Methods (instance base->derived + static).
		//
		// Important: base method names must be reserved first so overrides keep the same Rust name,
		// and derived-only names disambiguate against inherited names.
		var chain: Array<ClassType> = [];
		var cur: Null<ClassType> = classType;
		while (cur != null) {
			chain.unshift(cur);
			cur = cur.superClass != null ? cur.superClass.t.get() : null;
		}

		for (cls in chain) {
			var clsMethodNames: Array<String> = [];
			for (cf in cls.fields.get()) {
				switch (cf.kind) {
					case FMethod(_):
						clsMethodNames.push(cf.getHaxeName());
					case _:
				}
			}
			clsMethodNames.sort(Reflect.compare);
			for (name in clsMethodNames) {
				if (methodMap.exists(name)) continue;
				var base = rustMemberBaseIdent(name);
				methodMap.set(name, RustNaming.stableUnique(base, methodUsed));
			}
		}

		var staticMethodNames: Array<String> = [];
		for (cf in classType.statics.get()) {
			switch (cf.kind) {
				case FMethod(_):
					staticMethodNames.push(cf.getHaxeName());
				case _:
			}
		}
		staticMethodNames.sort(Reflect.compare);
		for (name in staticMethodNames) {
			if (methodMap.exists(name)) continue;
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

	function rustAccessorSuffix(classType: ClassType, cf: ClassField): String {
		// Keep accessors warning-free (`non_snake_case`) even when a field name starts with `_`
		// (common for private backing fields like `_x`).
		var name = rustFieldName(classType, cf);
		var underscoreCount = 0;
		while (StringTools.startsWith(name, "_")) {
			underscoreCount++;
			name = name.substr(1);
		}
		if (name.length == 0) name = "field";
		return underscoreCount == 0 ? name : ("u" + underscoreCount + "_" + name);
	}

	function rustGetterName(classType: ClassType, cf: ClassField): String {
		return "__hx_get_" + rustAccessorSuffix(classType, cf);
	}

	function rustSetterName(classType: ClassType, cf: ClassField): String {
		return "__hx_set_" + rustAccessorSuffix(classType, cf);
	}

		function isAccessorForPublicPropertyInstance(classType: ClassType, accessorField: ClassField): Bool {
			var name = accessorField.getHaxeName();
			if (name == null) return false;
			if (classType.fields == null) return false;

				inline function propUsesAccessor(prop: ClassField, kind: String): Bool {
					if (!prop.isPublic) return false;
					return switch (prop.kind) {
						case FVar(read, write):
							(kind == "get" && read == AccCall) || (kind == "set" && write == AccCall);
						case _:
							false;
					}
				}

			if (StringTools.startsWith(name, "get_")) {
				var propName = name.substr(4);
				var cur: Null<ClassType> = classType;
				while (cur != null) {
					for (cf in cur.fields.get()) if (cf.getHaxeName() == propName) return propUsesAccessor(cf, "get");
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
			}
			if (StringTools.startsWith(name, "set_")) {
				var propName = name.substr(4);
				var cur: Null<ClassType> = classType;
				while (cur != null) {
					for (cf in cur.fields.get()) if (cf.getHaxeName() == propName) return propUsesAccessor(cf, "set");
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
			}
			return false;
		}

		function isAccessorForPublicPropertyStatic(classType: ClassType, accessorField: ClassField): Bool {
			var name = accessorField.getHaxeName();
			if (name == null) return false;
			if (classType.statics == null) return false;

				inline function propUsesAccessor(prop: ClassField, kind: String): Bool {
					if (!prop.isPublic) return false;
					return switch (prop.kind) {
					case FVar(read, write):
						(kind == "get" && read == AccCall) || (kind == "set" && write == AccCall);
					case _:
						false;
				}
			}

			if (StringTools.startsWith(name, "get_")) {
				var propName = name.substr(4);
				var cur: Null<ClassType> = classType;
				while (cur != null) {
					for (cf in cur.statics.get()) if (cf.getHaxeName() == propName) return propUsesAccessor(cf, "get");
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
			}
			if (StringTools.startsWith(name, "set_")) {
				var propName = name.substr(4);
				var cur: Null<ClassType> = classType;
				while (cur != null) {
					for (cf in cur.statics.get()) if (cf.getHaxeName() == propName) return propUsesAccessor(cf, "set");
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
			}
			return false;
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
		// `Null<T>` defaults to `null` in Haxe, which maps to `Option<T>::None` on this target.
		switch (TypeTools.follow(t)) {
			case TAbstract(absRef, params): {
				var abs = absRef.get();
				if (abs != null && abs.module == "StdTypes" && abs.name == "Null" && params.length == 1) {
					return "None";
				}
			}
			case _:
		}

		if (TypeHelper.isBool(t)) return "false";
		if (TypeHelper.isInt(t)) return "0";
		if (TypeHelper.isFloat(t)) return "0.0";
		if (isStringType(t)) return "String::new()";
		if (isRustVecType(t)) return "Vec::new()";
		if (isRustHashMapType(t)) return "std::collections::HashMap::new()";
		if (isArrayType(t)) {
			var elem = arrayElementType(t);
			var elemRust = toRustType(elem, pos);
			return "hxrt::array::Array::<" + rustTypeToString(elemRust) + ">::new()";
		}

		return "Default::default()";
	}

		function compileConstructor(classType: ClassType, varFields: Array<ClassVarData>, f: ClassFuncData): reflaxe.rust.ast.RustAST.RustFunction {
			var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
			var modName = rustModuleNameForClass(classType);
			var rustSelfType = rustTypeNameForClass(classType);
			var selfRefTy = RPath("crate::HxRef<crate::" + modName + "::" + rustClassTypeInst(classType) + ">");

			var stmts: Array<RustStmt> = [];
			if (f.expr != null) {
				// If this ctor calls `super(...)`, we inline base-ctor bodies into this Rust function.
				// Compute local mutation/read-count context over the combined (base+derived) bodies so
				// `mut` and clone decisions remain correct and name collisions are avoided.
				var ctxExpr: TypedExpr = f.expr;
				if (classType.superClass != null) {
					var chain: Array<TypedExpr> = [];
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
						ctxExpr = { expr: TBlock(chain.concat([f.expr])), pos: f.expr.pos, t: f.expr.t };
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
					var liftedFieldInit: Map<String, String> = new Map();
					var remainingExprs: Null<Array<TypedExpr>> = null;

					var exprU = unwrapMetaParen(f.expr);
					switch (exprU.expr) {
						case TBlock(exprs): {
							var ctorArgNames: Map<String, Bool> = new Map();
							for (a in f.args) {
								var n = a.getName();
								if (n != null && n.length > 0) ctorArgNames.set(n, true);
							}

							function isCtorArgLocal(v: TVar): Bool {
								return v != null && v.name != null && ctorArgNames.exists(v.name);
							}

							function tryLift(e: TypedExpr): Null<{ field: String, rhs: String }> {
								var u = unwrapMetaParen(e);
								return switch (u.expr) {
									case TBinop(OpAssign, lhs, rhs): {
										var l = unwrapMetaParen(lhs);
								switch (l.expr) {
											case TField(obj, fa): {
												switch (unwrapMetaParen(obj).expr) {
													case TConst(TThis): {
														// Resolve the Haxe field name.
														var haxeFieldName: Null<String> = null;
														var haxeFieldType: Null<Type> = null;
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
														if (haxeFieldName == null) return null;

															var r = unwrapMetaParen(rhs);
															switch (r.expr) {
																case TLocal(v) if (isCtorArgLocal(v)):
																	{
																		var exprStr = reflaxe.rust.ast.RustASTPrinter.printExprForInjection(compileExpr(r));

																		// Prefer moving constructor args into the struct init when safe:
																		// - Copy types never need `.clone()`
																		// - For non-Copy types, only clone when the arg is used again later in the constructor body
																		//   (based on local read counts collected for the function context).
																		var needsClone = !isCopyType(v.t);
																		if (needsClone && currentLocalReadCounts != null && currentLocalReadCounts.exists(v.id)) {
																			var reads = currentLocalReadCounts.get(v.id);
																			if (reads <= 1) needsClone = false;
																		}

																		{
																			field: haxeFieldName,
																			rhs: {
																				var base = needsClone ? (exprStr + ".clone()") : exprStr;
																				if (haxeFieldType != null && isNullType(haxeFieldType) && !isNullType(v.t)) {
																					"Some(" + base + ")";
																				} else {
																					base;
																				}
																			},
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
									case _:
										null;
								}
							}

							var out: Array<TypedExpr> = [];
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

					var fieldInits: Array<String> = [];
					for (cf in getAllInstanceVarFieldsForStruct(classType)) {
						var haxeName = cf.getHaxeName();
						if (liftedFieldInit.exists(haxeName)) {
							fieldInits.push(rustFieldName(classType, cf) + ": " + liftedFieldInit.get(haxeName));
						} else {
							fieldInits.push(rustFieldName(classType, cf) + ": " + defaultValueForType(cf.type, cf.pos));
						}
					}
					if (classNeedsPhantomForUnusedTypeParams(classType)) {
						fieldInits.push("__hx_phantom: std::marker::PhantomData");
					}
					var structInit = rustSelfType + " { " + fieldInits.join(", ") + " }";
					var allocExpr = rcBasePath() + "::new(" + refCellBasePath() + "::new(" + structInit + "))";

					stmts.push(RLet(
						"self_",
						false,
						selfRefTy,
						ERaw(allocExpr)
					));

					function unwrapLeadingSuperCall(e: TypedExpr): Null<Array<TypedExpr>> {
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

					function allocTemp(base: String): String {
						if (currentLocalUsed == null) return base;
						return RustNaming.stableUnique(base, currentLocalUsed);
					}

					function ctorFieldFor(cls: ClassType): Null<ClassField> {
						return cls != null && cls.constructor != null ? cls.constructor.get() : null;
					}

					function ctorParamsFor(cls: ClassType): Array<{ name: String, t: Type, opt: Bool }> {
						var cf = ctorFieldFor(cls);
						if (cf == null) return [];
						return switch (followType(cf.type)) {
							case TFun(params, _): params;
							case _: [];
						};
					}

					function ctorBodyFor(cls: ClassType): Null<TypedExpr> {
						var cf = ctorFieldFor(cls);
						var ex = cf != null ? cf.expr() : null;
						if (ex == null) return null;
						// ClassField.expr() returns a `TFunction` for methods; we want the body expression.
						return switch (ex.expr) {
							case TFunction(fn): fn.expr;
							case _: ex;
						};
					}

					function compilePositionalArgsFor(params: Array<{ name: String, t: Type, opt: Bool }>, args: Array<TypedExpr>): Array<{ param: { name: String, t: Type, opt: Bool }, rust: RustExpr, typed: Null<TypedExpr> }> {
						var out: Array<{ param: { name: String, t: Type, opt: Bool }, rust: RustExpr, typed: Null<TypedExpr> }> = [];
						for (i in 0...params.length) {
							var p = params[i];
							if (i < args.length) {
								var a = args[i];
								var compiled = compileExpr(a);
								compiled = coerceArgForParam(compiled, a, p.t);
								out.push({ param: p, rust: compiled, typed: a });
								} else if (p.opt) {
									var d = isNullType(p.t) ? "None" : defaultValueForType(p.t, f.field.pos);
									out.push({ param: p, rust: ERaw(d), typed: null });
								} else {
									// Typechecker should prevent this; keep a deterministic fallback.
									out.push({ param: p, rust: ERaw(defaultValueForType(p.t, f.field.pos)), typed: null });
								}
						}
						return out;
					}

					function emitCtorChainInit(cls: ClassType, callArgs: Array<TypedExpr>, depth: Int): Void {
						if (cls == null) return;
						var ctorExpr = ctorBodyFor(cls);
						if (ctorExpr == null) return;

						var params = ctorParamsFor(cls);
						var compiledArgs = compilePositionalArgsFor(params, callArgs);

						// Evaluate super-call args once, in order, into temps.
						var subst: Map<String, RustExpr> = new Map();
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

						function withSubst<T>(m: Map<String, RustExpr>, fn: () -> T): T {
							var prev = inlineLocalSubstitutions;
							inlineLocalSubstitutions = m;
							var out = fn();
							inlineLocalSubstitutions = prev;
							return out;
						}

						withSubst(subst, () -> {
							// If this ctor starts with a `super(...)` call, inline the super-ctor first.
							var exprU = unwrapMetaParen(ctorExpr);
							var remaining: Array<TypedExpr> = null;
							var superArgs: Null<Array<TypedExpr>> = null;
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
								var bodyExpr: TypedExpr = { expr: TBlock(remaining), pos: ctorExpr.pos, t: ctorExpr.t };
								var block = compileVoidBody(bodyExpr);
								for (s in block.stmts) stmts.push(s);
								if (block.tail != null) stmts.push(RSemi(block.tail));
							} else {
								var block = compileVoidBody(ctorExpr);
								for (s in block.stmts) stmts.push(s);
								if (block.tail != null) stmts.push(RSemi(block.tail));
							}
							return null;
						});
					}

					// Remove a leading `super(...)` call from the derived ctor body and inline the base ctor chain.
					var bodyExpr: TypedExpr = f.expr;
					var exprsForBody: Null<Array<TypedExpr>> = remainingExprs;
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
						bodyExpr = { expr: TBlock(exprsForBody), pos: f.expr.pos, t: f.expr.t };
					}

					var bodyBlock = compileFunctionBody(bodyExpr, f.ret);
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

		function compileInstanceMethod(classType: ClassType, f: ClassFuncData, methodOwner: ClassType): reflaxe.rust.ast.RustAST.RustFunction {
			var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
			var generics = rustGenericParamsFromFieldMeta(f.field.meta, [for (p in f.field.params) p.name]);
			var selfName = exprUsesThis(f.expr) ? "self_" : "_self_";
			args.push({
				name: selfName,
				ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">")
			});
			var body = { stmts: [], tail: null };
			var prevOwner = currentMethodOwnerType;
			currentMethodOwnerType = methodOwner;
			var prevField = currentMethodField;
			currentMethodField = f.field;
			withFunctionContext(f.expr, [for (a in f.args) a.getName()], f.ret, () -> {
				for (a in f.args) {
					args.push({
						name: rustArgIdent(a.getName()),
						ty: toRustType(a.type, f.field.pos)
					});
				}
				body = compileFunctionBody(f.expr, f.ret);
			});
			currentMethodOwnerType = prevOwner;
			currentMethodField = prevField;

			return {
				name: rustMethodName(classType, f.field),
				// Haxe allows `public var x(get, never)` while keeping `get_x()` itself private.
				// Rust module privacy is stricter, so make accessors public when the property is public.
				isPub: f.field.isPublic || isAccessorForPublicPropertyInstance(classType, f.field),
			generics: generics,
			args: args,
			ret: rustReturnTypeForField(f.field, f.ret, f.field.pos),
			body: body
		};
	}

		function compileStaticMethod(classType: ClassType, f: ClassFuncData): reflaxe.rust.ast.RustAST.RustFunction {
			var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
			var generics = rustGenericParamsFromFieldMeta(f.field.meta, [for (p in f.field.params) p.name]);
			var body = { stmts: [], tail: null };
			var prevField = currentMethodField;
			currentMethodField = f.field;
			withFunctionContext(f.expr, [for (a in f.args) a.getName()], f.ret, () -> {
				for (a in f.args) {
					args.push({
						name: rustArgIdent(a.getName()),
						ty: toRustType(a.type, f.field.pos)
					});
				}
				body = compileFunctionBody(f.expr, f.ret);
			});
			currentMethodField = prevField;

			return {
				name: rustMethodName(classType, f.field),
				isPub: f.field.isPublic || isAccessorForPublicPropertyStatic(classType, f.field),
			generics: generics,
			args: args,
			ret: rustReturnTypeForField(f.field, f.ret, f.field.pos),
			body: body
		};
	}

		function compileSuperThunk(classType: ClassType, owner: ClassType, cf: ClassField): reflaxe.rust.ast.RustAST.RustFunction {
			var ex = cf.expr();
			if (ex == null) {
				// Should only happen if `noteSuperThunk` registered a method with no body.
				return {
					name: superThunkName(owner, cf),
					isPub: false,
					args: [{ name: "_self_", ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">") }],
					ret: RPath("()"),
					body: { stmts: [RSemi(ERaw("todo!()"))], tail: null }
				};
			}

			var bodyExpr = unwrapFieldFunctionBody(ex);
			var sig = switch (followType(cf.type)) {
				case TFun(params, ret): { params: params, ret: ret };
				case _: null;
			};
			if (sig == null) {
				return {
					name: superThunkName(owner, cf),
					isPub: false,
					args: [{ name: "_self_", ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">") }],
					ret: RPath("()"),
					body: { stmts: [RSemi(ERaw("todo!()"))], tail: null }
				};
			}

			var selfName = exprUsesThis(bodyExpr) ? "self_" : "_self_";
			var args: Array<reflaxe.rust.ast.RustAST.RustFnArg> = [];
			args.push({
				name: selfName,
				ty: RPath("&" + refCellBasePath() + "<" + rustClassTypeInst(classType) + ">")
			});

			var argNames: Array<String> = [];
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
			var body = { stmts: [], tail: null };
			var prevOwner = currentMethodOwnerType;
			currentMethodOwnerType = owner;
			var prevField = currentMethodField;
			currentMethodField = cf;
			withFunctionContext(bodyExpr, argNames, sig.ret, () -> {
				body = compileFunctionBody(bodyExpr, sig.ret);
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

	function rustReturnTypeFromMeta(meta: haxe.macro.Type.MetaAccess): Null<reflaxe.rust.ast.RustAST.RustType> {
		for (entry in meta.get()) {
			if (entry.name != ":rustReturn") continue;
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

	function rustReturnTypeForField(field: ClassField, haxeRet: Type, pos: haxe.macro.Expr.Position): reflaxe.rust.ast.RustAST.RustType {
		var overrideTy = rustReturnTypeFromMeta(field.meta);
		return overrideTy != null ? overrideTy : toRustType(haxeRet, pos);
	}

	function rustGenericNamesFromDecls(decls: Array<String>): Array<String> {
		var out: Array<String> = [];
		for (d in decls) {
			var s = StringTools.trim(d);
			if (s.length == 0) continue;
			var colon = s.indexOf(":");
			var name = colon >= 0 ? s.substr(0, colon) : s;
			name = StringTools.trim(name);
			// Be defensive: `T where ...` isn't valid in Rust generics, but avoid generating garbage names.
			var space = name.indexOf(" ");
			if (space >= 0) name = name.substr(0, space);
			out.push(name);
		}
		return out;
	}

	function rustGenericDeclsForClass(classType: ClassType): Array<String> {
		var out: Array<String> = [];
		var found = false;

		for (entry in classType.meta.get()) {
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

		if (found) return out;

		// Default bounds policy for class-level generics:
		//
		// Class instances are interior-mutable (`Rc<RefCell<_>>`) and methods commonly need to return
		// values by value while borrowing `self`. To preserve Haxe's "values are reusable" semantics,
		// codegen often clones non-`Copy` fields/values, so we default to `T: Clone` for class params.
		var bounded: Array<String> = [];
		for (p in classType.params) bounded.push(p.name + ": Clone");
		return bounded;
	}

	function rustClassTypeInst(classType: ClassType): String {
		var base = rustTypeNameForClass(classType);
		var decls = rustGenericDeclsForClass(classType);
		var names = rustGenericNamesFromDecls(decls);
		return names.length > 0 ? (base + "<" + names.join(", ") + ">") : base;
	}

	function haxeTypeContainsClassTypeParam(t: Type, typeParamNames: Map<String, Bool>): Bool {
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
				for (p in params) if (haxeTypeContainsClassTypeParam(p, typeParamNames)) return true;
				false;
			}
			case TAbstract(_, params): {
				for (p in params) if (haxeTypeContainsClassTypeParam(p, typeParamNames)) return true;
				false;
			}
			case TEnum(_, params): {
				for (p in params) if (haxeTypeContainsClassTypeParam(p, typeParamNames)) return true;
				false;
			}
			case TFun(params, ret): {
				for (p in params) if (haxeTypeContainsClassTypeParam(p.t, typeParamNames)) return true;
				haxeTypeContainsClassTypeParam(ret, typeParamNames);
			}
			case TAnonymous(anonRef): {
				var anon = anonRef.get();
				if (anon != null && anon.fields != null) {
					for (cf in anon.fields) if (haxeTypeContainsClassTypeParam(cf.type, typeParamNames)) return true;
				}
				false;
			}
			case _:
				false;
		}
	}

	function classNeedsPhantomForUnusedTypeParams(classType: ClassType): Bool {
		var decls = rustGenericDeclsForClass(classType);
		var names = rustGenericNamesFromDecls(decls);
		if (names.length == 0) return false;

		var nameSet: Map<String, Bool> = new Map();
		for (n in names) nameSet.set(n, true);

		for (cf in getAllInstanceVarFieldsForStruct(classType)) {
			if (haxeTypeContainsClassTypeParam(cf.type, nameSet)) return false;
		}
		return true;
	}

	function compileFunctionBody(e: TypedExpr, expectedReturn: Null<Type> = null): RustBlock {
		var allowTail = true;
		if (expectedReturn != null && TypeHelper.isVoid(expectedReturn)) {
			allowTail = false;
		}

		return switch (e.expr) {
			case TBlock(exprs): compileBlock(exprs, allowTail, expectedReturn);
			case _: {
				// Single-expression function body
				{ stmts: [compileStmt(e)], tail: null };
			}
		}
	}

		function compileBlock(exprs: Array<TypedExpr>, allowTail: Bool = true, expectedTail: Null<Type> = null): RustBlock {
			var stmts: Array<RustStmt> = [];
			var tail: Null<RustExpr> = null;

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
					case TVar(v, init) if (init != null && isNullType(v.t) && isNullConstExpr(init)): {
						if (currentMutatedLocals != null && currentMutatedLocals.exists(v.id) && i + 1 < exprs.length) {
							function isDirectLocalAssignTo(target: TVar, expr: TypedExpr): Bool {
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
								function countDirectAssignsTo(target: TVar, expr: TypedExpr): Int {
									var count = 0;
									function scan(x: TypedExpr): Void {
										switch (x.expr) {
											case TBinop(OpAssign, lhs, _) | TBinop(OpAssignOp(_), lhs, _): {
												switch (unwrapMetaParen(lhs).expr) {
													case TLocal(v2) if (v2.id == target.id):
														count++;
													case _:
												}
											}
											case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement): {
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
					case TVar(v, init) if (init != null && i + 1 < exprs.length): {
						// Idiomatic move optimization (conservative, straight-line only):
						// If we immediately overwrite a local `x` on the next statement, then `var y = x; x = ...;`
						// does not need to clone `x` into `y`. Moving `x` is safe because the old value dies before
						// any subsequent read of `x`.
						//
						// This is primarily useful for `String` (owned `String` in Rust), where cloning is costly.
						function unwrapToLocal(e: TypedExpr): Null<TVar> {
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
							function isDirectLocalAssignTo(target: TVar, expr: TypedExpr): Bool {
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

										// `rust.HashMap` iterators (`keys()` / `values()`) are already valid Rust
										// iterables; use them directly (borrowed items, no cloning).
										if (isRustHashMapType(objU.t) && (matchesFieldName(fa, "keys") || matchesFieldName(fa, "values"))) {
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
								// If we can't recover a Rust-native iterable, fall back to using the iterator value
								// directly. `hxrt::iter::Iter<T>` implements `IntoIterator`, so Rust `for` loops can
								// consume it safely.
								if (it == null) it = compileExpr(itInit);

								var bodyBlock = compileBlock(bodyExprs.slice(1), false);
								return RFor(rustLocalDeclIdent(loopVar), it, bodyBlock);
							}
							case _:
								return null;
						}
					}

					var lowered = tryLowerDesugaredFor(exprs);
					if (lowered != null) return lowered;

					// Fallback: treat block as a statement-position expression (unit block; no semicolon).
					RExpr(EBlock(compileBlock(exprs, false)), false);
				}
				case TVar(v, init): {
					var name = rustLocalDeclIdent(v);
					var rustTy = toRustType(v.t, e.pos);
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

						// `Null<T>` locals must store `Some(value)` when initialized from a non-null `T`.
						// (Avoid double-wrapping for `Null<Fn>` which is handled by `coerceArgForParam` above.)
						if (isNullType(v.t) && !isNullType(init.t) && !isNullConstExpr(init)) {
							switch (followType(v.t)) {
								case TFun(_, _):
									// handled above
								case _:
									var stored = maybeCloneForReuse(initExpr, init);
									initExpr = ECall(EPath("Some"), [stored]);
							}
						}

						// Haxe sometimes treats `Null<T> -> T` as "assert non-null" (e.g. null-safety off or
						// implicit coercions in desugared code). In Rust output this is `Option<T> -> T`,
						// so unwrap.
						if (!isNullType(v.t) && isNullType(init.t) && !isNullConstExpr(init)) {
							initExpr = ECall(EField(initExpr, "unwrap"), []);
						}

						// Preserve Haxe reuse/aliasing semantics for reference-like values:
						// `var b = a;` must not move `a` in Rust output.
						initExpr = maybeCloneForReuseValue(initExpr, init);
					}
					var mutable = currentMutatedLocals != null && currentMutatedLocals.exists(v.id);
					RLet(name, mutable, rustTy, initExpr);
				}
				case TIf(cond, eThen, eElse): {
					// Statement-position if: force unit branches so we can omit a trailing semicolon.
					var thenExpr = EBlock(compileVoidBody(eThen));
					var elseExpr: Null<RustExpr> = eElse != null ? EBlock(compileVoidBody(eElse)) : null;
					RExpr(EIf(compileExpr(cond), thenExpr, elseExpr), false);
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
							RWhile(compileExpr(cond), compileVoidBody(body));
					}
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
						// `hxrt::array::Array<T>::iter()` returns an owned iterator; do not append `.cloned()`.
						if (isArrayType(x.t)) {
							return ECall(EField(compileExpr(x), "iter"), []);
						}
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
				if (ret != null && ex != null) {
					ex = coerceExprToExpected(ex, ret, currentFunctionReturn);
				}
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

		function withFunctionContext<T>(bodyExpr: TypedExpr, argNames: Array<String>, expectedReturn: Null<Type>, fn: () -> T): T {
			var prevMutated = currentMutatedLocals;
			var prevReadCounts = currentLocalReadCounts;
			var prevArgNames = currentArgNames;
			var prevLocalNames = currentLocalNames;
			var prevLocalUsed = currentLocalUsed;
			var prevEnumParamBinds = currentEnumParamBinds;
			var prevReturn = currentFunctionReturn;

			currentMutatedLocals = collectMutatedLocals(bodyExpr);
			currentLocalReadCounts = collectLocalReadCounts(bodyExpr);
			currentArgNames = [];
			currentLocalNames = [];
			currentLocalUsed = [];
			currentEnumParamBinds = null;
			currentFunctionReturn = expectedReturn;

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
			currentLocalReadCounts = prevReadCounts;
			currentArgNames = prevArgNames;
			currentLocalNames = prevLocalNames;
			currentLocalUsed = prevLocalUsed;
			currentEnumParamBinds = prevEnumParamBinds;
			currentFunctionReturn = prevReturn;
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
			return withFunctionContext(e, argNames, expectedReturn, () -> compileFunctionBody(e, expectedReturn));
		}

		function compileVoidBodyWithContext(e: TypedExpr, argNames: Array<String>): RustBlock {
			return withFunctionContext(e, argNames, Context.getType("Void"), () -> compileVoidBody(e));
		}

		function collectMutatedLocals(root: TypedExpr): Map<Int, Bool> {
			var mutated: Map<Int, Bool> = [];
			var declaredWithoutInit: Map<Int, Bool> = [];
			var assignCounts: Map<Int, Int> = [];

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
				case TVar(v, init): {
					if (init == null) {
						// Rust allows `let x; x = value;` without `mut` (the first assignment is initialization).
						declaredWithoutInit.set(v.id, true);
					}

					if (init != null && isRustMutRefType(v.t)) {
						// Taking a `rust.MutRef<T>` from a local requires the source binding to be `mut`.
						markLocal(init);
					}
				}

					case TBinop(OpAssign, lhs, _) | TBinop(OpAssignOp(_), lhs, _): {
						switch (lhs.expr) {
							case TLocal(v):
								if (declaredWithoutInit.exists(v.id)) {
									var prev = assignCounts.exists(v.id) ? assignCounts.get(v.id) : 0;
									assignCounts.set(v.id, prev + 1);
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
						}
						case _:
					}
				}

				case _:
			}

			TypedExprTools.iter(e, scan);
		}

		scan(root);

		// If a local was declared without an initializer, only require `mut` when it is assigned more than once.
		for (id in assignCounts.keys()) {
			if (assignCounts.get(id) > 1) mutated.set(id, true);
		}
		return mutated;
	}

		function collectLocalReadCounts(root: TypedExpr): Map<Int, Int> {
			var counts: Map<Int, Int> = [];

			function inc(v: TVar): Void {
				if (v == null) return;
				var prev = counts.exists(v.id) ? counts.get(v.id) : 0;
				counts.set(v.id, prev + 1);
			}

			function scan(e: TypedExpr): Void {
				switch (e.expr) {
					// Writes should not count as reads: `x = expr` does not "use" `x` for move/clone analysis.
					//
					// However, compound assignments and ++/-- do read the previous value.
					case TBinop(OpAssign, lhs, rhs): {
						switch (unwrapMetaParen(lhs).expr) {
							case TLocal(_):
								// Skip counting the local; still scan RHS.
							case _:
								scan(lhs);
						}
						scan(rhs);
						return;
					}
					case TBinop(OpAssignOp(_), lhs, rhs): {
						// Reads + writes: count and scan both sides.
						scan(lhs);
						scan(rhs);
						return;
					}
					case TUnop(op, _, inner) if (op == OpIncrement || op == OpDecrement): {
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

	function compileExpr(e: TypedExpr): RustExpr {
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
				var idx = ECast(compileExpr(index), "usize");
				// If the expression is typed as `Null<T>`, represent array access as `Option<T>`.
				// This avoids Rust panics on out-of-bounds and matches Haxe’s “nullable access” typing.
				if (isNullType(e.t)) {
					ECall(EField(compileExpr(arr), "get"), [idx]);
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
				if (eElse == null) {
					// `if (...) expr;` in Haxe is statement-shaped; ensure the Rust `if` branches yield `()`.
					EIf(compileExpr(cond), EBlock(compileVoidBody(eThen)), null);
				} else if (isNullType(e.t)) {
					var thenExpr = coerceExprToExpected(compileBranchExpr(eThen), eThen, e.t);
					var elseExpr = coerceExprToExpected(compileBranchExpr(eElse), eElse, e.t);
					EIf(compileExpr(cond), thenExpr, elseExpr);
				} else {
					EIf(compileExpr(cond), compileBranchExpr(eThen), compileBranchExpr(eElse));
				}

			case TBlock(exprs):
				EBlock(compileBlock(exprs));

			case TCall(callExpr, args):
				compileCall(callExpr, args, e);

				case TNew(clsRef, typeParams, args): {
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
					ECall(EPath(ctorBase + ctorParams + "::new"), [for (x in args) compileExpr(x)]);
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

				withFunctionContext(fn.expr, baseArgNames, fn.t, () -> {
					for (i in 0...fn.args.length) {
						var a = fn.args[i];
						var baseName = baseArgNames[i];
						var rustName = rustArgIdent(baseName);
						argParts.push(rustName + ": " + rustTypeToString(toRustType(a.v.t, e.pos)));
					}
					body = compileFunctionBody(fn.expr, fn.t);
				});

				ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, body, true)]);
			}

				case TCast(e1, _): {
					var inner = compileExpr(e1);
					var fromT = followType(e1.t);
					var toT = followType(e.t);

				// Numeric casts (`Int` <-> `Float`) must be explicit in Rust.
				if (!isNullType(e1.t)
					&& !isNullType(e.t)
					&& (TypeHelper.isInt(fromT) || TypeHelper.isFloat(fromT))
					&& (TypeHelper.isInt(toT) || TypeHelper.isFloat(toT))) {
					var target = rustTypeToString(toRustType(toT, e.pos));
					ECast(inner, target);
					} else if (isNullType(e1.t) && isNullType(e.t)) {
						// With nested nullability collapsed at the type level (`Null<Null<T>>` == `Null<T>`),
						// null-to-null casts become a no-op.
						inner;
					} else if (isNullType(e1.t) && !isNullType(e.t)) {
						// `@:nullSafety(Off)` and explicit casts from `Null<T>` to `T` are treated as
						// "assert non-null". In Rust output, `Null<T>` is `Option<T>`, so unwrap.
						ECall(EField(inner, "unwrap"), []);
					} else if (!isNullType(e1.t) && isNullType(e.t)) {
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
						var keyExpr: Null<TypedExpr> = null;
						var valueExpr: Null<TypedExpr> = null;
						for (f in fields) {
							switch (f.name) {
								case "key": keyExpr = f.expr;
								case "value": valueExpr = f.expr;
								case _:
							}
						}

						if (keyExpr != null && valueExpr != null) {
							return EStructLit("hxrt::iter::KeyValue", [
								{ name: "key", expr: compileExpr(keyExpr) },
								{ name: "value", expr: compileExpr(valueExpr) },
							]);
						}
					}

					// General record literal -> `{ let __o = Rc::new(RefCell::new(Anon::new())); { let mut __b = __o.borrow_mut(); __b.set(...); } __o }`
					function typedNoneForNull(t: Type, pos: haxe.macro.Expr.Position): RustExpr {
						var inner = nullInnerType(t);
						if (inner == null) return ERaw("None");
						var innerRust = rustTypeToString(toRustType(inner, pos));
						return ERaw("Option::<" + innerRust + ">::None");
					}

					var stmts: Array<RustStmt> = [];
					var objName = "__o";

					var newAnon = ECall(EPath("hxrt::anon::Anon::new"), []);
					var newRef = ECall(EPath(rcBasePath() + "::new"), [ECall(EPath(refCellBasePath() + "::new"), [newAnon])]);
					stmts.push(RLet(objName, false, null, newRef));

					var innerStmts: Array<RustStmt> = [];
					innerStmts.push(RLet("__b", true, null, ECall(EField(EPath(objName), "borrow_mut"), [])));
					if (fields != null) {
						for (f in fields) {
							var valueExpr = f.expr;
							var compiledVal: RustExpr;
							if (isNullConstExpr(valueExpr) && isNullType(valueExpr.t)) {
								compiledVal = typedNoneForNull(valueExpr.t, valueExpr.pos);
							} else {
								compiledVal = maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr);
							}
							innerStmts.push(RSemi(ECall(EField(EPath("__b"), "set"), [ELitString(f.name), compiledVal])));
						}
					}
					stmts.push(RSemi(EBlock({ stmts: innerStmts, tail: null })));

					return EBlock({ stmts: stmts, tail: EPath(objName) });
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
				coerceExprToExpected(compileExpr(expr), expr, expectedReturn);
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

	function isSuperExpr(e: TypedExpr): Bool {
		return switch (unwrapMetaParen(e).expr) {
			case TConst(TSuper): true;
			case _: false;
		};
	}

	function superThunkKey(owner: ClassType, cf: ClassField): String {
		var argc = switch (followType(cf.type)) {
			case TFun(args, _): args.length;
			case _: 0;
		};
		return classKey(owner) + ":" + cf.getHaxeName() + "/" + argc;
	}

	function superThunkName(owner: ClassType, cf: ClassField): String {
		// The name must be stable, avoid collisions across base-chain methods, and be unlikely to
		// clash with user code.
		return "__hx_super_" + rustModuleNameForClass(owner) + "_" + rustMethodName(owner, cf);
	}

	function noteSuperThunk(owner: ClassType, cf: ClassField): String {
		if (currentNeededSuperThunks == null) currentNeededSuperThunks = [];
		var key = superThunkKey(owner, cf);
		if (!currentNeededSuperThunks.exists(key)) currentNeededSuperThunks.set(key, { owner: owner, field: cf });
		return superThunkName(owner, cf);
	}

	function isNullConstExpr(e: TypedExpr): Bool {
		return switch (unwrapMetaParen(e).expr) {
			case TConst(TNull): true;
			case _: false;
		}
	}

	function nullInnerType(t: Type): Null<Type> {
		switch (t) {
			case TAbstract(absRef, params): {
				var abs = absRef.get();
				if (abs != null && abs.module == "StdTypes" && abs.name == "Null" && params.length == 1) {
					return params[0];
				}
			}
			case TLazy(f):
				return nullInnerType(f());
			case TType(typeRef, params): {
				var tt = typeRef.get();
				if (tt != null) {
					var under: Type = tt.type;
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

	function isNullType(t: Type): Bool {
		return nullInnerType(t) != null;
	}

	function maybeCloneForReuse(expr: RustExpr, valueExpr: TypedExpr): RustExpr {
		if (inCodeInjectionArg) return expr;
		if (isCopyType(valueExpr.t)) return expr;
		if (isStringLiteralExpr(valueExpr) || isArrayLiteralExpr(valueExpr) || isNewExpr(valueExpr)) return expr;
		if (isLocalExpr(valueExpr) && !isObviousTemporaryExpr(valueExpr)) {
			return ECall(EField(expr, "clone"), []);
		}
		return expr;
	}

	function isIteratorStructType(t: Type): Bool {
		var ft = followType(t);
		return switch (ft) {
			case TAnonymous(anonRef): {
				var anon = anonRef.get();
				if (anon == null || anon.fields == null || anon.fields.length != 2) return false;
				var hasNext = false;
				var next = false;
				for (cf in anon.fields) {
					switch (cf.getHaxeName()) {
						case "hasNext": hasNext = true;
						case "next": next = true;
						case _:
					}
				}
				hasNext && next;
			}
			case _:
				false;
		}
	}

	function isKeyValueStructType(t: Type): Bool {
		var ft = followType(t);
		return switch (ft) {
			case TAnonymous(anonRef): {
				var anon = anonRef.get();
				if (anon == null || anon.fields == null || anon.fields.length != 2) return false;
				var key = false;
				var value = false;
				for (cf in anon.fields) {
					switch (cf.getHaxeName()) {
						case "key": key = true;
						case "value": value = true;
						case _:
					}
				}
				key && value;
			}
			case _:
				false;
		}
	}

	function isAnonObjectType(t: Type): Bool {
		var ft = followType(t);
		return switch (ft) {
			case TAnonymous(_):
				!isIteratorStructType(t) && !isKeyValueStructType(t);
			case _:
				false;
		}
	}

	function isHaxeReusableValueType(t: Type): Bool {
		// Types that behave like Haxe reference values (must not be "moved" by Rust assignments).
		// - `Array<T>` is `hxrt::array::Array<T>` (Rc-backed).
		// - class instances / Bytes are `HxRef<T>` (Rc-backed).
		// - `String` is immutable and reusable in Haxe (needs clone in Rust when re-used).
		// - structural `Iterator<T>` maps to `hxrt::iter::Iter<T>` (Rc-backed).
		// - general anonymous objects map to `crate::HxRef<hxrt::anon::Anon>` (Rc-backed).
		return isArrayType(t) || isHxRefValueType(t) || isStringType(t) || isIteratorStructType(t) || isAnonObjectType(t) || isDynamicType(t);
	}

		function maybeCloneForReuseValue(expr: RustExpr, valueExpr: TypedExpr): RustExpr {
			if (inCodeInjectionArg) return expr;
			if (isCopyType(valueExpr.t)) return expr;
			if (isStringLiteralExpr(valueExpr) || isArrayLiteralExpr(valueExpr) || isNewExpr(valueExpr)) return expr;
			function isAlreadyClone(e: RustExpr): Bool {
				return switch (e) {
					case ECall(EField(_, "clone"), []): true;
					case _: false;
				}
			}
			if (isAlreadyClone(expr)) return expr;

			function unwrapToLocalId(e: TypedExpr): Null<Int> {
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
				if (reads <= 1) return expr;
			}

			if (isLocalExpr(valueExpr) && !isObviousTemporaryExpr(valueExpr) && isHaxeReusableValueType(valueExpr.t)) {
				return ECall(EField(expr, "clone"), []);
			}
			return expr;
		}

	function coerceExprToExpected(compiled: RustExpr, valueExpr: TypedExpr, expected: Null<Type>): RustExpr {
		if (expected == null) return compiled;
		if (isNullType(expected) && !isNullType(valueExpr.t) && !isNullConstExpr(valueExpr)) {
			return ECall(EPath("Some"), [compiled]);
		}
		return compiled;
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

	function isNewExpr(e: TypedExpr): Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TNew(_, _, _): true;
			case _: false;
		}
	}

	function isLocalExpr(e: TypedExpr): Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TLocal(_): true;
			case _: false;
		}
	}

	function isObviousTemporaryExpr(e: TypedExpr): Bool {
		var u = unwrapMetaParen(e);
		return switch (u.expr) {
			case TConst(_): true;
			case TArrayDecl(_): true;
			case TObjectDecl(_): true;
			case TNew(_, _, _): true;
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
			case "haxe.ds.Option" | "haxe.functional.Result" | "rust.Option" | "rust.Result" | "haxe.io.Error": true;
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
				case "haxe.io.Error":
					"hxrt::io::Error::" + variant;
				case _:
					"crate::" + rustModuleNameForEnum(en) + "::" + rustTypeNameForEnum(en) + "::" + variant;
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
			case TReturn(_) | TBreak | TContinue | TThrow(_):
				EBlock(compileVoidBody(e));
			case _:
				compileExpr(e);
		}
	}

	function compileCall(callExpr: TypedExpr, args: Array<TypedExpr>, fullExpr: TypedExpr): RustExpr {
		function compilePositionalArgsFor(params: Null<Array<{ name: String, t: Type, opt: Bool }>>): Array<RustExpr> {
			var out: Array<RustExpr> = [];

			for (i in 0...args.length) {
				var arg = args[i];
				var compiled = compileExpr(arg);
				if (params != null && i < params.length) {
					compiled = coerceArgForParam(compiled, arg, params[i].t);
				}
				out.push(compiled);
			}

			// Fill omitted optional args (`null` => `None` for `Null<T>`).
			if (params != null && args.length < params.length) {
				for (i in args.length...params.length) {
					if (!params[i].opt) break;
					var t = params[i].t;
					out.push(isNullType(t) ? ERaw("None") : ERaw(defaultValueForType(t, fullExpr.pos)));
				}
			}

			return out;
		}

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

							function typeHasTypeParameter(t: Type): Bool {
								var cur = followType(t);
								return switch (cur) {
									case TInst(clsRef, params): {
										var cls = clsRef.get();
										if (cls != null) {
											switch (cls.kind) {
												case KTypeParameter(_):
													true;
												case _:
													for (p in params) if (typeHasTypeParameter(p)) return true;
													false;
											}
										} else {
											false;
										}
									}
									case TAbstract(_, params): {
										for (p in params) if (typeHasTypeParameter(p)) return true;
										false;
									}
									case TEnum(_, params): {
										for (p in params) if (typeHasTypeParameter(p)) return true;
										false;
									}
									case TFun(params, ret): {
										for (p in params) if (typeHasTypeParameter(p.t)) return true;
										typeHasTypeParameter(ret);
									}
									case TAnonymous(anonRef): {
										var anon = anonRef.get();
										if (anon != null && anon.fields != null) {
											for (cf in anon.fields) if (typeHasTypeParameter(cf.type)) return true;
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
								return ECall(EField(compileExpr(value), "to_haxe_string"), []);
							} else if (isCopyType(ft)) {
								return ECall(EField(compileExpr(value), "to_string"), []);
							} else if (typeHasTypeParameter(ft)) {
								// `hxrt::dynamic::from(...)` requires `T: Any + 'static`, which generic type parameters
								// don't necessarily satisfy. Fall back to `Debug` formatting for generic types.
								return EMacroCall("format", [ELitString("{:?}"), compileExpr(value)]);
							} else {
								var compiled = compileExpr(value);
								var needsClone = !isCopyType(value.t);
								// Avoid cloning obvious temporaries (literals) that won't be re-used after stringification.
								if (needsClone && isStringLiteralExpr(value)) needsClone = false;
								if (needsClone && isArrayLiteralExpr(value)) needsClone = false;
								if (needsClone) {
									compiled = ECall(EField(compiled, "clone"), []);
								}
								// Route through the runtime so `Std.string`, `trace`, and `Sys.println`
								// converge on the same formatting rules.
								return ECall(EField(ECall(EPath("hxrt::dynamic::from"), [compiled]), "to_haxe_string"), []);
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

								// Classes: compile to a concrete field read and box into Dynamic.
								switch (followType(obj.t)) {
									case TInst(cls2Ref, _): {
										var owner = cls2Ref.get();
										if (owner != null) {
											var cf: Null<ClassField> = null;
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
											var cf: Null<ClassField> = null;
											for (f in anon.fields) {
												if (f.name == fieldName || f.getHaxeName() == fieldName) {
													cf = f;
													break;
												}
											}
											if (cf != null) {
												var value: RustExpr;
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

								return unsupported(fullExpr, "Reflect.field (unsupported receiver/field)");
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

								// Haxe signature is `setField(o:Dynamic, field:String, value:Dynamic):Void`,
								// so typed AST generally coerces `value` to Dynamic. Convert back via runtime downcast.
								function dynamicToConcrete(dynVar: String, target: Type, pos: haxe.macro.Expr.Position): RustExpr {
									var nullInner = nullInnerType(target);
									if (nullInner != null) {
										var innerRust = rustTypeToString(toRustType(nullInner, pos));
										var optTyStr = "Option<" + innerRust + ">";
										var optTry = "__opt";
										var stmts: Array<RustStmt> = [];
										stmts.push(RLet(optTry, false, null, ECall(EField(EPath(dynVar), "downcast_ref::<" + optTyStr + ">"), [])));
										var hasOpt = ECall(EField(EPath(optTry), "is_some"), []);
										var thenExpr = ECall(EField(ECall(EField(EPath(optTry), "unwrap"), []), "clone"), []);
										var innerExpr = ECall(
											EField(ECall(EField(EPath(dynVar), "downcast_ref::<" + innerRust + ">"), []), "unwrap"),
											[]
										);
										var elseExpr = ECall(EPath("Some"), [ECall(EField(innerExpr, "clone"), [])]);
										return EBlock({ stmts: stmts, tail: EIf(hasOpt, thenExpr, elseExpr) });
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
											var cf: Null<ClassField> = null;
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

														var stmts: Array<RustStmt> = [];
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
														return EBlock({ stmts: stmts, tail: null });
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
											var cf: Null<ClassField> = null;
											for (f in anon.fields) {
												if (f.name == fieldName || f.getHaxeName() == fieldName) {
													cf = f;
													break;
												}
											}
											if (cf != null && isAnonObjectType(obj.t)) {
												var stmts: Array<RustStmt> = [];
												stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));
												var rhsExpr = maybeCloneForReuseValue(compileExpr(valueExpr), valueExpr);
												if (isDynamicType(valueExpr.t)) {
													stmts.push(RLet("__v", false, null, rhsExpr));
													stmts.push(RLet("__val", false, null, dynamicToConcrete("__v", cf.type, fullExpr.pos)));
												} else {
													stmts.push(RLet("__val", false, null, coerceExprToExpected(rhsExpr, valueExpr, cf.type)));
												}
												var setCall = ECall(EField(ECall(EField(EPath("__obj"), "borrow_mut"), []), "set"), [ELitString(cf.getHaxeName()), EPath("__val")]);
												stmts.push(RSemi(setCall));
												return EBlock({ stmts: stmts, tail: null });
											}
										}
									}
									case _:
								}

								return unsupported(fullExpr, "Reflect.setField (unsupported receiver/field)");
							}

							case "hasField": {
								if (args.length != 2) return unsupported(fullExpr, "Reflect.hasField args");

								var obj = args[0];
								var nameExpr = args[1];
								var fieldName: Null<String> = switch (nameExpr.expr) {
									case TConst(TString(s)): s;
									case _: null;
								};
								if (fieldName == null) return unsupported(fullExpr, "Reflect.hasField non-const");

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
							if (args.length != 1) return unsupported(fullExpr, "Bytes.alloc args");
							var size = ECast(compileExpr(args[0]), "usize");
							var inner = ECall(EPath("hxrt::bytes::Bytes::alloc"), [size]);
								return ECall(EPath(rcBasePath() + "::new"), [ECall(EPath(refCellBasePath() + "::new"), [inner])]);
						}
						case "ofString": {
							// Ignore optional encoding arg for now (must be null / omitted).
							if (args.length != 1 && args.length != 2) return unsupported(fullExpr, "Bytes.ofString args");
							var s = args[0];
							// Preserve evaluation order/side-effects for the encoding expression (even though we
							// currently treat encodings the same at runtime).
							if (args.length == 2) {
								var enc = compileExpr(args[1]);
								// `{ let _ = enc; Rc::new(RefCell::new(Bytes::of_string(...))) }`
								var asStr = ECall(EField(compileExpr(s), "as_str"), []);
								var inner = ECall(EPath("hxrt::bytes::Bytes::of_string"), [asStr]);
								var wrapped = ECall(EPath(rcBasePath() + "::new"), [ECall(EPath(refCellBasePath() + "::new"), [inner])]);
								return EBlock({ stmts: [RLet("_", false, null, enc)], tail: wrapped });
							}
							var asStr = ECall(EField(compileExpr(s), "as_str"), []);
							var inner = ECall(EPath("hxrt::bytes::Bytes::of_string"), [asStr]);
								return ECall(EPath(rcBasePath() + "::new"), [ECall(EPath(refCellBasePath() + "::new"), [inner])]);
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
			case TField(obj, FInstance(clsRef, _, cfRef)): {
				var owner = clsRef.get();
				var cf = cfRef.get();
				if (owner == null || cf == null) return unsupported(fullExpr, "instance method call");
				// `super.method(...)` calls compile to a synthesized "super thunk" on the current class.
				// This avoids trying to call `Base::method(&RefCell<Base>)` with a `&RefCell<Sub>` receiver.
				if (isSuperExpr(obj)) {
					if (currentClassType == null) return unsupported(fullExpr, "super method call (no class context)");
					var thunk = noteSuperThunk(owner, cf);

					var clsName = classNameFromClass(currentClassType);
					var callArgs: Array<RustExpr> = [EUnary("&", EPath("self_"))];
					var paramDefs: Null<Array<{ name: String, t: Type, opt: Bool }>> = switch (TypeTools.follow(cf.type)) {
						case TFun(params, _): params;
						case _: null;
					};
					for (x in compilePositionalArgsFor(paramDefs)) callArgs.push(x);
					return ECall(EPath(clsName + "::" + thunk), callArgs);
				}
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
						case "blit": {
							if (args.length != 4) return unsupported(fullExpr, "Bytes.blit args");
							var dst = compileExpr(obj);
							var src = compileExpr(args[1]);
							var pos = compileExpr(args[0]);
							var srcpos = compileExpr(args[2]);
							var len = compileExpr(args[3]);
							return ECall(EPath("hxrt::bytes::blit"), [EUnary("&", dst), pos, EUnary("&", src), srcpos, len]);
						}
						case "sub": {
							if (args.length != 2) return unsupported(fullExpr, "Bytes.sub args");
							var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
							var inner = ECall(EField(borrowed, "sub"), [compileExpr(args[0]), compileExpr(args[1])]);
							return ECall(EPath(rcBasePath() + "::new"), [ECall(EPath(refCellBasePath() + "::new"), [inner])]);
						}
						case "getString": {
							// Ignore optional encoding arg for now (must be null / omitted).
							if (args.length != 2 && args.length != 3) return unsupported(fullExpr, "Bytes.getString args");
							var borrowed = ECall(EField(compileExpr(obj), "borrow"), []);
							var call = ECall(EField(borrowed, "get_string"), [compileExpr(args[0]), compileExpr(args[1])]);
							if (args.length == 3) {
								var enc = compileExpr(args[2]);
								return EBlock({ stmts: [RLet("_", false, null, enc)], tail: call });
							}
							return call;
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
								var paramDefs: Null<Array<{ name: String, t: Type, opt: Bool }>> = switch (TypeTools.follow(cf.type)) {
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
								return ECall(EField(recv, rustName), compilePositionalArgsFor(paramDefs));
							}

						// `this` inside concrete methods is always `&RefCell<Concrete>`; keep static dispatch.
						if (!isThisExpr(obj) && (isInterfaceType(obj.t) || isPolymorphicClassType(obj.t))) {
							// Interface/base-typed receiver: dynamic dispatch via trait method call.
							var recv = compileExpr(obj);
							var paramDefs: Null<Array<{ name: String, t: Type, opt: Bool }>> = switch (TypeTools.follow(cf.type)) {
								case TFun(params, _): params;
								case _: null;
							};
							return ECall(EField(recv, rustMethodName(owner, cf)), compilePositionalArgsFor(paramDefs));
						}

						var clsName = classNameFromType(obj.t);
						var objCls: Null<ClassType> = switch (followType(obj.t)) {
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
						if (clsName == null) return unsupported(fullExpr, "instance method call");
						var callArgs: Array<RustExpr> = [EUnary("&", compileExpr(obj))];
						var paramDefs: Null<Array<{ name: String, t: Type, opt: Bool }>> = switch (TypeTools.follow(cf.type)) {
							case TFun(params, _): params;
							case _: null;
						};
						for (x in compilePositionalArgsFor(paramDefs)) callArgs.push(x);
						var rustName = rustMethodName(objCls != null ? objCls : owner, cf);
						return ECall(EPath(clsName + "::" + rustName), callArgs);
					}
					case _:
				}
			}
			case _:
		}

			var overrideArrayFn: Null<RustExpr> = null;
			switch (callExpr.expr) {
				case TField(obj, fa) if (isArrayType(obj.t)): {
					var elem = arrayElementType(obj.t);
					if (isRcBackedType(elem)) {
						var fieldName: Null<String> = switch (fa) {
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
							var refName: Null<String> = switch (fieldName) {
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
			var fnTypeForParams: Type = (nullableFnInner != null ? nullableFnInner : callExpr.t);
			// Prefer the declared field type when available so we don't lose Rusty ref-wrapper types
			// (e.g. `rust.Ref<T>`) via aggressive type following.
			//
			// This is especially important for stdlib helpers like `rust.VecTools.len(get)` which take
			// `Ref<Vec<T>>` and must lower to `&Vec<T>` at call sites.
			if (nullableFnInner == null) {
				switch (callExpr.expr) {
					case TField(_, FStatic(_, fieldRef)): {
						var cf = fieldRef.get();
						if (cf != null) fnTypeForParams = cf.type;
					}
					case TField(_, FAnon(cfRef)): {
						var cf = cfRef.get();
						if (cf != null) fnTypeForParams = cf.type;
					}
					case TField(_, FInstance(_, _, cfRef)): {
						var cf = cfRef.get();
						if (cf != null) fnTypeForParams = cf.type;
					}
					case _:
				}
			}
			function funParamDefs(t: Type): Null<Array<{ name: String, t: Type, opt: Bool }>> {
				return switch (t) {
					case TLazy(f):
						funParamDefs(f());
					case TType(typeRef, params): {
						var tt = typeRef.get();
						if (tt != null) {
							var under: Type = tt.type;
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

			var paramDefs: Null<Array<{ name: String, t: Type, opt: Bool }>> = funParamDefs(fnTypeForParams);

		// Calling `Null<Fn>` values: `opt_fn(args...)` -> `opt_fn.as_ref().unwrap()(args...)`
		if (nullableFnInner != null) {
			switch (TypeTools.follow(nullableFnInner)) {
				case TFun(_, _):
					f = ECall(EField(ECall(EField(f, "as_ref"), []), "unwrap"), []);
				case _:
			}
		}

		var a: Array<RustExpr> = [];
		for (i in 0...args.length) {
			var arg = args[i];
			var compiled = compileExpr(arg);

			if (paramDefs != null && i < paramDefs.length) {
				compiled = coerceArgForParam(compiled, arg, paramDefs[i].t);
			}

			a.push(compiled);
		}

		// Fill omitted optional arguments with their implicit default (`null`).
		// For this target, `null` maps to `None` for `Null<T>` (Option<T>).
		if (paramDefs != null && args.length < paramDefs.length) {
			for (i in args.length...paramDefs.length) {
				if (!paramDefs[i].opt) break;
				var t = paramDefs[i].t;
				var d: RustExpr = isNullType(t) ? ERaw("None") : ERaw(defaultValueForType(t, fullExpr.pos));
				a.push(d);
			}
		}
		return ECall(f, a);
	}

	function coerceArgForParam(compiled: RustExpr, argExpr: TypedExpr, paramType: Type): RustExpr {
		var rustParamTy = toRustType(paramType, argExpr.pos);
		function isCloneExpr(e: RustExpr): Bool {
			return switch (e) {
				case ECall(EField(_, "clone"), []): true;
				case _: false;
			}
		}

		function localReadCount(e: TypedExpr): Null<Int> {
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
		var nullInner = nullInnerType(paramType);
		if (nullInner != null) {
			if (!isNullType(argExpr.t) && !isNullConstExpr(argExpr)) {
				var innerCoerced = coerceArgForParam(compiled, argExpr, nullInner);
				return wrapBorrowIfNeeded(ECall(EPath("Some"), [innerCoerced]), rustParamTy, argExpr);
			}
			return wrapBorrowIfNeeded(compiled, rustParamTy, argExpr);
		}

		// Passing into `Dynamic` should not move the source value (Haxe values are reusable).
		if (isDynamicType(paramType) && !isDynamicType(argExpr.t)) {
			var needsClone = !isCopyType(argExpr.t);
			// Avoid cloning obvious temporaries (literals) that won't be re-used after the call.
			if (needsClone && isStringLiteralExpr(argExpr)) needsClone = false;
			if (needsClone && isArrayLiteralExpr(argExpr)) needsClone = false;
			if (needsClone && !isCloneExpr(compiled)) {
				compiled = ECall(EField(compiled, "clone"), []);
			}
			compiled = ECall(EPath("hxrt::dynamic::from"), [compiled]);
		} else if (isStringType(paramType)) {
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
			}

		// Function values: coerce function items/paths into our function representation.
		// Baseline representation is `std::rc::Rc<dyn Fn(...) -> ...>`.
		switch (followType(paramType)) {
			case TFun(params, ret): {
				function isRcNew(e: RustExpr): Bool {
					var cur = e;
					while (true) {
						switch (cur) {
							case EBlock(b):
								if (b.tail == null) return false;
								cur = b.tail;
								continue;
							case _:
						}
						break;
					}
					return switch (cur) {
						case ECall(EPath(p), _) if (p == rcBasePath() + "::new"): true;
						case _: false;
					};
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

					compiled = ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, body, true)]);
				}
			}
			case _:
		}

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
				else if (key == "rust.MutSlice") "mutslice"
				else null;
			}
			case _:
				null;
		}
	}

		function isDirectRustRefValue(e: TypedExpr): Bool {
			var cur = unwrapMetaParen(e);
			switch (cur.expr) {
				case TCast(inner, _): {
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
					if (toKind != null && fromKind == null) return false;
					return fromKind != null && toKind != null;
				}
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

			function compileTrace(value: TypedExpr): RustExpr {
				// Haxe `trace` uses `Std.string(value)` semantics. Route through `hxrt::dynamic::Dynamic`
				// so formatting matches `Std.string` and `Sys.println`.
				var compiled = compileExpr(value);
				if (isDynamicType(followType(value.t))) {
					// Typed AST may coerce trace args to Dynamic; print that value directly.
					return EMacroCall("println", [ELitString("{}"), compiled]);
				}
				var needsClone = !isCopyType(value.t);
				if (needsClone && isStringLiteralExpr(value)) needsClone = false;
				if (needsClone && isArrayLiteralExpr(value)) needsClone = false;
				if (needsClone) {
					compiled = ECall(EField(compiled, "clone"), []);
				}
				return EMacroCall("println", [ELitString("{}"), ECall(EPath("hxrt::dynamic::from"), [compiled])]);
			}

		function exprUsesThis(e: TypedExpr): Bool {
			var used = false;
			function scan(x: TypedExpr): Void {
				if (used) return;
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
				var owner: Null<ClassType> = switch (followType(obj.t)) {
					case TInst(clsRef, _): clsRef.get();
					case _: null;
				};
				if (owner == null) return unsupported(fullExpr, "closure field (unknown owner)");
				compileInstanceMethodValue(obj, owner, cf, fullExpr);
			}
				case FInstance(clsRef, _, cfRef): {
					var owner = clsRef.get();
					var cf = cfRef.get();
					if (owner == null || cf == null) return unsupported(fullExpr, "instance field");

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
									if (currentClassType == null) return unsupported(fullExpr, "super property read (no class context)");
									var propName = cf.getHaxeName();
									if (propName == null) return unsupported(fullExpr, "super property read (missing name)");
									var getterName = "get_" + propName;
									var getter: Null<ClassField> = null;
									var cur: Null<ClassType> = owner;
									while (cur != null && getter == null) {
										for (f in cur.fields.get()) {
											if (f.getHaxeName() == getterName) {
												switch (f.kind) {
													case FMethod(_): getter = f;
													case _:
												}
												if (getter != null) break;
											}
										}
										cur = cur.superClass != null ? cur.superClass.t.get() : null;
									}
									if (getter == null) return unsupported(fullExpr, "super property read (missing getter)");
									var thunk = noteSuperThunk(owner, getter);
									var clsName = classNameFromClass(currentClassType);
									return ECall(EPath(clsName + "::" + thunk), [EUnary("&", EPath("self_"))]);
								}
							}
							case _:
						}

						var recv = EPath("self_");
						var borrowed = ECall(EField(recv, "borrow"), []);
						var access = EField(borrowed, rustFieldName(currentClassType != null ? currentClassType : owner, cf));
						if (!TypeHelper.isBool(fullExpr.t) && !TypeHelper.isInt(fullExpr.t) && !TypeHelper.isFloat(fullExpr.t)) {
						return ECall(EField(access, "clone"), []);
					}
					return access;
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
			case FDynamic(name): EField(compileExpr(obj), name);
			case _: unsupported(fullExpr, "field");
		}
	}

	function compileInstanceMethodValue(obj: TypedExpr, owner: ClassType, cf: ClassField, fullExpr: TypedExpr): RustExpr {
		// `this.method` inside a concrete method would capture `&RefCell<Self>`; that reference cannot be
		// stored in our baseline `'static` function-value representation (`Rc<dyn Fn...>`).
		//
		// For now we only support binding non-`this` receivers.
		if (isThisExpr(obj)) return unsupported(fullExpr, "method value (this)");

		var sig = switch (TypeTools.follow(cf.type)) {
			case TFun(params, ret): { params: params, ret: ret };
			case _: null;
		};
		if (sig == null) return unsupported(fullExpr, "method value (non-function type)");

		var recvExpr = maybeCloneForReuseValue(compileExpr(obj), obj);
		var recvName = "__recv";

		var argParts: Array<String> = [];
		var callArgs: Array<RustExpr> = [];
		for (i in 0...sig.params.length) {
			var p = sig.params[i];
			var name = "a" + i;
			argParts.push(name + ": " + rustTypeToString(toRustType(p.t, fullExpr.pos)));
			callArgs.push(EPath(name));
		}

		var call: RustExpr = if (isExternInstanceType(obj.t)) {
			ECall(EField(EPath(recvName), rustExternFieldName(cf)), callArgs);
		} else if (isInterfaceType(obj.t) || isPolymorphicClassType(obj.t)) {
			ECall(EField(EPath(recvName), rustMethodName(owner, cf)), callArgs);
		} else {
			var modName = rustModuleNameForClass(owner);
			var path = "crate::" + modName + "::" + rustTypeNameForClass(owner) + "::" + rustMethodName(owner, cf);
			ECall(EPath(path), [EUnary("&", EPath(recvName))].concat(callArgs));
		};

		var isVoid = TypeHelper.isVoid(sig.ret);
		var body: RustBlock = isVoid
			? { stmts: [RSemi(call)], tail: null }
			: { stmts: [], tail: call };

		var fnValue = ECall(EPath(rcBasePath() + "::new"), [EClosure(argParts, body, true)]);
		return EBlock({
			stmts: [RLet(recvName, false, null, recvExpr)],
			tail: fnValue
		});
	}

		function compileInstanceFieldRead(obj: TypedExpr, owner: ClassType, cf: ClassField, fullExpr: TypedExpr): RustExpr {
			function receiverClassForField(obj: TypedExpr, fallback: ClassType): ClassType {
				// In inherited method shims, the typed AST may treat `this` as the base class, but codegen
				// must dispatch against the concrete class being compiled.
				if (isThisExpr(obj) && currentClassType != null) return currentClassType;
				return switch (followType(obj.t)) {
					case TInst(clsRef, _): {
						var cls = clsRef.get();
						cls != null ? cls : fallback;
					}
					case _: fallback;
				}
			}

				function findInstanceMethodInChain(start: ClassType, haxeName: String): Null<ClassField> {
				var cur: Null<ClassType> = start;
				while (cur != null) {
					for (f in cur.fields.get()) {
						if (f.getHaxeName() != haxeName) continue;
						switch (f.kind) {
							case FMethod(_): return f;
							case _:
						}
					}
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
					return null;
				}

				function varHasStorage(prop: ClassField): Bool {
					// `@:isVar` forces storage even when accessors are `get/set`.
					for (m in prop.meta.get()) if (m.name == ":isVar") return true;
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
					case FVar(read, _): {
						if (read == AccCall) {
							var recvCls = receiverClassForField(obj, owner);
							var propName = cf.getHaxeName();
							if (propName == null) return unsupported(fullExpr, "property read (missing name)");
							// Special-case: inside `get_x()` for a storage-backed property (e.g. `default,get`),
							// Haxe treats `x` as a direct read of the backing storage to avoid recursion.
							var skipLower = varHasStorage(cf) && currentMethodField != null && currentMethodField.getHaxeName() == ("get_" + propName);
							if (!skipLower) {
								var getter = findInstanceMethodInChain(recvCls, "get_" + propName);
								if (getter == null) return unsupported(fullExpr, "property read (missing getter)");

								// Polymorphic receivers use trait-object calls.
								if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
									return ECall(EField(compileExpr(obj), rustMethodName(recvCls, getter)), []);
								}

								var modName = rustModuleNameForClass(recvCls);
								var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, getter);
								return ECall(EPath(path), [EUnary("&", compileExpr(obj))]);
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
			var borrowed = ECall(EField(recv, "borrow"), []);
			var access = EField(borrowed, rustFieldName(owner, cf));

		// For non-Copy types, cloning is the simplest POC rule.
		if (!TypeHelper.isBool(fullExpr.t) && !TypeHelper.isInt(fullExpr.t) && !TypeHelper.isFloat(fullExpr.t)) {
			return ECall(EField(access, "clone"), []);
		}

		return access;
	}

		function compileInstanceFieldAssign(obj: TypedExpr, owner: ClassType, cf: ClassField, rhs: TypedExpr): RustExpr {
			function receiverClassForField(obj: TypedExpr, fallback: ClassType): ClassType {
				// In inherited method shims, the typed AST may treat `this` as the base class, but codegen
				// must dispatch against the concrete class being compiled.
				if (isThisExpr(obj) && currentClassType != null) return currentClassType;
				return switch (followType(obj.t)) {
					case TInst(clsRef, _): {
						var cls = clsRef.get();
						cls != null ? cls : fallback;
					}
					case _: fallback;
				}
			}

			function findInstanceMethodInChain(start: ClassType, haxeName: String): Null<ClassField> {
				var cur: Null<ClassType> = start;
				while (cur != null) {
					for (f in cur.fields.get()) {
						if (f.getHaxeName() != haxeName) continue;
						switch (f.kind) {
							case FMethod(_): return f;
							case _:
						}
					}
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
					return null;
				}

				function varHasStorage(prop: ClassField): Bool {
					for (m in prop.meta.get()) if (m.name == ":isVar") return true;
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

				// Property writes (`var x(..., set)`) compile to `set_x(v)` and return the setter's return value.
				switch (cf.kind) {
					case FVar(_, write): {
						if (write == AccCall) {
							var recvCls = receiverClassForField(obj, owner);
							var propName = cf.getHaxeName();
							if (propName == null) return unsupported(rhs, "property write (missing name)");
							// Special-case: inside `set_x()` for a storage-backed property (e.g. `default,set`),
							// Haxe treats `x = v` as a direct write to backing storage to avoid recursion.
							var skipLower = varHasStorage(cf) && currentMethodField != null && currentMethodField.getHaxeName() == ("set_" + propName);
							if (!skipLower) {
								var setter = findInstanceMethodInChain(recvCls, "set_" + propName);
								if (setter == null) return unsupported(rhs, "property write (missing setter)");

								var paramType: Null<Type> = switch (followType(setter.type)) {
									case TFun(params, _):
										(params != null && params.length > 0) ? params[0].t : null;
									case _:
										null;
								};
								if (paramType == null) return unsupported(rhs, "property write (missing setter param)");

								var rhsCompiled = coerceArgForParam(compileExpr(rhs), rhs, paramType);

								// `super.prop = rhs` must call the base setter implementation.
								if (isSuperExpr(obj)) {
									if (currentClassType == null) return unsupported(rhs, "super property write (no class context)");
									var thunk = noteSuperThunk(owner, setter);
									var clsName = classNameFromClass(currentClassType);
									return ECall(EPath(clsName + "::" + thunk), [EUnary("&", EPath("self_")), rhsCompiled]);
								}

								// Polymorphic receivers call through the trait object.
								if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
									return ECall(EField(compileExpr(obj), rustMethodName(recvCls, setter)), [rhsCompiled]);
								}

								var modName = rustModuleNameForClass(recvCls);
								var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
								return ECall(EPath(path), [EUnary("&", compileExpr(obj)), rhsCompiled]);
							}
						}
					}
				case _:
			}

			var fieldIsNull = isNullType(cf.type);
			var rhsIsNullish = isNullType(rhs.t) || isNullConstExpr(rhs);

			if (isSuperExpr(obj)) {
				// `super.field = rhs` assigns into the inherited struct field on the current receiver.
				// `{ let __tmp = rhs; self_.borrow_mut().field = __tmp.clone(); __tmp }`
				var stmts: Array<RustStmt> = [];

			var rhsExpr = compileExpr(rhs);
			rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
			stmts.push(RLet("__tmp", false, null, rhsExpr));

			var borrowed = ECall(EField(EPath("self_"), "borrow_mut"), []);
			var access = EField(borrowed, rustFieldName(currentClassType != null ? currentClassType : owner, cf));
			var rhsVal: RustExpr = isCopyType(rhs.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
			var assigned = (fieldIsNull && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal;
			stmts.push(RSemi(EAssign(access, assigned)));

			return EBlock({ stmts: stmts, tail: EPath("__tmp") });
		}

			if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
				// Haxe assignment returns the RHS value.
				// `{ let __tmp = rhs; obj.__hx_set_field(__tmp.clone()); __tmp }`
				var stmts: Array<RustStmt> = [];
				stmts.push(RLet("__tmp", false, null, compileExpr(rhs)));

				var rhsVal: RustExpr = isCopyType(cf.type) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
				var assigned = (fieldIsNull && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal;
				stmts.push(RSemi(ECall(EField(compileExpr(obj), rustSetterName(owner, cf)), [assigned])));

				return EBlock({ stmts: stmts, tail: EPath("__tmp") });
			}

		// Important: evaluate RHS before taking a mutable borrow to avoid RefCell borrow panics.
		// `{ let __tmp = rhs; obj.borrow_mut().field = __tmp.clone(); __tmp }`
		var stmts: Array<RustStmt> = [];

		var rhsExpr = compileExpr(rhs);
		rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
		stmts.push(RLet("__tmp", false, null, rhsExpr));

		var recv = compileExpr(obj);
		var borrowed = ECall(EField(recv, "borrow_mut"), []);
		var access = EField(borrowed, rustFieldName(owner, cf));
		var rhsVal: RustExpr = isCopyType(rhs.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
		var assigned = (fieldIsNull && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal;
		stmts.push(RSemi(EAssign(access, assigned)));

		return EBlock({
			stmts: stmts,
			tail: EPath("__tmp")
		});
	}

	function compileArrayIndexAssign(arr: TypedExpr, index: TypedExpr, rhs: TypedExpr): RustExpr {
		// Haxe assignment returns the RHS value.
		// `{ let __tmp = rhs; arr.set(idx, __tmp.clone()); __tmp }`
		var stmts: Array<RustStmt> = [];
		var rhsExpr = compileExpr(rhs);
		rhsExpr = maybeCloneForReuseValue(rhsExpr, rhs);
		stmts.push(RLet("__tmp", false, null, rhsExpr));

		var idx = ECast(compileExpr(index), "usize");
		var rhsVal: RustExpr = isCopyType(rhs.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
		stmts.push(RSemi(ECall(EField(compileExpr(arr), "set"), [idx, rhsVal])));

		return EBlock({ stmts: stmts, tail: EPath("__tmp") });
	}

		function classNameFromType(t: Type): Null<String> {
			var ft = TypeTools.follow(t);
			return switch (ft) {
				case TInst(clsRef, _): {
					var cls = clsRef.get();
					if (cls == null) null else if (isMainClass(cls)) rustTypeNameForClass(cls) else ("crate::" + rustModuleNameForClass(cls) + "::" + rustTypeNameForClass(cls));
				}
				case _: null;
			}
		}

	function classNameFromClass(cls: ClassType): String {
		return isMainClass(cls)
			? rustTypeNameForClass(cls)
			: ("crate::" + rustModuleNameForClass(cls) + "::" + rustTypeNameForClass(cls));
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

	function rustImplsFromMeta(meta: haxe.macro.Type.MetaAccess): Array<RustImplSpec> {
		var out: Array<RustImplSpec> = [];

		function unwrap(e: Expr): Expr {
			return switch (e.expr) {
				case EParenthesis(inner): unwrap(inner);
				case EMeta(_, inner): unwrap(inner);
				case _: e;
			}
		}

		function stringConst(e: Expr): Null<String> {
			return switch (unwrap(e).expr) {
				case EConst(CString(s, _)): s;
				case _: null;
			}
		}

		for (entry in meta.get()) {
			if (entry.name != ":rustImpl") continue;

			var pos = entry.pos;
			if (entry.params == null || entry.params.length == 0) {
				#if eval
				Context.error("`@:rustImpl` requires at least one parameter.", pos);
				#end
				continue;
			}

			inline function expectString(v: Dynamic, label: String): Null<String> {
				if (v == null) return null;
				if (Std.isOfType(v, String)) return cast v;
				#if eval
				Context.error("`@:rustImpl` " + label + " must be a string.", pos);
				#end
				return null;
			}

			function addSpec(spec: RustImplSpec): Void {
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
					addSpec({ traitPath: s });
					continue;
				}
				try {
					var v: Dynamic = ExprTools.getValue(entry.params[0]);
					if (Std.isOfType(v, String)) {
						addSpec({ traitPath: cast v });
						continue;
					}
					var traitPath = expectString(Reflect.field(v, "trait"), "field `trait`");
					var forType = expectString(Reflect.field(v, "forType"), "field `forType`");
					var body = expectString(Reflect.field(v, "body"), "field `body`");
					if (traitPath != null) {
						var spec: RustImplSpec = { traitPath: traitPath };
						if (forType != null) spec.forType = forType;
						if (body != null) spec.body = body;
						addSpec(spec);
						continue;
					}
				} catch (_: Dynamic) {}

				#if eval
				Context.error("`@:rustImpl` must be a compile-time constant string or object.", pos);
				#end
				continue;
			}

			if (entry.params.length >= 2) {
				var traitPath: Null<String> = null;
				var body: Null<String> = null;
				traitPath = stringConst(entry.params[0]);
				body = stringConst(entry.params[1]);
				if (traitPath != null) {
					var spec: RustImplSpec = { traitPath: traitPath };
					if (body != null) spec.body = body;
					addSpec(spec);
					continue;
				}
				try {
					var v0: Dynamic = ExprTools.getValue(entry.params[0]);
					var v1: Dynamic = ExprTools.getValue(entry.params[1]);
					traitPath = expectString(v0, "trait path");
					body = expectString(v1, "body");
				} catch (_: Dynamic) {}
				if (traitPath == null) {
					#if eval
					Context.error("`@:rustImpl` first parameter must be a compile-time string trait path.", pos);
					#end
					continue;
				}
				var spec: RustImplSpec = { traitPath: traitPath };
				if (body != null) spec.body = body;
				addSpec(spec);
				continue;
			}
		}

		// Stable ordering for snapshots.
		out.sort((a, b) -> Reflect.compare(a.traitPath, b.traitPath));
		return out;
	}

	function renderRustImplBlock(spec: RustImplSpec, implGenerics: Array<String>, forType: String): String {
		var header = "impl";
		if (implGenerics != null && implGenerics.length > 0) header += "<" + implGenerics.join(", ") + ">";
		header += " " + spec.traitPath + " for " + (spec.forType != null ? spec.forType : forType) + " {";

		var lines: Array<String> = [header];
		var body = spec.body;
		if (body != null) {
			var trimmed = StringTools.trim(body);
			if (trimmed.length > 0) {
				for (l in body.split("\n")) lines.push("\t" + l);
			}
		}
		lines.push("}");
		return lines.join("\n");
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
		var traitName = rustTypeNameForClass(classType) + "Trait";
		var generics = rustGenericDeclsForClass(classType);
		var genericSuffix = generics.length > 0 ? "<" + generics.join(", ") + ">" : "";
		var lines: Array<String> = [];
		lines.push("pub trait " + traitName + genericSuffix + " {");

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
			var traitPathBase = "crate::" + modName + "::" + rustTypeNameForClass(classType) + "Trait";
			var rustSelfType = rustTypeNameForClass(classType);
			var rustSelfInst = rustClassTypeInst(classType);
			var generics = rustGenericDeclsForClass(classType);
			var genericNames = rustGenericNamesFromDecls(generics);
			var turbofish = genericNames.length > 0 ? ("::<" + genericNames.join(", ") + ">") : "";
			var traitArgs = genericNames.length > 0 ? "<" + genericNames.join(", ") + ">" : "";
			var implGenerics = generics.length > 0 ? "<" + generics.join(", ") + ">" : "";

			var lines: Array<String> = [];
			lines.push("impl" + implGenerics + " " + traitPathBase + traitArgs + " for " + refCellBasePath() + "<" + rustSelfInst + "> {");

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
				lines.push("\t\t" + rustSelfType + turbofish + "::" + rustName + "(" + callArgs.join(", ") + ")");
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
			var baseTraitPathBase = "crate::" + baseMod + "::" + rustTypeNameForClass(baseType) + "Trait";
			var rustSubType = rustTypeNameForClass(subType);
			var rustSubInst = rustClassTypeInst(subType);
			var subGenerics = rustGenericDeclsForClass(subType);
			var subGenericNames = rustGenericNamesFromDecls(subGenerics);
			var subTurbofish = subGenericNames.length > 0 ? ("::<" + subGenericNames.join(", ") + ">") : "";
			var subImplGenerics = subGenerics.length > 0 ? "<" + subGenerics.join(", ") + ">" : "";

			function findSuperParams(sub: ClassType, base: ClassType): Array<Type> {
				var cur: Null<ClassType> = sub;
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
			var baseTraitArgs = baseArgs.length > 0
				? ("<" + [for (p in baseArgs) rustTypeToString(toRustType(p, subType.pos))].join(", ") + ">")
				: "";

		var overrides = new Map<String, ClassFuncData>();
		for (f in subFuncFields) {
			if (f.isStatic) continue;
			if (f.field.getHaxeName() == "new") continue;
			if (f.expr == null) continue;
			overrides.set(f.field.getHaxeName() + "/" + f.args.length, f);
		}

			var lines: Array<String> = [];
			lines.push("impl" + subImplGenerics + " " + baseTraitPathBase + baseTraitArgs + " for " + refCellBasePath() + "<" + rustSubInst + "> {");

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

		// Base traits include inherited methods (see `emitClassTrait` using `effectiveFuncFields`).
		// Implement the same surface here: baseType declared methods with bodies plus inherited base bodies.
		var baseTraitMethods: Array<ClassField> = [];
		var baseTraitSeen: Map<String, Bool> = [];

		function considerBaseTraitMethod(cf: ClassField): Void {
			if (cf.getHaxeName() == "new") return;
			switch (cf.kind) {
				case FMethod(_):
					var ft = followType(cf.type);
					var argc = switch (ft) {
						case TFun(a, _): a.length;
						case _: 0;
					};
					var key = cf.getHaxeName() + "/" + argc;
					if (baseTraitSeen.exists(key)) return;
					// Only include methods that actually have bodies; abstract/extern methods are not part of base traits yet.
					if (cf.expr() == null) return;
					baseTraitSeen.set(key, true);
					baseTraitMethods.push(cf);
				case _:
			}
		}

		for (cf in baseType.fields.get()) considerBaseTraitMethod(cf);
		var curBase: Null<ClassType> = baseType.superClass != null ? baseType.superClass.t.get() : null;
		while (curBase != null) {
			for (cf in curBase.fields.get()) considerBaseTraitMethod(cf);
			curBase = curBase.superClass != null ? curBase.superClass.t.get() : null;
		}

		function baseTraitKey(cf: ClassField): String {
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
								lines.push("\t\t" + rustSubType + subTurbofish + "::" + rustMethodName(subType, overrideFunc.field) + "(" + callArgs.join(", ") + ")");
							} else {
								// Stub: keep signatures warning-free under `#![deny(warnings)]`.
								// `_` patterns avoid `unused_variables` even when the body is `todo!()`.
								lines.pop();
								var stubSigArgs: Array<String> = ["&self"];
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

		function isPhysicalVarField(cls: ClassType, cf: ClassField): Bool {
			// Haxe `var x(get,set)` style properties are not stored fields unless explicitly marked `@:isVar`
			// or declared with default-like access (e.g. `default`, `null`, `ctor`).
			if (cf.meta != null && cf.meta.has(":isVar")) return true;
			return switch (cf.kind) {
				case FVar(read, write):
					switch ([read, write]) {
						case [AccNormal | AccNo | AccCtor, _]: true;
						case [_, AccNormal | AccNo | AccCtor]: true;
						case _: false;
					}
				case _:
					false;
			};
		}

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
						if (!isPhysicalVarField(cls, cf)) continue;
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

	function unwrapFieldFunctionBody(ex: TypedExpr): TypedExpr {
		// ClassField.expr() returns a `TFunction` for methods; we want the body expression.
		return switch (ex.expr) {
			case TFunction(fn): fn.expr;
			case _: ex;
		};
	}

	function collectInheritedInstanceMethodShims(classType: ClassType, funcFields: Array<ClassFuncData>): Array<{ owner: ClassType, f: ClassFuncData }> {
		// We only need to synthesize methods that have bodies on a base class and are not
		// overridden in `classType`. This allows concrete dispatch on the subclass and
		// avoids `todo!()` stubs in base trait impls for subclasses.
		var out: Array<{ owner: ClassType, f: ClassFuncData }> = [];

		var implemented: Map<String, Bool> = [];
		for (f in funcFields) {
			if (f.isStatic) continue;
			if (f.field.getHaxeName() == "new") continue;
			if (f.expr == null) continue;
			implemented.set(f.field.getHaxeName() + "/" + f.args.length, true);
		}

		function buildFrom(owner: ClassType, cf: ClassField, body: TypedExpr): Null<{ owner: ClassType, f: ClassFuncData }> {
			var ft = followType(cf.type);
			var sig = switch (ft) {
				case TFun(args, ret): { args: args, ret: ret };
				case _: null;
			};
			if (sig == null) return null;

			var args: Array<ClassFuncArg> = [];
			for (i in 0...sig.args.length) {
				var a = sig.args[i];
				var baseName = a.name != null && a.name.length > 0 ? a.name : ("a" + i);
				args.push(new ClassFuncArg(i, a.t, a.opt, baseName));
			}

			var kind: MethodKind = switch (cf.kind) {
				case FMethod(k): k;
				case _: MethNormal;
			};

			var id = classKey(classType) + " inherited " + classKey(owner) + " " + cf.getHaxeName() + "/" + args.length;
			var data = new ClassFuncData(id, classType, cf, false, kind, sig.ret, args, null, body, false, null);
			for (a in args) a.setFuncData(data);
			return { owner: owner, f: data };
		}

		// Walk nearest base first so overrides in closer bases win.
		var cur: Null<ClassType> = classType.superClass != null ? classType.superClass.t.get() : null;
		while (cur != null) {
			for (cf in cur.fields.get()) {
				if (cf.getHaxeName() == "new") continue;
				switch (cf.kind) {
					case FMethod(_): {
						var ex = cf.expr();
						if (ex == null) continue;
						var body = unwrapFieldFunctionBody(ex);

						var ft = followType(cf.type);
						var argc = switch (ft) {
							case TFun(args, _): args.length;
							case _: 0;
						};
						var key = cf.getHaxeName() + "/" + argc;
						if (implemented.exists(key)) continue;

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

	function compileBinop(op: Binop, e1: TypedExpr, e2: TypedExpr, fullExpr: TypedExpr): RustExpr {
		return switch (op) {
			case OpAssign:
				switch (e1.expr) {
					case TLocal(v) if (isNullType(v.t) && !isNullType(e2.t) && !isNullConstExpr(e2)): {
						// Assignment to `Null<T>` (Option<T>) from a non-null `T`:
						// `{ let __tmp = rhs; lhs = Some(__tmp.clone()); __tmp }`
						var stmts: Array<RustStmt> = [];
						stmts.push(RLet("__tmp", false, null, compileExpr(e2)));

						var rhsVal: RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
						var wrapped = ECall(EPath("Some"), [rhsVal]);
						stmts.push(RSemi(EAssign(compileExpr(e1), wrapped)));

						return EBlock({ stmts: stmts, tail: EPath("__tmp") });
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
						if (cf == null) return unsupported(fullExpr, "anon field assign");

						var fieldIsNull = isNullType(cf.type);
						var rhsIsNullish = isNullType(e2.t) || isNullConstExpr(e2);

						function typedNoneForNull(t: Type, pos: haxe.macro.Expr.Position): RustExpr {
							var inner = nullInnerType(t);
							if (inner == null) return ERaw("None");
							var innerRust = rustTypeToString(toRustType(inner, pos));
							return ERaw("Option::<" + innerRust + ">::None");
						}

						var stmts: Array<RustStmt> = [];

						// Evaluate receiver once (and clone locals to avoid moves).
						stmts.push(RLet("__obj", false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));

						// Evaluate RHS before taking a mutable borrow.
						var rhsExpr = if (isNullConstExpr(e2) && isNullType(e2.t)) typedNoneForNull(e2.t, e2.pos) else maybeCloneForReuseValue(compileExpr(e2), e2);
						stmts.push(RLet("__tmp", false, null, rhsExpr));

						var rhsVal: RustExpr = isCopyType(e2.t) ? EPath("__tmp") : ECall(EField(EPath("__tmp"), "clone"), []);
						var assigned = (fieldIsNull && !rhsIsNullish) ? ECall(EPath("Some"), [rhsVal]) : rhsVal;

						var borrowed = ECall(EField(EPath("__obj"), "borrow_mut"), []);
						var setCall = ECall(EField(borrowed, "set"), [ELitString(cf.getHaxeName()), assigned]);
						stmts.push(RSemi(setCall));

						return EBlock({ stmts: stmts, tail: EPath("__tmp") });
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
						function collectParts(e: TypedExpr, out: Array<TypedExpr>): Void {
							var u = unwrapMetaParen(e);
							switch (u.expr) {
								case TBinop(OpAdd, a, b) if (isStringType(followType(u.t))):
									collectParts(a, out);
									collectParts(b, out);
								case _:
									out.push(e);
							}
						}

						var parts: Array<TypedExpr> = [];
						collectParts(fullExpr, parts);

						// Prefer borrowing `String`-typed values as `&String` inside `format!` to avoid
						// intermediate `String::clone()` allocations when all we need is to format into a
						// new output string.
						//
						// Additionally, emit string literals as `&'static str` (no `String::from`) inside
						// `format!` args to reduce heap allocation noise.
						function formatArg(p: TypedExpr): RustExpr {
							if (!isStringType(followType(p.t))) return compileExpr(p);

							var u = unwrapMetaParen(p);
							switch (u.expr) {
								case TConst(TString(s)):
									return ELitString(s);
								case TLocal(_):
									return EUnary("&", compileExpr(p));
								case TField(obj, FInstance(clsRef, _, cfRef)): {
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
						for (_ in 0...parts.length) fmt += "{}";

						var args: Array<RustExpr> = [ELitString(fmt)];
						for (p in parts) args.push(formatArg(p));
						EMacroCall("format", args);
					} else {
						EBinary("+", compileExpr(e1), compileExpr(e2));
					}

			case OpSub: EBinary("-", compileExpr(e1), compileExpr(e2));
			case OpMult: EBinary("*", compileExpr(e1), compileExpr(e2));
			case OpDiv: EBinary("/", compileExpr(e1), compileExpr(e2));
			case OpMod: EBinary("%", compileExpr(e1), compileExpr(e2));

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
					// `Null<T>` compares to `null` should not require `T: PartialEq` (e.g. `Null<Fn>`).
					if (isNullType(e1.t) && isNullConstExpr(e2)) {
						ECall(EField(compileExpr(e1), "is_none"), []);
					} else if (isNullType(e2.t) && isNullConstExpr(e1)) {
						ECall(EField(compileExpr(e2), "is_none"), []);
					} else {
						var ft1 = followType(e1.t);
						var ft2 = followType(e2.t);

						// Haxe object/array equality is identity-based.
						if (isArrayType(ft1) && isArrayType(ft2)) {
							ECall(EField(compileExpr(e1), "ptr_eq"), [EUnary("&", compileExpr(e2))]);
							} else if (isRcBackedType(ft1) && isRcBackedType(ft2)) {
								ECall(EPath(rcBasePath() + "::ptr_eq"), [EUnary("&", compileExpr(e1)), EUnary("&", compileExpr(e2))]);
							} else {
								EBinary("==", compileExpr(e1), compileExpr(e2));
							}
						}
					}
					case OpNotEq: {
					if (isNullType(e1.t) && isNullConstExpr(e2)) {
						ECall(EField(compileExpr(e1), "is_some"), []);
					} else if (isNullType(e2.t) && isNullConstExpr(e1)) {
						ECall(EField(compileExpr(e2), "is_some"), []);
					} else {
						var ft1 = followType(e1.t);
						var ft2 = followType(e2.t);

						if (isArrayType(ft1) && isArrayType(ft2)) {
							EUnary("!", ECall(EField(compileExpr(e1), "ptr_eq"), [EUnary("&", compileExpr(e2))]));
							} else if (isRcBackedType(ft1) && isRcBackedType(ft2)) {
								EUnary("!", ECall(EPath(rcBasePath() + "::ptr_eq"), [EUnary("&", compileExpr(e1)), EUnary("&", compileExpr(e2))]));
							} else {
								EBinary("!=", compileExpr(e1), compileExpr(e2));
							}
						}
					}
			case OpLt: EBinary("<", compileExpr(e1), compileExpr(e2));
			case OpLte: EBinary("<=", compileExpr(e1), compileExpr(e2));
			case OpGt: EBinary(">", compileExpr(e1), compileExpr(e2));
			case OpGte: EBinary(">=", compileExpr(e1), compileExpr(e2));
			case OpBoolAnd: EBinary("&&", compileExpr(e1), compileExpr(e2));
			case OpBoolOr: EBinary("||", compileExpr(e1), compileExpr(e2));

			case OpInterval:
				ERange(compileExpr(e1), compileExpr(e2));

				case OpAssignOp(inner): {
					// Compound assignments (`x += y`, `x %= y`, ...).
					//
					// POC: support locals (common in loops/desugarings). More complex lvalues
					// (fields/indices) can be added when needed.
				var opStr: Null<String> = switch (inner) {
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
				if (opStr == null) return unsupported(fullExpr, "assignop" + Std.string(inner));

				switch (e1.expr) {
					case TLocal(_): {
						// `{ x = x <op> rhs; x }`
						var lhs = compileExpr(e1);
						var rhs = compileExpr(e2);
						EBlock({
							stmts: [RSemi(EAssign(lhs, EBinary(opStr, lhs, rhs)))],
							tail: lhs
						});
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

						var stmts: Array<RustStmt> = [];
						stmts.push(RLet(arrName, false, null, maybeCloneForReuseValue(compileExpr(arr), arr)));
						stmts.push(RLet(idxName, false, null, ECast(compileExpr(index), "usize")));
						stmts.push(RLet(rhsName, false, null, compileExpr(e2)));

						var read = ECall(EField(EPath(arrName), "get_unchecked"), [EPath(idxName)]);
						stmts.push(RLet(tmpName, false, null, EBinary(opStr, read, EPath(rhsName))));
						stmts.push(RSemi(ECall(EField(EPath(arrName), "set"), [EPath(idxName), EPath(tmpName)])));

						EBlock({ stmts: stmts, tail: EPath(tmpName) });
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

									var read: Null<VarAccess> = null;
									var write: Null<VarAccess> = null;
									switch (cf.kind) {
										case FVar(r, w):
											read = r;
											write = w;
										case _:
									}

									function receiverClassForField(obj: TypedExpr, fallback: ClassType): ClassType {
										if (isThisExpr(obj) && currentClassType != null) return currentClassType;
										return switch (followType(obj.t)) {
											case TInst(cls2Ref, _): {
												var cls2 = cls2Ref.get();
												cls2 != null ? cls2 : fallback;
											}
											case _: fallback;
										}
									}

									function findInstanceMethodInChain(start: ClassType, haxeName: String): Null<ClassField> {
										var cur: Null<ClassType> = start;
										while (cur != null) {
											for (f in cur.fields.get()) {
												if (f.getHaxeName() != haxeName) continue;
												switch (f.kind) {
													case FMethod(_): return f;
													case _:
												}
											}
											cur = cur.superClass != null ? cur.superClass.t.get() : null;
										}
										return null;
									}

									function getterCall(recvCls: ClassType, recvExpr: RustExpr): RustExpr {
										var propName = cf.getHaxeName();
										if (propName == null) return unsupported(fullExpr, "assignop property read (missing name)");
										var getter = findInstanceMethodInChain(recvCls, "get_" + propName);
										if (getter == null) return unsupported(fullExpr, "assignop property read (missing getter)");
										if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
											return ECall(EField(recvExpr, rustMethodName(recvCls, getter)), []);
										}
										var modName = rustModuleNameForClass(recvCls);
										var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, getter);
										return ECall(EPath(path), [EUnary("&", recvExpr)]);
									}

									function setterCall(recvCls: ClassType, recvExpr: RustExpr, value: RustExpr): RustExpr {
										var propName = cf.getHaxeName();
										if (propName == null) return unsupported(fullExpr, "assignop property write (missing name)");
										var setter = findInstanceMethodInChain(recvCls, "set_" + propName);
										if (setter == null) return unsupported(fullExpr, "assignop property write (missing setter)");
										if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
											return ECall(EField(recvExpr, rustMethodName(recvCls, setter)), [value]);
										}
										var modName = rustModuleNameForClass(recvCls);
										var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
										return ECall(EPath(path), [EUnary("&", recvExpr), value]);
									}

									var recvName = "__hx_obj";
									var recvExpr: RustExpr = isThisExpr(obj) ? EPath("self_") : EPath(recvName);

									var fieldName = rustFieldName(owner, cf);
									var rhsName = "__rhs";
									var tmpName = "__tmp";

									var stmts: Array<RustStmt> = [];
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
										var curVal = (read == AccCall) ? getterCall(recvCls, recvExpr) : EField(ECall(EField(recvExpr, "borrow"), []), fieldName);
										stmts.push(RLet(tmpName, false, null, EBinary(opStr, curVal, EPath(rhsName))));
										var assigned = (write == AccCall)
											? setterCall(recvCls, recvExpr, EPath(tmpName))
											: EBlock({
												stmts: [RSemi(EAssign(EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName), EPath(tmpName)))],
												tail: EPath(tmpName)
											});
										stmts.push(RLet("__assigned", false, null, assigned));
										return EBlock({ stmts: stmts, tail: EPath("__assigned") });
									} else {
										if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
											return unsupported(fullExpr, "assignop field lvalue (polymorphic)");
										}
										var read = EField(ECall(EField(recvExpr, "borrow"), []), fieldName);
										var rhs = EPath(rhsName);
										stmts.push(RLet(tmpName, false, null, EBinary(opStr, read, rhs)));

										var writeField = EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName);
										stmts.push(RSemi(EAssign(writeField, EPath(tmpName))));

										return EBlock({ stmts: stmts, tail: EPath(tmpName) });
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
							if (cf == null) return unsupported(fullExpr, "assignop anon field lvalue (missing field)");
							var fieldName = cf.getHaxeName();

							var recvName = "__hx_obj";
							var rhsName = "__rhs";
							var tmpName = "__tmp";

							var stmts: Array<RustStmt> = [];
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

							EBlock({ stmts: stmts, tail: EPath(tmpName) });
						}
						case _:
							unsupported(fullExpr, "assignop lvalue");
					}
				}

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

						case TField(obj, FInstance(clsRef, _, cfRef)): {
						var owner = clsRef.get();
						var cf = cfRef.get();
						switch (cf.kind) {
							case FVar(_, _): {
								// Properties (`var x(get,set)` / mixed `default,set`) must go through accessors.
								var read: Null<VarAccess> = null;
								var write: Null<VarAccess> = null;
								switch (cf.kind) {
									case FVar(r, w):
										read = r;
										write = w;
									case _:
								}

								function receiverClassForField(obj: TypedExpr, fallback: ClassType): ClassType {
									if (isThisExpr(obj) && currentClassType != null) return currentClassType;
									return switch (followType(obj.t)) {
										case TInst(cls2Ref, _): {
											var cls2 = cls2Ref.get();
											cls2 != null ? cls2 : fallback;
										}
										case _: fallback;
									}
								}

								function findInstanceMethodInChain(start: ClassType, haxeName: String): Null<ClassField> {
									var cur: Null<ClassType> = start;
									while (cur != null) {
										for (f in cur.fields.get()) {
											if (f.getHaxeName() != haxeName) continue;
											switch (f.kind) {
												case FMethod(_): return f;
												case _:
											}
										}
										cur = cur.superClass != null ? cur.superClass.t.get() : null;
									}
									return null;
								}

								function readValue(recvCls: ClassType, recvExpr: RustExpr): RustExpr {
									if (read == AccCall) {
										var propName = cf.getHaxeName();
										if (propName == null) return unsupported(fullExpr, "property unop read (missing name)");
										var getter = findInstanceMethodInChain(recvCls, "get_" + propName);
										if (getter == null) return unsupported(fullExpr, "property unop read (missing getter)");
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

								function writeValue(recvCls: ClassType, recvExpr: RustExpr, value: RustExpr): RustExpr {
									if (write == AccCall) {
										var propName = cf.getHaxeName();
										if (propName == null) return unsupported(fullExpr, "property unop write (missing name)");
										var setter = findInstanceMethodInChain(recvCls, "set_" + propName);
										if (setter == null) return unsupported(fullExpr, "property unop write (missing setter)");
										if (!isThisExpr(obj) && isPolymorphicClassType(obj.t)) {
											return ECall(EField(recvExpr, rustMethodName(recvCls, setter)), [value]);
										}
										var modName = rustModuleNameForClass(recvCls);
										var path = "crate::" + modName + "::" + rustTypeNameForClass(recvCls) + "::" + rustMethodName(recvCls, setter);
										return ECall(EPath(path), [EUnary("&", recvExpr), value]);
									}
									var fieldName = rustFieldName(owner, cf);
									var writeField = EField(ECall(EField(recvExpr, "borrow_mut"), []), fieldName);
									return EBlock({ stmts: [RSemi(EAssign(writeField, value))], tail: value });
								}

								// If either side uses accessors, treat as a property-like operation.
								var usesAccessors = (read == AccCall) || (write == AccCall);
								if (usesAccessors) {
									if (!isCopyType(expr.t)) {
										return unsupported(fullExpr, (postFix ? "postfix" : "prefix") + " property unop (non-copy)");
									}

									var recvCls = receiverClassForField(obj, owner);
									var recvName = "__hx_obj";
									var recvExpr: RustExpr = isThisExpr(obj) ? EPath("self_") : EPath(recvName);
									var delta: RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
									var binop = (op == OpIncrement) ? "+" : "-";

									var stmts: Array<RustStmt> = [];
									if (!isThisExpr(obj)) {
										var base = compileExpr(obj);
										stmts.push(RLet(recvName, false, null, ECall(EField(base, "clone"), [])));
									}

									if (postFix) {
										stmts.push(RLet("__tmp", false, null, readValue(recvCls, recvExpr)));
										stmts.push(RLet("__new", false, null, EBinary(binop, EPath("__tmp"), delta)));
										stmts.push(RLet("_", false, null, writeValue(recvCls, recvExpr, EPath("__new"))));
										return EBlock({ stmts: stmts, tail: EPath("__tmp") });
									} else {
										stmts.push(RLet("__new", false, null, EBinary(binop, readValue(recvCls, recvExpr), delta)));
										stmts.push(RLet("__tmp", false, null, writeValue(recvCls, recvExpr, EPath("__new"))));
										return EBlock({ stmts: stmts, tail: EPath("__tmp") });
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
							var recvExpr: RustExpr = if (isThisExpr(obj)) {
								EPath("self_");
							} else {
								EPath(recvName);
							}

							var fieldName = rustFieldName(owner, cf);
							var delta: RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
							var binop = (op == OpIncrement) ? "+" : "-";

							var borrowRead = ECall(EField(recvExpr, "borrow"), []);
							var readField = EField(borrowRead, fieldName);

							var stmts: Array<RustStmt> = [];
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
								return EBlock({ stmts: stmts, tail: EPath("__tmp") });
							} else {
								stmts.push(RLet("__tmp", false, null, EBinary(binop, readField, delta)));
								var borrowWrite = ECall(EField(recvExpr, "borrow_mut"), []);
								var writeField = EField(borrowWrite, fieldName);
								stmts.push(RSemi(EAssign(writeField, EPath("__tmp"))));
								return EBlock({ stmts: stmts, tail: EPath("__tmp") });
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
						if (cf == null) return unsupported(fullExpr, "anon field unop (missing field)");
						var fieldName = cf.getHaxeName();

						var recvName = "__hx_obj";
						var tyStr = rustTypeToString(toRustType(cf.type, fullExpr.pos));
						var getter = "get::<" + tyStr + ">";

						var delta: RustExpr = TypeHelper.isFloat(expr.t) ? ELitFloat(1.0) : ELitInt(1);
						var binop = (op == OpIncrement) ? "+" : "-";

						var stmts: Array<RustStmt> = [];
						stmts.push(RLet(recvName, false, null, maybeCloneForReuseValue(compileExpr(obj), obj)));

						function readField(): RustExpr {
							var borrowRead = ECall(EField(EPath(recvName), "borrow"), []);
							return ECall(EField(borrowRead, getter), [ELitString(fieldName)]);
						}

						function writeField(value: RustExpr): RustStmt {
							var borrowWrite = ECall(EField(EPath(recvName), "borrow_mut"), []);
							return RSemi(ECall(EField(borrowWrite, "set"), [ELitString(fieldName), value]));
						}

						if (postFix) {
							stmts.push(RLet("__tmp", false, null, readField()));
							stmts.push(RLet("__new", false, null, EBinary(binop, EPath("__tmp"), delta)));
							stmts.push(writeField(EPath("__new")));
							return EBlock({ stmts: stmts, tail: EPath("__tmp") });
						} else {
							stmts.push(RLet("__tmp", false, null, EBinary(binop, readField(), delta)));
							stmts.push(writeField(EPath("__tmp")));
							return EBlock({ stmts: stmts, tail: EPath("__tmp") });
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
		// Haxe `Null<T>` in Rust output is represented by `Option<T>`.
		//
		// IMPORTANT: detect this on the *raw* type before `TypeTools.follow` potentially erases the
		// wrapper (some follow variants will eagerly follow abstracts).
		switch (t) {
			case TAbstract(absRef, params): {
				var abs = absRef.get();
				if (abs != null && abs.module == "StdTypes" && abs.name == "Null" && params.length == 1) {
					// Collapse nested nullability (`Null<Null<T>>` == `Null<T>` in practice).
					var innerType: Type = params[0];
					while (true) {
						var n = nullInnerType(innerType);
						if (n == null) break;
						innerType = n;
					}
					var inner = toRustType(innerType, pos);
					return RPath("Option<" + rustTypeToString(inner) + ">");
				}
			}
			case _:
		}

		var base = TypeTools.follow(t);
		// Expand typedefs explicitly (e.g. `Iterable<T>`, `Iterator<T>`, many std typedef helpers).
		// `TypeTools.follow` doesn't always erase `TType` in practice (notably in macro/std contexts),
		// so handle it here to keep type mapping predictable.
		switch (base) {
			case TType(typeRef, params): {
				var tt = typeRef.get();
				if (tt != null) {
					var under: Type = tt.type;
					if (tt.params != null && tt.params.length > 0 && params != null && params.length == tt.params.length) {
						under = TypeTools.applyTypeParameters(under, tt.params, params);
					}
					return toRustType(under, pos);
				}
			}
			case _:
		}
		if (TypeHelper.isVoid(t)) return RUnit;
		if (TypeHelper.isBool(t)) return RBool;
		if (TypeHelper.isInt(t)) return RI32;
		if (TypeHelper.isFloat(t)) return RF64;
		if (isStringType(base)) return RString;

		var ft = followType(base);

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
				return RPath(rcBasePath() + "<" + sig + ">");
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
				if (key == "rust.MutSlice" && params.length == 1) {
					var inner = toRustType(params[0], pos);
					return RRef(RPath("[" + rustTypeToString(inner) + "]"), true);
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

		// StdTypes: Iterator<T> / KeyValueIterator<K,V> are typedefs to structural types.
		// We lower them to owned Rust iterators for codegen simplicity (primarily used in `for` loops).
		//
		// Documented limitation: manually calling `.hasNext()` / `.next()` on these iterators is not
		// guaranteed to work; prefer `for (x in ...)`.
		switch (ft) {
			case TAnonymous(anonRef): {
				var anon = anonRef.get();
				if (anon != null && anon.fields != null && anon.fields.length == 2) {
					var hasNext: Null<ClassField> = null;
					var next: Null<ClassField> = null;
					var keyField: Null<ClassField> = null;
					var valueField: Null<ClassField> = null;

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
						var nextRet: Type = switch (followType(next.type)) {
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
					var errT = params.length >= 2 ? toRustType(params[1], pos) : RString;
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
				var typeParams = params != null && params.length > 0 ? ("<" + [for (p in params) rustTypeToString(toRustType(p, pos))].join(", ") + ">") : "";
				if (cls.isInterface) {
					var modName = rustModuleNameForClass(cls);
					RPath(rcBasePath() + "<dyn crate::" + modName + "::" + rustTypeNameForClass(cls) + typeParams + ">");
					} else if (classHasSubclasses(cls)) {
						var modName = rustModuleNameForClass(cls);
						RPath(rcBasePath() + "<dyn crate::" + modName + "::" + rustTypeNameForClass(cls) + "Trait" + typeParams + ">");
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

	function isCopyType(t: Type): Bool {
		var ft = followType(t);
		return TypeHelper.isBool(ft) || TypeHelper.isInt(ft) || TypeHelper.isFloat(ft);
	}

	function isDynamicType(t: Type): Bool {
		return switch (followType(t)) {
			case TDynamic(_): true;
			case TAbstract(absRef, _): {
				var abs = absRef.get();
				abs != null && abs.module == "StdTypes" && abs.name == "Dynamic";
			}
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

		function isHxRefValueType(t: Type): Bool {
			if (isBytesType(t)) return true;
			var ft = followType(t);
			return switch (ft) {
				case TInst(clsRef, _): {
					var cls = clsRef.get();
					if (cls == null) return false;
					// Arrays are represented as `hxrt::array::Array<T>`, not `HxRef<_>`.
					if (cls.pack.length == 0 && cls.module == "Array" && cls.name == "Array") return false;
					!cls.isExtern && !cls.isInterface;
				}
				case _:
					false;
			}
		}

		function isRcBackedType(t: Type): Bool {
			// Concrete classes / Bytes are `HxRef<T>` (Rc-backed).
			// Interfaces and polymorphic base classes are `Rc<dyn Trait>` (Rc-backed).
			return isHxRefValueType(t) || isAnonObjectType(t) || isInterfaceType(t) || isPolymorphicClassType(t);
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
