package model;

import haxe.Json;
import haxe.ds.StringMap;
import haxe.json.Value;
import model.Task.TaskDataV1;
import sys.FileSystem;
import sys.io.File;
import util.Paths;

private typedef StoreDataV1 = {
	var version:Int;
	@:optional var tasks:Array<TaskDataV1>;
};

private typedef StoreLoadResult = {
	var data:StoreDataV1;
	var migrated:Bool;
};

/**
	Task storage + persistence for the todo app.

	Why
	- We want the example to act like a real sys target application by default: it persists
	  tasks to disk.
	- We avoid serializing Haxe class instances directly; instead we serialize a typed data payload
	  so persistence stays stable across refactors.

	What
	- In-memory `tasks:Array<Task>` plus `dirty` tracking.
	- JSON persistence with a schema version.

	How
	- `save()` writes to a temp file and renames for best-effort crash safety.
	- `load()` tolerates missing files and parse failures (caller can surface errors).
**/
class Store {
	public var tasks:Array<Task> = [];
	public var dirty(default, null):Bool = false;
	public var dirtyVersion(default, null):Int = 0;

	public function new() {}

	public function seedDemo():Void {
		tasks = [
			Task.make("bootstrap reflaxe.rust", true),
			Task.make("ship TUI harness", false),
			Task.make("reach v1.0 stdlib parity", false),
			Task.make("write docs + regression tests", false),
		];
		dirty = false;
	}

	public function countDone():Int {
		var n = 0;
		for (t in tasks)
			if (t.done)
				n = n + 1;
		return n;
	}

	public function add(title:String):Task {
		var t = Task.make(title, false);
		tasks.push(t);
		markDirty();
		return t;
	}

	public function toggleAt(index:Int):Void {
		if (index < 0 || index >= tasks.length)
			return;
		tasks[index].toggle();
		markDirty();
	}

	public function markDirty():Void {
		dirty = true;
		dirtyVersion = dirtyVersion + 1;
	}

	public function removeById(id:String):Void {
		var i = 0;
		while (i < tasks.length) {
			var t = tasks[i];
			if (t.id == id) {
				tasks.splice(i, 1);
				markDirty();
				return;
			}
			i = i + 1;
		}
	}

	public function findById(id:String):Null<Task> {
		for (t in tasks)
			if (t.id == id)
				return t;
		return null;
	}

	public function load():Void {
		var path = Paths.dataFile();
		if (!FileSystem.exists(path))
			return;

		var content = File.getContent(path);
		var decoded = decodeStoreData(Json.parseValue(content));
		var obj = decoded.data;

		var list:Array<TaskDataV1> = obj.tasks != null ? obj.tasks : [];
		var out:Array<Task> = [];
		for (d in list) {
			out.push(Task.fromData(d));
		}

		tasks = out;
		dirty = false;

		// Best-effort normalize legacy payloads to the current schema.
		if (decoded.migrated) {
			save();
		}
	}

	public function save():Void {
		Paths.ensureConfigDir();

		var path = Paths.dataFile();
		var tmp = path + ".tmp";
		var backup = path + ".bak";

		var list:Array<TaskDataV1> = [];
		for (t in tasks)
			list.push(t.toData());

		var payload:StoreDataV1 = {
			version: 1,
			tasks: list,
		};

		var json = Json.stringify(payload, null, "  ");
		File.saveContent(tmp, json);

		var hadOld = FileSystem.exists(path);
		if (FileSystem.exists(backup))
			FileSystem.deleteFile(backup);
		if (hadOld)
			FileSystem.rename(path, backup);

		try {
			FileSystem.rename(tmp, path);
		} catch (e:haxe.Exception) {
			// Best-effort rollback to preserve the previous file on failed swap.
			if (FileSystem.exists(tmp))
				FileSystem.deleteFile(tmp);
			if (hadOld && !FileSystem.exists(path) && FileSystem.exists(backup)) {
				FileSystem.rename(backup, path);
			}
			throw e;
		}

		if (FileSystem.exists(backup))
			FileSystem.deleteFile(backup);

		dirty = false;
	}

	static function decodeStoreData(raw:Value):StoreLoadResult {
		var root = requireObject(raw, "Invalid store data: root must be an object.");
		var versionValue = readField(root, "version");

		if (versionValue == null || isNullValue(versionValue)) {
			// Legacy payloads sometimes omitted `version`. Try current format first,
			// then fall back to v0 migration.
			try {
				return {
					data: {
						version: 1,
						tasks: decodeTaskListV1(root),
					},
					migrated: true,
				};
			} catch (_:haxe.Exception) {
				return {
					data: {
						version: 1,
						tasks: decodeTaskListV0(root),
					},
					migrated: true,
				};
			}
		}

		var version = requireInt(versionValue, "Invalid store data: 'version' must be an integer.");
		if (version == 1) {
			return {
				data: {
					version: 1,
					tasks: decodeTaskListV1(root),
				},
				migrated: false,
			};
		}

		if (version == 0) {
			return {
				data: {
					version: 1,
					tasks: decodeTaskListV0(root),
				},
				migrated: true,
			};
		}

		throw new haxe.Exception("Unsupported data version: " + version);
	}

	static function decodeTaskListV1(raw:StringMap<Value>):Array<TaskDataV1> {
		var out:Array<TaskDataV1> = [];
		var tasksValue = readField(raw, "tasks");
		if (tasksValue == null || isNullValue(tasksValue))
			return out;

		var entries = requireArray(tasksValue, "Invalid store data: 'tasks' must be an array.");
		for (entry in entries) {
			out.push(decodeTaskData(entry));
		}
		return out;
	}

	static function decodeTaskListV0(raw:StringMap<Value>):Array<TaskDataV1> {
		var out:Array<TaskDataV1> = [];
		var tasksValue = readField(raw, "tasks");
		if (tasksValue == null || isNullValue(tasksValue))
			return out;

		var legacyTasks = requireArray(tasksValue, "Invalid legacy store data: 'tasks' must be an array.");
		var now = Std.int(Date.now().getTime());
		var index = 0;
		for (entry in legacyTasks) {
			var legacy = requireObject(entry, "Invalid legacy store data: each task entry must be an object.");
			var title = readRequiredString(legacy, "text");
			var done = readRequiredBool(legacy, "done");
			var createdAtValue = readOptionalInt(legacy, "createdAt");
			var createdAt = createdAtValue != null ? (createdAtValue : Int) : now;
			var updatedAtValue = readOptionalInt(legacy, "updatedAt");
			var updatedAt = updatedAtValue != null ? (updatedAtValue : Int) : createdAt;

			out.push({
				id: "migrated-v0-" + createdAt + "-" + index,
				title: title,
				done: done,
				notes: ("" : Null<String>),
				tags: [],
				project: ("inbox" : Null<String>),
				createdAt: createdAt,
				updatedAt: updatedAt,
				due: null,
			});
			index = index + 1;
		}
		return out;
	}

	static function decodeTaskData(raw:Value):TaskDataV1 {
		var obj = requireObject(raw, "Invalid task data: each task entry must be an object.");
		return {
			id: readRequiredString(obj, "id"),
			title: readRequiredString(obj, "title"),
			done: readRequiredBool(obj, "done"),
			notes: readOptionalString(obj, "notes"),
			tags: readOptionalStringArray(obj, "tags"),
			project: readOptionalString(obj, "project"),
			createdAt: readRequiredInt(obj, "createdAt"),
			updatedAt: readOptionalInt(obj, "updatedAt"),
			due: readOptionalInt(obj, "due"),
		};
	}

	static function readRequiredString(raw:StringMap<Value>, field:String):String {
		var value = readField(raw, field);
		if (value == null)
			throw new haxe.Exception("Invalid task data: '" + field + "' is required and must be a string.");
		return requireString(value, "Invalid task data: '" + field + "' must be a string.");
	}

	static function readOptionalString(raw:StringMap<Value>, field:String):Null<String> {
		var value = readField(raw, field);
		if (value == null || isNullValue(value))
			return null;
		return requireString(value, "Invalid task data: '" + field + "' must be a string.");
	}

	static function readRequiredBool(raw:StringMap<Value>, field:String):Bool {
		var value = readField(raw, field);
		if (value == null)
			throw new haxe.Exception("Invalid task data: '" + field + "' is required and must be a bool.");
		return requireBool(value, "Invalid task data: '" + field + "' must be a bool.");
	}

	static function readRequiredInt(raw:StringMap<Value>, field:String):Int {
		var value = readField(raw, field);
		if (value == null)
			throw new haxe.Exception("Invalid task data: '" + field + "' is required and must be an integer.");
		return requireInt(value, "Invalid task data: '" + field + "' must be an integer.");
	}

	static function readOptionalInt(raw:StringMap<Value>, field:String):Null<Int> {
		var value = readField(raw, field);
		if (value == null || isNullValue(value))
			return null;
		return requireInt(value, "Invalid task data: '" + field + "' must be an integer.");
	}

	static function readOptionalStringArray(raw:StringMap<Value>, field:String):Null<Array<String>> {
		var value = readField(raw, field);
		if (value == null || isNullValue(value))
			return null;

		var values = requireArray(value, "Invalid task data: '" + field + "' must be an array of strings.");
		var out:Array<String> = [];
		for (entry in values) {
			out.push(requireString(entry, "Invalid task data: '" + field + "' must contain only strings."));
		}
		return out;
	}

	static function readField(raw:StringMap<Value>, field:String):Null<Value> {
		return raw.exists(field) ? raw.get(field) : null;
	}

	static function requireObject(value:Value, message:String):StringMap<Value> {
		return switch (value) {
			case JObject(keys, values):
				var out = new StringMap<Value>();
				var limit = keys.length < values.length ? keys.length : values.length;
				for (i in 0...limit) {
					out.set(keys[i], values[i]);
				}
				out;
			case _: throw new haxe.Exception(message);
		};
	}

	static function requireArray(value:Value, message:String):Array<Value> {
		return switch (value) {
			case JArray(items): items;
			case _: throw new haxe.Exception(message);
		};
	}

	static function requireString(value:Value, message:String):String {
		return switch (value) {
			case JString(s): s;
			case _: throw new haxe.Exception(message);
		};
	}

	static function requireBool(value:Value, message:String):Bool {
		return switch (value) {
			case JBool(b): b;
			case _: throw new haxe.Exception(message);
		};
	}

	static function requireInt(value:Value, message:String):Int {
		return switch (value) {
			case JNumber(n):
				if (Math.isNaN(n) || !Math.isFinite(n))
					throw new haxe.Exception(message);
				var intValue = Std.int(n);
				if (intValue != n)
					throw new haxe.Exception(message);
				intValue;
			case _: throw new haxe.Exception(message);
		};
	}

	static function isNullValue(value:Value):Bool {
		return switch (value) {
			case JNull: true;
			case _: false;
		};
	}
}
