package reflaxe.rust.macros;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.rust.ProfileResolver;
import reflaxe.rust.RustDiagnostic;
import reflaxe.rust.RustDiagnostic.RustDiagnosticId;
import reflaxe.rust.RustProfile;
import reflaxe.rust.analyze.RustRawInjectionAuthorityAnalyzer;

/**
 * StrictModeEnforcer
 *
 * WHAT
 * - Adds an opt-in safety profile for Haxe→Rust projects.
 * - When enabled, rejects `__rust__()` code injection in project sources.
 *
 * WHY
 * - Keep application code Haxe-first and structurally analyzable.
 * - Make "escape hatch" usage explicit and easy to ban in production builds.
 *
 * HOW
 * - Enable with `-D reflaxe_rust_strict` in the user's `.hxml`.
 * - Scans project-local sources (under current working directory), excluding framework sources
 *   via resolved root paths (not substring path checks).
 * - `@:rustAllowRaw` can authorize one tagged module/type as a narrow raw-injection authority
 *   island under strict mode.
 *
 * Metal profile note
 * - `reflaxe_rust_profile=metal` enables strict mode by default in `CompilerInit`.
 * - In metal mode we still reject raw project-side `__rust__`, but allow framework-origin
 *   typed wrappers (for example macro facades in `src/reflaxe/rust/macros` and `std/rust/metal`).
 * - `@:rustAllowRaw` does not bypass metal-clean enforcement; raw fallback is still rejected later
 *   by `MetalRestrictionsPass`.
 */
class StrictModeEnforcer {
	public static function init():Void {
		if (!isRustBuild())
			return;
		if (!Context.defined("reflaxe_rust_strict"))
			return;

		var projectRoot = normalizePath(Sys.getCwd());
		var frameworkSourceRoots = detectFrameworkSourceRoots(projectRoot);
		var frameworkTypedInjectionRoots = detectFrameworkTypedInjectionRoots(projectRoot);
		var allowFrameworkTypedInjections = ProfileResolver.resolve() == RustProfile.Metal;
		Context.onAfterTyping(types -> enforce(types, projectRoot, frameworkSourceRoots, allowFrameworkTypedInjections, frameworkTypedInjectionRoots,
			allowedRawInjectionModules(types)));
	}

	static function enforce(types:Array<ModuleType>, projectRoot:String, frameworkSourceRoots:Array<String>, allowFrameworkTypedInjections:Bool,
			frameworkTypedInjectionRoots:Array<String>, allowedRawModules:Map<String, Bool>):Void {
		for (moduleType in types) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					if (!isStrictProjectSource(classType.pos, projectRoot, frameworkSourceRoots))
						continue;
					enforceNoRustInjectionInClass(classType, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots,
						allowedRawModules.exists(RustRawInjectionAuthorityAnalyzer.moduleNameForClass(classType)));
				case TAbstract(abstractRef):
					var abstractType = abstractRef.get();
					if (!isStrictProjectSource(abstractType.pos, projectRoot, frameworkSourceRoots) || abstractType.impl == null)
						continue;
					var impl = abstractType.impl.get();
					if (impl != null) {
						enforceNoRustInjectionInFields(impl.fields.get().concat(impl.statics.get()), projectRoot, allowFrameworkTypedInjections,
							frameworkTypedInjectionRoots, allowedRawModules.exists(RustRawInjectionAuthorityAnalyzer.moduleNameForAbstract(abstractType)));
					}
				case _:
			}
		}
	}

	static function enforceNoRustInjectionInClass(classType:ClassType, projectRoot:String, allowFrameworkTypedInjections:Bool,
			frameworkTypedInjectionRoots:Array<String>, allowScopedRawAuthority:Bool):Void {
		enforceNoRustInjectionInFields(classType.fields.get().concat(classType.statics.get()), projectRoot, allowFrameworkTypedInjections,
			frameworkTypedInjectionRoots, allowScopedRawAuthority);
	}

	static function enforceNoRustInjectionInFields(fields:Array<ClassField>, projectRoot:String, allowFrameworkTypedInjections:Bool,
			frameworkTypedInjectionRoots:Array<String>, allowScopedRawAuthority:Bool):Void {
		var allFields = fields;
		for (field in allFields) {
			var expr = field.expr();
			if (expr == null)
				continue;
			scanForRustInjection(expr, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots, allowScopedRawAuthority);
		}
	}

	static function scanForRustInjection(expr:TypedExpr, projectRoot:String, allowFrameworkTypedInjections:Bool, frameworkTypedInjectionRoots:Array<String>,
			allowScopedRawAuthority:Bool):Void {
		if (isRustInjectionCall(expr)) {
			if (allowScopedRawAuthority) {
				TypedExprTools.iter(expr,
					e -> scanForRustInjection(e, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots, allowScopedRawAuthority));
				return;
			}
			if (allowFrameworkTypedInjections && isFrameworkTypedInjectionExpr(expr.pos, projectRoot, frameworkTypedInjectionRoots)) {
				TypedExprTools.iter(expr,
					e -> scanForRustInjection(e, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots, allowScopedRawAuthority));
				return;
			}

			RustDiagnostic.error(RustDiagnosticId.ProfileContractError, "Strict mode forbids `__rust__()` code injection in application code. "
				+ "Prefer a typed wrapper or move target-specific interop into `std/`.",
				expr.pos);
		}

		TypedExprTools.iter(expr,
			e -> scanForRustInjection(e, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots, allowScopedRawAuthority));
	}

	static function isRustInjectionCall(expr:TypedExpr):Bool {
		return switch (expr.expr) {
			case TCall(callTarget, _):
				switch (callTarget.expr) {
					case TIdent(name):
						name == "__rust__";
					case TLocal(variable):
						variable.name == "__rust__";
					case TField(_, fieldAccess):
						switch (fieldAccess) {
							case FInstance(_, _, classField) | FStatic(_, classField) | FAnon(classField) | FClosure(_, classField):
								classField.get().name == "__rust__";
							case FEnum(_, enumField):
								enumField.name == "__rust__";
							case FDynamic(name):
								name == "__rust__";
						}
					case _:
						false;
				}
			case _:
				false;
		}
	}

	static function isStrictProjectSource(pos:haxe.macro.Expr.Position, projectRoot:String, frameworkSourceRoots:Array<String>):Bool {
		var root = ensureTrailingSlash(projectRoot);
		var file = normalizePath(Context.getPosInfos(pos).file);
		if (file == null || file == "")
			return false;

		if (!Path.isAbsolute(file)) {
			file = normalizePath(Path.join([root, file]));
		}

		if (!StringTools.startsWith(file, root)) {
			return false;
		}

		if (isUnderAnyRoot(file, frameworkSourceRoots)) {
			return false;
		}

		return true;
	}

	static function isFrameworkTypedInjectionExpr(pos:haxe.macro.Expr.Position, projectRoot:String, frameworkTypedInjectionRoots:Array<String>):Bool {
		var root = ensureTrailingSlash(projectRoot);
		var file = normalizePath(Context.getPosInfos(pos).file);
		if (file == null || file == "")
			return false;

		if (!Path.isAbsolute(file)) {
			file = normalizePath(Path.join([root, file]));
		}

		// Dependency/library source outside the project root is framework code.
		if (!StringTools.startsWith(file, root)) {
			return true;
		}

		return isUnderAnyRoot(file, frameworkTypedInjectionRoots);
	}

	static function detectFrameworkSourceRoots(projectRoot:String):Array<String> {
		var roots:Array<String> = [];
		for (root in frameworkRootCandidates(projectRoot))
			addUniqueRoot(roots, root);
		return roots;
	}

	static function detectFrameworkTypedInjectionRoots(projectRoot:String):Array<String> {
		var roots:Array<String> = [];
		for (base in frameworkRootCandidates(projectRoot)) {
			addUniqueRoot(roots, Path.join([base, "reflaxe/rust/macros"]));
			addUniqueRoot(roots, Path.join([base, "rust/metal"]));
		}
		addUniqueRoot(roots, Path.join([projectRoot, "std/rust/metal"]));
		return roots;
	}

	static function frameworkRootCandidates(projectRoot:String):Array<String> {
		var roots:Array<String> = [];
		try {
			var compilerInitPath = normalizePath(Context.resolvePath("reflaxe/rust/CompilerInit.hx"));
			var rustDir = Path.directory(compilerInitPath);
			var reflaxeDir = Path.directory(rustDir);
			var srcDir = Path.directory(reflaxeDir);
			var libraryRoot = Path.directory(srcDir);
			roots.push(srcDir);
			roots.push(Path.join([libraryRoot, "std"]));
		} catch (_:haxe.Exception) {
			// Resolve failures can occur in non-standard tool contexts; strict checks then fall back
			// to project-root-only filtering.
		}
		return roots;
	}

	static function addUniqueRoot(roots:Array<String>, path:String):Void {
		if (path == null || path == "")
			return;
		var normalized = normalizePath(path);
		if (!Path.isAbsolute(normalized))
			return;
		for (existing in roots) {
			if (existing == normalized)
				return;
		}
		roots.push(normalized);
	}

	static function isUnderAnyRoot(file:String, roots:Array<String>):Bool {
		for (root in roots) {
			if (isUnderRoot(file, root))
				return true;
		}
		return false;
	}

	static function isUnderRoot(file:String, root:String):Bool {
		var normalizedRoot = ensureTrailingSlash(root);
		return StringTools.startsWith(file, normalizedRoot) || file == normalizePath(root);
	}

	static function ensureTrailingSlash(path:String):String {
		var normalized = normalizePath(path);
		return StringTools.endsWith(normalized, "/") ? normalized : normalized + "/";
	}

	static function normalizePath(path:String):String {
		return Path.normalize(path).split("\\").join("/");
	}

	static function allowedRawInjectionModules(types:Array<ModuleType>):Map<String, Bool> {
		var out:Map<String, Bool> = [];
		var snapshot = RustRawInjectionAuthorityAnalyzer.collect(types);
		for (module in snapshot.modules)
			out.set(module, true);
		return out;
	}

	static function isRustBuild():Bool {
		var targetName = Context.definedValue("target.name");
		return targetName == "rust" || Context.defined("rust_output");
	}
}
#end
