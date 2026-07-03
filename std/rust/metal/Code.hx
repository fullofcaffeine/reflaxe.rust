package rust.metal;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import StringTools as HaxeStringTools;
#end

/**
 * Scoped code-injection bridge for the `metal` profile.
 *
 * Why
 * - The raw `__rust__` escape hatch is intentionally restricted in app code (strict boundary mode).
 * - Metal still needs an ergonomic way to reach Rust-only constructs that are not yet modeled as
 *   dedicated Haxe APIs.
 *
 * What
 * - `expr(code, ...args)` emits a Rust expression and returns it as a typed Haxe expression.
 * - `stmt(code, ...args)` emits Rust statement/block code in a `Void` context.
 * - Placeholder interpolation follows Reflaxe injection rules: `{0}`, `{1}`, ...
 * - Intended usage pattern:
 *   1. framework/library helper uses `rust.metal.Code.*`,
 *   2. app code calls that helper and remains fully typed.
 * - Project-local direct use must live in a narrow owning class tagged with `@:rustAllowRaw`.
 *
 * How
 * - This macro delegates to the framework-owned `RustInjection.__rust__` shim.
 * - Keeping the boundary in `std/rust/metal/*` provides a single documented surface for metal interop.
 * - Callers should keep snippets minimal and prefer dedicated typed `std/` APIs when available.
 */
class Code {
	public static macro function expr(code:String, args:Array<Expr>):Expr {
		if (code == null || code.length == 0) {
			Context.error("`rust.metal.Code.expr` requires a non-empty Rust snippet.", Context.currentPos());
		}
		enforceScopedAuthority("expr");
		var callArgs = [macro $v{code}].concat(args);
		return macro reflaxe.rust.macros.RustInjection.__rust__($a{callArgs});
	}

	public static macro function stmt(code:String, args:Array<Expr>):Expr {
		if (code == null || code.length == 0) {
			Context.error("`rust.metal.Code.stmt` requires a non-empty Rust snippet.", Context.currentPos());
		}
		enforceScopedAuthority("stmt");
		var callArgs = [macro $v{code}].concat(args);
		return macro {
			reflaxe.rust.macros.RustInjection.__rust__($a{callArgs});
		};
	}

	#if macro
	static function enforceScopedAuthority(kind:String):Void {
		if (isFrameworkCallsite())
			return;
		if (localTypeAllowsRaw())
			return;
		Context.error("`rust.metal.Code."
			+ kind
			+ "` is a controlled raw Rust escape hatch. Use it only in a narrow owning class tagged with `@:rustAllowRaw`, "
			+ "then expose a typed Haxe API to application code.",
			Context.currentPos());
	}

	static function localTypeAllowsRaw():Bool {
		var localClass = Context.getLocalClass();
		if (localClass != null && hasRustAllowRaw(localClass.get().meta))
			return true;
		return false;
	}

	static function hasRustAllowRaw(meta:MetaAccess):Bool {
		if (meta == null)
			return false;
		for (entry in meta.get()) {
			if (entry.name == ":rustAllowRaw" || entry.name == "rustAllowRaw")
				return true;
		}
		return false;
	}

	static function isFrameworkCallsite():Bool {
		var info = Context.getPosInfos(Context.currentPos());
		if (info == null || info.file == null || info.file.length == 0)
			return false;
		var file = normalizePath(info.file);
		var cwd = normalizePath(Sys.getCwd());
		if (!Path.isAbsolute(file))
			file = normalizePath(Path.join([cwd, file]));
		if (!HaxeStringTools.startsWith(file, ensureTrailingSlash(cwd)))
			return true;
		return isUnderAnyRoot(file, detectFrameworkSourceRoots());
	}

	static function detectFrameworkSourceRoots():Array<String> {
		var roots:Array<String> = [];
		try {
			var compilerInitPath = normalizePath(Context.resolvePath("reflaxe/rust/CompilerInit.hx"));
			var rustDir = Path.directory(compilerInitPath);
			var reflaxeDir = Path.directory(rustDir);
			var srcDir = Path.directory(reflaxeDir);
			var libraryRoot = Path.directory(srcDir);
			addUniqueRoot(roots, srcDir);
			addUniqueRoot(roots, Path.join([libraryRoot, "std"]));
		} catch (_:haxe.Exception) {
			// Non-standard macro contexts may not resolve the compiler package; in that case only
			// dependency files outside the current project root are treated as framework-owned.
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
		return HaxeStringTools.startsWith(file, normalizedRoot) || file == normalizePath(root);
	}

	static function ensureTrailingSlash(path:String):String {
		var normalized = normalizePath(path);
		return HaxeStringTools.endsWith(normalized, "/") ? normalized : normalized + "/";
	}

	static function normalizePath(path:String):String {
		return Path.normalize(path).split("\\").join("/");
	}
	#end
}
