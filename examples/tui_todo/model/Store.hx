package model;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import util.Paths;

/**
	Task storage + persistence for the todo app.

	Why
	- We want the example to act like a real sys target application by default: it persists
	  tasks to disk.
	- We avoid serializing Haxe class instances directly; instead we convert to/from `Dynamic`
	  so the Rust target can stringify reliably.

	What
	- In-memory `tasks:Array<Task>` plus `dirty` tracking.
	- JSON persistence with a schema version.

	How
	- `save()` writes to a temp file and renames for best-effort crash safety.
	- `load()` tolerates missing files and parse failures (caller can surface errors).
**/
class Store {
	public var tasks: Array<Task> = [];
	public var dirty(default, null): Bool = false;

	public function new() {}

	public function seedDemo(): Void {
		tasks = [
			Task.make("bootstrap reflaxe.rust", true),
			Task.make("ship crazy TUI harness", false),
			Task.make("reach v1.0 stdlib parity", false),
			Task.make("write docs + regression tests", false),
		];
		dirty = false;
	}

	public function countDone(): Int {
		var n = 0;
		for (t in tasks) if (t.done) n = n + 1;
		return n;
	}

	public function add(title: String): Task {
		var t = Task.make(title, false);
		tasks.push(t);
		dirty = true;
		return t;
	}

	public function toggleAt(index: Int): Void {
		if (index < 0 || index >= tasks.length) return;
		tasks[index].toggle();
		markDirty();
	}

	public function markDirty(): Void {
		dirty = true;
	}

	public function removeById(id: String): Void {
		var i = 0;
		while (i < tasks.length) {
			if (tasks[i].id == id) {
				tasks.splice(i, 1);
				markDirty();
				return;
			}
			i = i + 1;
		}
	}

	public function findById(id: String): Null<Task> {
		for (t in tasks) if (t.id == id) return t;
		return null;
	}

	public function load(): Void {
		var path = Paths.dataFile();
		if (!FileSystem.exists(path)) return;

		var content = File.getContent(path);
		var obj: Dynamic = Json.parse(content);
		var version: Int = obj.version;
		if (version != 1) {
			throw "Unsupported data version: " + version;
		}

		var list: Array<Dynamic> = obj.tasks;
		var out: Array<Task> = [];
		for (d in list) {
			out.push(Task.fromDyn(d));
		}

		tasks = out;
		dirty = false;
	}

	public function save(): Void {
		Paths.ensureConfigDir();

		var path = Paths.dataFile();
		var tmp = path + ".tmp";

		var payload: Dynamic = {
			version: 1,
			tasks: tasks.map(t -> t.toDyn()),
		};

		var json = Json.stringify(payload, null, "  ");
		File.saveContent(tmp, json);

		if (FileSystem.exists(path)) FileSystem.deleteFile(path);
		FileSystem.rename(tmp, path);

		dirty = false;
	}
}
