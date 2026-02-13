package model;

import haxe.Json;
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
		var decoded = decodeStoreData(Json.parse(content));
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

	static function decodeStoreData(raw:Dynamic):StoreLoadResult {
		var version = readOptionalInt(raw, "version");
		if (version == null) {
			// Legacy payloads sometimes omitted `version`. Try current format first,
			// then fall back to v0 migration.
			try {
				return {
					data: {
						version: 1,
						tasks: decodeTaskListV1(raw),
					},
					migrated: true,
				};
			} catch (_:haxe.Exception) {
				return {
					data: {
						version: 1,
						tasks: decodeTaskListV0(raw),
					},
					migrated: true,
				};
			}
		}

		if (version == 1) {
			return {
				data: {
					version: 1,
					tasks: decodeTaskListV1(raw),
				},
				migrated: false,
			};
		}

		if (version == 0) {
			return {
				data: {
					version: 1,
					tasks: decodeTaskListV0(raw),
				},
				migrated: true,
			};
		}

		throw "Unsupported data version: " + version;
	}

	static function decodeTaskListV1(raw:Dynamic):Array<TaskDataV1> {
		var tasks:Array<TaskDataV1> = [];
		var rawTasks:Dynamic = Reflect.field(raw, "tasks");
		if (rawTasks != null) {
			for (rawTask in requireDynamicArray(rawTasks, "Invalid store data: 'tasks' must be an array.")) {
				tasks.push(decodeTaskData(rawTask));
			}
		}
		return tasks;
	}

	static function decodeTaskListV0(raw:Dynamic):Array<TaskDataV1> {
		var out:Array<TaskDataV1> = [];
		var rawTasks:Dynamic = Reflect.field(raw, "tasks");
		if (rawTasks == null)
			return out;
		var legacyTasks = requireDynamicArray(rawTasks, "Invalid legacy store data: 'tasks' must be an array.");

		var now = Std.int(Date.now().getTime());
		var index = 0;
		for (entry in legacyTasks) {
			var title = readRequiredString(entry, "text");
			var done = readRequiredBool(entry, "done");
			var createdAtValue = readOptionalInt(entry, "createdAt");
			var createdAt = createdAtValue != null ? (createdAtValue : Int) : now;
			var updatedAtValue = readOptionalInt(entry, "updatedAt");
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

	static function decodeTaskData(raw:Dynamic):TaskDataV1 {
		return {
			id: readRequiredString(raw, "id"),
			title: readRequiredString(raw, "title"),
			done: readRequiredBool(raw, "done"),
			notes: readOptionalString(raw, "notes"),
			tags: readOptionalStringArray(raw, "tags"),
			project: readOptionalString(raw, "project"),
			createdAt: readRequiredInt(raw, "createdAt"),
			updatedAt: readOptionalInt(raw, "updatedAt"),
			due: readOptionalInt(raw, "due"),
		};
	}

	static function readRequiredString(raw:Dynamic, field:String):String {
		var value:Dynamic = Reflect.field(raw, field);
		if (value == null) {
			throw "Invalid task data: '" + field + "' must be a string.";
		}
		return Std.string(value);
	}

	static function readOptionalString(raw:Dynamic, field:String):Null<String> {
		var value:Dynamic = Reflect.field(raw, field);
		if (value == null)
			return null;
		if (Std.string(value) == "null")
			return null;
		return Std.string(value);
	}

	static function readRequiredBool(raw:Dynamic, field:String):Bool {
		var value:Dynamic = Reflect.field(raw, field);
		if (value == null) {
			throw "Invalid task data: '" + field + "' must be a bool.";
		}
		var s = Std.string(value).toLowerCase();
		if (s == "true")
			return true;
		if (s == "false")
			return false;
		throw "Invalid task data: '" + field + "' must be a bool.";
		return false;
	}

	static function readRequiredInt(raw:Dynamic, field:String):Int {
		var value:Dynamic = Reflect.field(raw, field);
		if (value == null) {
			throw "Invalid task data: '" + field + "' is required.";
		}
		return readIntValue(value, field);
	}

	static function readOptionalInt(raw:Dynamic, field:String):Null<Int> {
		var value:Dynamic = Reflect.field(raw, field);
		if (value == null)
			return null;
		if (Std.string(value) == "null")
			return null;
		return readIntValue(value, field);
	}

	static function readIntValue(value:Dynamic, field:String):Int {
		var parsed = Std.parseFloat(Std.string(value));
		if (!Math.isNaN(parsed))
			return Std.int(parsed);
		throw "Invalid task data: '" + field + "' must be numeric.";
		return 0;
	}

	static function readOptionalStringArray(raw:Dynamic, field:String):Null<Array<String>> {
		var value:Dynamic = Reflect.field(raw, field);
		if (value == null)
			return null;
		if (Std.string(value) == "null")
			return null;
		var values = requireDynamicArray(value, "Invalid task data: '" + field + "' must be an array of strings.");
		var out:Array<String> = [];
		for (entry in values) {
			out.push(Std.string(entry));
		}
		return out;
	}

	static function requireDynamicArray(value:Dynamic, message:String):Array<Dynamic> {
		var replacer:(Dynamic, Dynamic) -> Dynamic = null;
		var json = Json.stringify(value, replacer, null);
		var normalized:Dynamic = Json.parse(json);
		var arr:Array<Dynamic> = cast normalized;
		if (arr == null) {
			throw message;
		}
		return arr;
	}
}
