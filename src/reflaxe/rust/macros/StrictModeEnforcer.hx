package reflaxe.rust.macros;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;

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
 * - Scans project-local sources (under current working directory), excluding this compiler’s
 *   own `src/reflaxe/**` and `std/**` sources when developing the compiler repo.
 */
class StrictModeEnforcer {
	public static function init(): Void {
		if (!isRustBuild()) return;
		if (!Context.defined("reflaxe_rust_strict")) return;

		var projectRoot = normalizePath(Sys.getCwd());
		Context.onAfterTyping(types -> enforce(types, projectRoot));
	}

	static function enforce(types: Array<ModuleType>, projectRoot: String): Void {
		for (moduleType in types) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					if (!isStrictProjectSource(classType.pos, projectRoot)) continue;
					enforceNoRustInjectionInClass(classType);
				case _:
			}
		}
	}

	static function enforceNoRustInjectionInClass(classType: ClassType): Void {
		var allFields = classType.fields.get().concat(classType.statics.get());
		for (field in allFields) {
			var expr = field.expr();
			if (expr == null) continue;
			scanForRustInjection(expr);
		}
	}

	static function scanForRustInjection(expr: TypedExpr): Void {
		if (isRustInjectionCall(expr)) {
			Context.error(
				"Strict mode forbids `__rust__()` code injection in application code. " +
				"Prefer a typed wrapper or move target-specific interop into `std/`.",
				expr.pos
			);
		}

		TypedExprTools.iter(expr, scanForRustInjection);
	}

	static function isRustInjectionCall(expr: TypedExpr): Bool {
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

	static function isStrictProjectSource(pos: haxe.macro.Expr.Position, projectRoot: String): Bool {
		var root = ensureTrailingSlash(projectRoot);
		var file = normalizePath(Context.getPosInfos(pos).file);
		if (file == null || file == "") return false;

		if (!Path.isAbsolute(file)) {
			file = normalizePath(Path.join([root, file]));
		}

		if (!StringTools.startsWith(file, root)) {
			return false;
		}

		// Exclude compiler/framework sources when developing this repository.
		// In consumer projects, these directories typically don't exist under the app root.
		if (file.indexOf("/src/reflaxe/") != -1 || file.indexOf("/std/") != -1) {
			return false;
		}

		return true;
	}

	static function ensureTrailingSlash(path: String): String {
		var normalized = normalizePath(path);
		return StringTools.endsWith(normalized, "/") ? normalized : normalized + "/";
	}

	static function normalizePath(path: String): String {
		return Path.normalize(path).split("\\").join("/");
	}

	static function isRustBuild(): Bool {
		var targetName = Context.definedValue("target.name");
		return targetName == "rust" || Context.defined("rust_output");
	}
}
#end

