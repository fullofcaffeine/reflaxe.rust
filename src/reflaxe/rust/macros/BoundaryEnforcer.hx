package reflaxe.rust.macros;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;

/**
 * BoundaryEnforcer
 *
 * WHAT
 * - Enforces "no escape hatches in apps" for this repository's example programs and snapshot cases.
 * - Fails compilation if example sources use `__rust__()` injections.
 *
 * WHY
 * - Example programs are the public reference for "Haxe -> Rust" and should not rely on raw Rust injections.
 * - Keeping examples pure forces missing surfaces into framework code (e.g. `std/` wrappers).
 *
 * HOW
 * - Enabled by defining `-D reflaxe_rust_strict_examples` in the example/snapshot `.hxml`.
 * - Registers a `Context.onAfterTyping` hook and scans example modules for `__rust__()` calls.
 */
class BoundaryEnforcer {
	public static function init(): Void {
		if (!isRustBuild()) return;
		if (!Context.defined("reflaxe_rust_strict_examples")) return;

		Context.onAfterTyping(enforceExampleBoundaries);
	}

	static function enforceExampleBoundaries(types: Array<ModuleType>): Void {
		for (moduleType in types) {
			switch (moduleType) {
				case TClassDecl(classRef):
					var classType = classRef.get();
					if (!isExampleSource(classType.pos)) continue;
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
				"`__rust__()` code injection is disallowed in examples/snapshots. " +
				"Implement the feature in Haxe (preferred) or add a reusable framework wrapper in `std/`.",
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

	static function isExampleSource(pos: haxe.macro.Expr.Position): Bool {
		var file = Context.getPosInfos(pos).file;
		if (file == null || file == "") return false;

		var cwd = normalizePath(Sys.getCwd());
		var normalized = normalizePath(file);
		if (!Path.isAbsolute(normalized)) {
			normalized = normalizePath(Path.join([cwd, normalized]));
		}

		return normalized.indexOf("/examples/") != -1 || normalized.indexOf("/test/snapshot/") != -1;
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

