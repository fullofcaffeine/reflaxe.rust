package reflaxe.rust.macros;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import sys.FileSystem;

typedef RustExtraSrcFile = {
	var module:String;
	var fileName:String;
	var fullPath:String;
	var pos:haxe.macro.Expr.Position;
}

/**
 * RustExtraSrcRegistry
 *
 * Collects `@:rustExtraSrc("...")` and `@:rustExtraSrcDir("...")` metadata from
 * typed modules to request additional hand-written Rust sources be copied into
 * the generated crate's `src/` directory.
 *
 * Paths are resolved via:
 * - absolute path (if it exists)
 * - classpath-relative lookup (first matching entry from `Context.getClassPath()`)
 *
 * Notes:
 * - Only `*.rs` files are included.
 * - `main.rs` / `lib.rs` are ignored.
 * - Module name is derived from file name.
 */
class RustExtraSrcRegistry {
	static var files:Array<RustExtraSrcFile> = [];

	public static function reset():Void {
		files = [];
	}

	public static function collectFromContext():Void {
		reset();
		collect(Context.getAllModuleTypes());
	}

	public static function collect(types:Array<ModuleType>):Void {
		for (t in types) {
			switch (t) {
				case TClassDecl(clsRef):
					scanMeta(clsRef.get().meta);
				case TEnumDecl(enRef):
					scanMeta(enRef.get().meta);
				case TTypeDecl(tdRef):
					scanMeta(tdRef.get().meta);
				case TAbstract(abRef):
					scanMeta(abRef.get().meta);
			}
		}
	}

	public static function getFiles():Array<RustExtraSrcFile> {
		return files.copy();
	}

	static function scanMeta(meta:haxe.macro.Type.MetaAccess):Void {
		for (entry in meta.get()) {
			switch (entry.name) {
				case ":rustExtraSrc":
					if (entry.params == null || entry.params.length != 1) {
						Context.error("`@:rustExtraSrc` requires a single string parameter.", entry.pos);
						continue;
					}
					addFileFromExpr(entry.params[0], entry.pos);
				case ":rustExtraSrcDir":
					if (entry.params == null || entry.params.length != 1) {
						Context.error("`@:rustExtraSrcDir` requires a single string parameter.", entry.pos);
						continue;
					}
					addDirFromExpr(entry.params[0], entry.pos);
				case _:
			}
		}
	}

	static function addFileFromExpr(e:Expr, pos:haxe.macro.Expr.Position):Void {
		var path = extractString(e, pos, ":rustExtraSrc");
		if (path == null)
			return;
		var full = resolveExistingPath(path, pos);
		if (full == null)
			return;

		if (FileSystem.isDirectory(full)) {
			Context.error("`@:rustExtraSrc` must point to a .rs file, not a directory: " + full, pos);
			return;
		}
		addFilePath(full, pos);
	}

	static function addDirFromExpr(e:Expr, pos:haxe.macro.Expr.Position):Void {
		var path = extractString(e, pos, ":rustExtraSrcDir");
		if (path == null)
			return;
		var full = resolveExistingPath(path, pos);
		if (full == null)
			return;

		if (!FileSystem.isDirectory(full)) {
			Context.error("`@:rustExtraSrcDir` must point to a directory: " + full, pos);
			return;
		}

		for (entry in FileSystem.readDirectory(full)) {
			if (!StringTools.endsWith(entry, ".rs"))
				continue;
			if (entry == "main.rs" || entry == "lib.rs")
				continue;

			var filePath = Path.normalize(Path.join([full, entry]));
			if (FileSystem.isDirectory(filePath))
				continue;
			addFilePath(filePath, pos);
		}
	}

	static function addFilePath(fullPath:String, pos:haxe.macro.Expr.Position):Void {
		if (!StringTools.endsWith(fullPath, ".rs")) {
			Context.error("Extra Rust source must end with .rs: " + fullPath, pos);
			return;
		}

		var fileName = Path.withoutDirectory(fullPath);
		if (fileName == "main.rs" || fileName == "lib.rs")
			return;

		var moduleName = fileName.substr(0, fileName.length - 3);
		if (!isValidRustIdent(moduleName) || isRustKeyword(moduleName)) {
			Context.error("Invalid Rust module file name for extra src: " + fileName, pos);
			return;
		}

		files.push({
			module: moduleName,
			fileName: fileName,
			fullPath: fullPath,
			pos: pos
		});
	}

	static function extractString(e:Expr, pos:haxe.macro.Expr.Position, metaName:String):Null<String> {
		var value = readConstString(e);
		if (value == null) {
			Context.error("`@:" + metaName.substr(1) + "` must be a string.", pos);
			return null;
		}

		var s = value;
		s = StringTools.trim(s);
		if (s.length == 0) {
			Context.error("`@:" + metaName.substr(1) + "` must not be empty.", pos);
			return null;
		}
		return s;
	}

	static function resolveExistingPath(path:String, pos:haxe.macro.Expr.Position):Null<String> {
		var full:Null<String> = null;

		// Accept absolute/relative paths as-is if they exist.
		if (FileSystem.exists(path)) {
			full = Path.normalize(path);
		} else {
			// Otherwise treat as classpath-relative.
			for (cp in Context.getClassPath()) {
				var candidate = Path.normalize(Path.join([cp, path]));
				if (FileSystem.exists(candidate)) {
					full = candidate;
					break;
				}
			}
		}

		if (full == null || !FileSystem.exists(full)) {
			Context.error("Extra Rust source path not found: " + path, pos);
			return null;
		}

		return full;
	}

	static function unwrapExpr(e:Expr):Expr {
		return switch (e.expr) {
			case EParenthesis(inner): unwrapExpr(inner);
			case EMeta(_, inner): unwrapExpr(inner);
			case _: e;
		}
	}

	static function readConstString(e:Expr):Null<String> {
		return switch (unwrapExpr(e).expr) {
			case EConst(CString(s, _)): s;
			case _: null;
		};
	}

	static function isValidRustIdent(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		for (i in 0...name.length) {
			var c = name.charCodeAt(i);
			var ok = (c >= "a".code && c <= "z".code)
				|| (c >= "A".code && c <= "Z".code)
				|| (c == "_".code)
				|| (i > 0 && c >= "0".code && c <= "9".code);
			if (!ok)
				return false;
		}
		return true;
	}

	static function isRustKeyword(name:String):Bool {
		return switch (name) {
			case "as" | "break" | "box" | "const" | "continue" | "crate" | "else" | "enum" | "extern" | "false" | "fn" | "for" | "if" | "impl" | "in" |
				"let" | "loop" | "match" | "mod" | "move" | "mut" | "pub" | "ref" | "return" | "self" | "Self" | "static" | "struct" | "super" | "trait" |
				"true" | "type" | "unsafe" | "use" | "where" | "while" | "async" | "await" | "dyn":
				true;
			case _:
				false;
		}
	}
}
#end
