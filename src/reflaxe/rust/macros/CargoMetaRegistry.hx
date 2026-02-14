package reflaxe.rust.macros;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

typedef RustCargoDep = {
	var name:String;
	@:optional var version:String;
	@:optional var features:Array<String>;
	@:optional var optional:Bool;
	@:optional var defaultFeatures:Bool;
	@:optional var path:String;
	@:optional var git:String;
	@:optional var branch:String;
	@:optional var tag:String;
	@:optional var rev:String;
	@:optional var packageName:String;
}

/**
 * CargoMetaRegistry
 *
 * Collects `@:rustCargo(...)` metadata from typed modules and exposes a rendered
 * TOML snippet for appending under `[dependencies]` in the generated Cargo.toml.
 *
 * Supported forms:
 * - `@:rustCargo("ratatui = \"0.26\"")` (raw TOML line)
 * - `@:rustCargo({ name: "serde", version: "1", features: ["derive"] })`
 */
class CargoMetaRegistry {
	static var deps:Map<String, RustCargoDep> = new Map();
	static var rawLines:Array<String> = [];

	public static function reset():Void {
		deps = new Map();
		rawLines = [];
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

	public static function renderDependencyLines():String {
		var lines:Array<String> = [];

		var names = [for (k in deps.keys()) k];
		names.sort(Reflect.compare);
		for (name in names) {
			var dep = deps.get(name);
			if (dep == null)
				continue;
			lines.push(renderDep(dep));
		}

		if (rawLines.length > 0) {
			var raw = rawLines.copy();
			raw.sort(Reflect.compare);
			for (line in raw) {
				var trimmed = StringTools.trim(line);
				if (trimmed.length == 0)
					continue;
				lines.push(trimmed);
			}
		}

		if (lines.length == 0)
			return "";
		return lines.join("\n") + "\n";
	}

	static function scanMeta(meta:haxe.macro.Type.MetaAccess):Void {
		for (entry in meta.get()) {
			if (entry.name != ":rustCargo")
				continue;

			if (entry.params == null || entry.params.length == 0) {
				Context.error("`@:rustCargo` requires a single parameter.", entry.pos);
				continue;
			}

			addFromExpr(entry.params[0], entry.pos);
		}
	}

	static function addFromExpr(e:Expr, pos:haxe.macro.Expr.Position):Void {
		var raw = readConstString(e);
		if (raw != null) {
			rawLines.push(raw);
			return;
		}

		var fields = readObjectFields(e);
		if (fields == null) {
			Context.error("`@:rustCargo` must be a compile-time constant string or object.", pos);
			return;
		}

		var name = readOptionalStringField(fields, "name", pos);
		if (name == null || StringTools.trim(name).length == 0) {
			Context.error("`@:rustCargo` object form must include a non-empty `name` field.", pos);
			return;
		}

		var dep:RustCargoDep = {
			name: name
		};

		dep.version = readOptionalStringField(fields, "version", pos);
		dep.path = readOptionalStringField(fields, "path", pos);
		dep.git = readOptionalStringField(fields, "git", pos);
		dep.branch = readOptionalStringField(fields, "branch", pos);
		dep.tag = readOptionalStringField(fields, "tag", pos);
		dep.rev = readOptionalStringField(fields, "rev", pos);
		dep.packageName = readOptionalStringField(fields, "package", pos);
		dep.optional = readOptionalBoolField(fields, "optional", pos);
		dep.defaultFeatures = readOptionalBoolField(fields, "defaultFeatures", pos);
		dep.features = readOptionalStringArrayField(fields, "features", pos);

		addOrMerge(dep, pos);
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

	static function readConstBool(e:Expr):Null<Bool> {
		return switch (unwrapExpr(e).expr) {
			case EConst(CIdent("true")): true;
			case EConst(CIdent("false")): false;
			case _: null;
		};
	}

	static function readObjectFields(e:Expr):Null<Map<String, Expr>> {
		return switch (unwrapExpr(e).expr) {
			case EObjectDecl(entries):
				var out:Map<String, Expr> = new Map();
				for (entry in entries) {
					out.set(entry.field, entry.expr);
				}
				out;
			case _:
				null;
		}
	}

	static function readOptionalField(fields:Map<String, Expr>, field:String):Null<Expr> {
		return fields.exists(field) ? fields.get(field) : null;
	}

	static function readOptionalStringField(fields:Map<String, Expr>, field:String, pos:haxe.macro.Expr.Position):Null<String> {
		var value = readOptionalField(fields, field);
		if (value == null)
			return null;
		var s = readConstString(value);
		if (s == null) {
			Context.error("`@:rustCargo` field `" + field + "` must be a string.", pos);
		}
		return s;
	}

	static function readOptionalBoolField(fields:Map<String, Expr>, field:String, pos:haxe.macro.Expr.Position):Null<Bool> {
		var value = readOptionalField(fields, field);
		if (value == null)
			return null;
		var b = readConstBool(value);
		if (b == null) {
			Context.error("`@:rustCargo` field `" + field + "` must be a bool literal.", pos);
		}
		return b;
	}

	static function readOptionalStringArrayField(fields:Map<String, Expr>, field:String, pos:haxe.macro.Expr.Position):Null<Array<String>> {
		var value = readOptionalField(fields, field);
		if (value == null)
			return null;

		return switch (unwrapExpr(value).expr) {
			case EArrayDecl(items):
				var out:Array<String> = [];
				for (item in items) {
					var s = readConstString(item);
					if (s == null) {
						Context.error("`@:rustCargo` field `" + field + "` must contain only strings.", pos);
						return null;
					}
					out.push(s);
				}
				out;
			case _:
				Context.error("`@:rustCargo` field `" + field + "` must be an array of strings.", pos);
				null;
		};
	}

	static function addOrMerge(dep:RustCargoDep, pos:haxe.macro.Expr.Position):Void {
		var existing = deps.get(dep.name);
		if (existing == null) {
			deps.set(dep.name, dep);
			return;
		}

		// Merge fields conservatively (prefer "union" semantics for features).
		var merged:RustCargoDep = {name: dep.name};

		merged.version = mergeStringField(existing.version, dep.version, "version", dep.name, pos);
		merged.path = mergeStringField(existing.path, dep.path, "path", dep.name, pos);
		merged.git = mergeStringField(existing.git, dep.git, "git", dep.name, pos);
		merged.branch = mergeStringField(existing.branch, dep.branch, "branch", dep.name, pos);
		merged.tag = mergeStringField(existing.tag, dep.tag, "tag", dep.name, pos);
		merged.rev = mergeStringField(existing.rev, dep.rev, "rev", dep.name, pos);
		merged.packageName = mergeStringField(existing.packageName, dep.packageName, "package", dep.name, pos);

		merged.optional = (existing.optional == true) || (dep.optional == true);

		merged.defaultFeatures = mergeBoolField(existing.defaultFeatures, dep.defaultFeatures, "defaultFeatures", dep.name, pos);

		var features:Array<String> = [];
		if (existing.features != null)
			features = features.concat(existing.features);
		if (dep.features != null)
			features = features.concat(dep.features);
		if (features.length > 0) {
			var seen = new Map<String, Bool>();
			var unique:Array<String> = [];
			for (f in features) {
				if (seen.exists(f))
					continue;
				seen.set(f, true);
				unique.push(f);
			}
			unique.sort(Reflect.compare);
			merged.features = unique;
		}

		deps.set(dep.name, merged);
	}

	static function mergeStringField(existing:Null<String>, incoming:Null<String>, field:String, name:String, pos:haxe.macro.Expr.Position):Null<String> {
		if (existing == null || existing.length == 0)
			return incoming;
		if (incoming == null || incoming.length == 0)
			return existing;
		if (existing != incoming) {
			Context.error("Conflicting `@:rustCargo` " + field + " for dependency `" + name + "`: `" + existing + "` vs `" + incoming + "`.", pos);
		}
		return existing;
	}

	static function mergeBoolField(existing:Null<Bool>, incoming:Null<Bool>, field:String, name:String, pos:haxe.macro.Expr.Position):Null<Bool> {
		if (existing == null)
			return incoming;
		if (incoming == null)
			return existing;
		if (existing != incoming) {
			Context.error("Conflicting `@:rustCargo` " + field + " for dependency `" + name + "`.", pos);
		}
		return existing;
	}

	static function renderDep(dep:RustCargoDep):String {
		var features = dep.features != null ? dep.features : [];
		var optional = dep.optional == true;
		var defaultFeatures = dep.defaultFeatures;

		var needsTable = features.length > 0
			|| optional
			|| (defaultFeatures != null && defaultFeatures == false)
			|| (dep.path != null && dep.path.length > 0)
			|| (dep.git != null && dep.git.length > 0)
			|| (dep.branch != null && dep.branch.length > 0)
			|| (dep.tag != null && dep.tag.length > 0)
			|| (dep.rev != null && dep.rev.length > 0)
			|| (dep.packageName != null && dep.packageName.length > 0);

		if (!needsTable && dep.version != null && dep.version.length > 0) {
			return dep.name + " = " + tomlString(dep.version);
		}

		var fields:Array<String> = [];
		if (dep.version != null && dep.version.length > 0)
			fields.push("version = " + tomlString(dep.version));
		if (dep.path != null && dep.path.length > 0)
			fields.push("path = " + tomlString(dep.path));
		if (dep.git != null && dep.git.length > 0)
			fields.push("git = " + tomlString(dep.git));
		if (dep.branch != null && dep.branch.length > 0)
			fields.push("branch = " + tomlString(dep.branch));
		if (dep.tag != null && dep.tag.length > 0)
			fields.push("tag = " + tomlString(dep.tag));
		if (dep.rev != null && dep.rev.length > 0)
			fields.push("rev = " + tomlString(dep.rev));
		if (dep.packageName != null && dep.packageName.length > 0)
			fields.push("package = " + tomlString(dep.packageName));

		if (features.length > 0) {
			var quoted = [for (f in features) tomlString(f)];
			fields.push("features = [" + quoted.join(", ") + "]");
		}

		if (defaultFeatures != null && defaultFeatures == false) {
			fields.push("default-features = false");
		}

		if (optional) {
			fields.push("optional = true");
		}

		return dep.name + " = { " + fields.join(", ") + " }";
	}

	static function tomlString(value:String):String {
		return '"' + value.split("\\").join("\\\\").split("\"").join("\\\"") + '"';
	}
}
#end
