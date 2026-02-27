package reflaxe.rust.macros;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.rust.ProfileResolver;
import reflaxe.rust.RustProfile;

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
 *
 * Metal profile note
 * - `reflaxe_rust_profile=metal` enables strict mode by default in `CompilerInit`.
 * - In metal mode we still reject raw project-side `__rust__`, but allow framework-origin
 *   typed wrappers (for example macro facades in `src/reflaxe/rust/macros` and `std/rust/metal`).
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
		Context.onAfterTyping(types -> enforce(types, projectRoot, frameworkSourceRoots, allowFrameworkTypedInjections, frameworkTypedInjectionRoots));
	}

	static function enforce(types:Array<ModuleType>, projectRoot:String, frameworkSourceRoots:Array<String>, allowFrameworkTypedInjections:Bool,
			frameworkTypedInjectionRoots:Array<String>):Void {
		for (moduleType in types) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					if (!isStrictProjectSource(classType.pos, projectRoot, frameworkSourceRoots))
						continue;
					enforceNoRustInjectionInClass(classType, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots);
				case _:
			}
		}
	}

	static function enforceNoRustInjectionInClass(classType:ClassType, projectRoot:String, allowFrameworkTypedInjections:Bool,
			frameworkTypedInjectionRoots:Array<String>):Void {
		var allFields = classType.fields.get().concat(classType.statics.get());
		for (field in allFields) {
			var expr = field.expr();
			if (expr == null)
				continue;
			scanForRustInjection(expr, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots);
		}
	}

	static function scanForRustInjection(expr:TypedExpr, projectRoot:String, allowFrameworkTypedInjections:Bool,
			frameworkTypedInjectionRoots:Array<String>):Void {
		if (isRustInjectionCall(expr)) {
			if (allowFrameworkTypedInjections && isFrameworkTypedInjectionExpr(expr.pos, projectRoot, frameworkTypedInjectionRoots)) {
				TypedExprTools.iter(expr, e -> scanForRustInjection(e, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots));
				return;
			}

			Context.error("Strict mode forbids `__rust__()` code injection in application code. "
				+ "Prefer a typed wrapper or move target-specific interop into `std/`.",
				expr.pos);
		}

		TypedExprTools.iter(expr, e -> scanForRustInjection(e, projectRoot, allowFrameworkTypedInjections, frameworkTypedInjectionRoots));
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

	static function isRustBuild():Bool {
		var targetName = Context.definedValue("target.name");
		return targetName == "rust" || Context.defined("rust_output");
	}
}
#end
