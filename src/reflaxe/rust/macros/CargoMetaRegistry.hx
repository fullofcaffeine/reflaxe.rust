package reflaxe.rust.macros;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Type;

typedef RustCargoDep = {
	var name: String;
	@:optional var version: String;
	@:optional var features: Array<String>;
	@:optional var optional: Bool;
	@:optional var defaultFeatures: Bool;
	@:optional var path: String;
	@:optional var git: String;
	@:optional var branch: String;
	@:optional var tag: String;
	@:optional var rev: String;
	@:optional var packageName: String;
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
	static var deps: Map<String, RustCargoDep> = new Map();
	static var rawLines: Array<String> = [];

	public static function reset(): Void {
		deps = new Map();
		rawLines = [];
	}

	public static function collectFromContext(): Void {
		reset();
		collect(Context.getAllModuleTypes());
	}

	public static function collect(types: Array<ModuleType>): Void {
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

	public static function renderDependencyLines(): String {
		var lines: Array<String> = [];

		var names = [for (k in deps.keys()) k];
		names.sort(Reflect.compare);
		for (name in names) {
			var dep = deps.get(name);
			if (dep == null) continue;
			lines.push(renderDep(dep));
		}

		if (rawLines.length > 0) {
			var raw = rawLines.copy();
			raw.sort(Reflect.compare);
			for (line in raw) {
				var trimmed = StringTools.trim(line);
				if (trimmed.length == 0) continue;
				lines.push(trimmed);
			}
		}

		if (lines.length == 0) return "";
		return lines.join("\n") + "\n";
	}

	static function scanMeta(meta: haxe.macro.Type.MetaAccess): Void {
		for (entry in meta.get()) {
			if (entry.name != ":rustCargo") continue;

			if (entry.params == null || entry.params.length == 0) {
				Context.error("`@:rustCargo` requires a single parameter.", entry.pos);
				continue;
			}

			addFromExpr(entry.params[0], entry.pos);
		}
	}

	static function addFromExpr(e: Expr, pos: haxe.macro.Expr.Position): Void {
		var value: Dynamic = null;
		try {
			value = ExprTools.getValue(e);
		} catch (err: Dynamic) {
			Context.error("`@:rustCargo` must be a compile-time constant value.", pos);
			return;
		}

		if (value == null) {
			Context.error("`@:rustCargo` must not be null.", pos);
			return;
		}

		if (Std.isOfType(value, String)) {
			rawLines.push(cast value);
			return;
		}

		var name: Null<String> = Std.string(Reflect.field(value, "name"));
		if (name == null || name.length == 0 || name == "null") {
			Context.error("`@:rustCargo` object form must include a non-empty `name` field.", pos);
			return;
		}

		var dep: RustCargoDep = {
			name: name
		};

		dep.version = asOptionalStringField(value, "version");
		dep.path = asOptionalStringField(value, "path");
		dep.git = asOptionalStringField(value, "git");
		dep.branch = asOptionalStringField(value, "branch");
		dep.tag = asOptionalStringField(value, "tag");
		dep.rev = asOptionalStringField(value, "rev");
		dep.packageName = asOptionalStringField(value, "package");
		dep.optional = asOptionalBoolField(value, "optional");
		dep.defaultFeatures = asOptionalBoolField(value, "defaultFeatures");
		dep.features = asOptionalStringArrayField(value, "features", pos);

		addOrMerge(dep, pos);
	}

	static function asOptionalStringField(o: Dynamic, field: String): Null<String> {
		var v: Dynamic = Reflect.field(o, field);
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return Std.string(v);
		return cast v;
	}

	static function asOptionalBoolField(o: Dynamic, field: String): Null<Bool> {
		var v: Dynamic = Reflect.field(o, field);
		if (v == null) return null;
		if (Std.isOfType(v, Bool)) return cast v;
		return null;
	}

	static function asOptionalStringArrayField(o: Dynamic, field: String, pos: haxe.macro.Expr.Position): Null<Array<String>> {
		var v: Dynamic = Reflect.field(o, field);
		if (v == null) return null;

		if (!Std.isOfType(v, Array)) {
			Context.error("`@:rustCargo` field `" + field + "` must be an array of strings.", pos);
			return null;
		}

		var out: Array<String> = [];
		for (item in (cast v : Array<Dynamic>)) {
			if (!Std.isOfType(item, String)) {
				Context.error("`@:rustCargo` field `" + field + "` must contain only strings.", pos);
				return null;
			}
			out.push(cast item);
		}

		return out;
	}

	static function addOrMerge(dep: RustCargoDep, pos: haxe.macro.Expr.Position): Void {
		var existing = deps.get(dep.name);
		if (existing == null) {
			deps.set(dep.name, dep);
			return;
		}

		// Merge fields conservatively (prefer "union" semantics for features).
		var merged: RustCargoDep = { name: dep.name };

		merged.version = mergeStringField(existing.version, dep.version, "version", dep.name, pos);
		merged.path = mergeStringField(existing.path, dep.path, "path", dep.name, pos);
		merged.git = mergeStringField(existing.git, dep.git, "git", dep.name, pos);
		merged.branch = mergeStringField(existing.branch, dep.branch, "branch", dep.name, pos);
		merged.tag = mergeStringField(existing.tag, dep.tag, "tag", dep.name, pos);
		merged.rev = mergeStringField(existing.rev, dep.rev, "rev", dep.name, pos);
		merged.packageName = mergeStringField(existing.packageName, dep.packageName, "package", dep.name, pos);

		merged.optional = (existing.optional == true) || (dep.optional == true);

		merged.defaultFeatures = mergeBoolField(existing.defaultFeatures, dep.defaultFeatures, "defaultFeatures", dep.name, pos);

		var features: Array<String> = [];
		if (existing.features != null) features = features.concat(existing.features);
		if (dep.features != null) features = features.concat(dep.features);
		if (features.length > 0) {
			var seen = new Map<String, Bool>();
			var unique: Array<String> = [];
			for (f in features) {
				if (seen.exists(f)) continue;
				seen.set(f, true);
				unique.push(f);
			}
			unique.sort(Reflect.compare);
			merged.features = unique;
		}

		deps.set(dep.name, merged);
	}

	static function mergeStringField(existing: Null<String>, incoming: Null<String>, field: String, name: String, pos: haxe.macro.Expr.Position): Null<String> {
		if (existing == null || existing.length == 0) return incoming;
		if (incoming == null || incoming.length == 0) return existing;
		if (existing != incoming) {
			Context.error("Conflicting `@:rustCargo` " + field + " for dependency `" + name + "`: `" + existing + "` vs `" + incoming + "`.", pos);
		}
		return existing;
	}

	static function mergeBoolField(existing: Null<Bool>, incoming: Null<Bool>, field: String, name: String, pos: haxe.macro.Expr.Position): Null<Bool> {
		if (existing == null) return incoming;
		if (incoming == null) return existing;
		if (existing != incoming) {
			Context.error("Conflicting `@:rustCargo` " + field + " for dependency `" + name + "`.", pos);
		}
		return existing;
	}

	static function renderDep(dep: RustCargoDep): String {
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

		var fields: Array<String> = [];
		if (dep.version != null && dep.version.length > 0) fields.push("version = " + tomlString(dep.version));
		if (dep.path != null && dep.path.length > 0) fields.push("path = " + tomlString(dep.path));
		if (dep.git != null && dep.git.length > 0) fields.push("git = " + tomlString(dep.git));
		if (dep.branch != null && dep.branch.length > 0) fields.push("branch = " + tomlString(dep.branch));
		if (dep.tag != null && dep.tag.length > 0) fields.push("tag = " + tomlString(dep.tag));
		if (dep.rev != null && dep.rev.length > 0) fields.push("rev = " + tomlString(dep.rev));
		if (dep.packageName != null && dep.packageName.length > 0) fields.push("package = " + tomlString(dep.packageName));

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

	static function tomlString(value: String): String {
		return '"' + value.split("\\").join("\\\\").split("\"").join("\\\"") + '"';
	}
}
#end
