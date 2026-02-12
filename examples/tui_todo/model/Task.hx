package model;

import haxe.Json;

typedef TaskDataV1 = {
	var id: String;
	var title: String;
	var done: Bool;
	@:optional var notes: Null<String>;
	@:optional var tags: Null<Array<String>>;
	@:optional var project: Null<String>;
	var createdAt: Int;
	@:optional var updatedAt: Null<Int>;
	@:optional var due: Null<Int>;
};

/**
	A single todo task.

	Why
	- This example is a compiler harness, so tasks intentionally exercise:
	  - classes + fields + methods
	  - nullable fields (due date)
	  - arrays (tags)
	  - conversion to/from a typed JSON payload for persistence

	What
	- Minimal productivity fields: title, notes, tags, done, timestamps.

	How
	- IDs are generated deterministically (timestamp + counter) to keep snapshots stable.
**/
class Task {
	static var __counter = 0;

	public var id(default, null): String;
	public var title: String;
	public var done: Bool;
	public var notes: String;
	public var tags: Array<String>;
	public var project: String;
	public var createdAt(default, null): Int;
	public var updatedAt(default, null): Int;
	public var due: Null<Int>;

	function new(id: String, title: String, done: Bool, notes: String, tags: Array<String>, project: String, createdAt: Int, updatedAt: Int, due: Null<Int>) {
		this.id = id;
		this.title = title;
		this.done = done;
		this.notes = notes;
		this.tags = tags;
		this.project = project;
		this.createdAt = createdAt;
		this.updatedAt = updatedAt;
		this.due = due;
	}

	public static function make(title: String, done: Bool): Task {
		var now = Std.int(Date.now().getTime());
		__counter = __counter + 1;
		var id = now + "-" + __counter;
		return new Task(id, title, done, "", [], "inbox", now, now, null);
	}

	public function touch(): Void {
		updatedAt = Std.int(Date.now().getTime());
	}

	public function toggle(): Void {
		done = !done;
		touch();
	}

	public function setTitle(t: String): Void {
		title = t;
		touch();
	}

	public function listLine(): String {
		var mark = done ? "x" : " ";
		var proj = project != null && project.length > 0 ? ("[" + project + "] ") : "";
		return "[" + mark + "] " + proj + title;
	}

	public function detailText(): String {
		var out = "Title: " + title + "\n";
		out = out + "Project: " + project + "\n";
		out = out + "Tags: " + (tags.length == 0 ? "-" : tags.join(", ")) + "\n";
		out = out + "Done: " + (done ? "yes" : "no") + "\n";
		out = out + "\nNotes:\n" + (notes.length == 0 ? "(none)" : notes);
		return out;
	}

	public function toData(): TaskDataV1 {
		return {
			id: id,
			title: title,
			done: done,
			notes: notes,
			tags: tags,
			project: project,
			createdAt: createdAt,
			updatedAt: updatedAt,
			due: due,
		};
	}

	public static function fromData(d: Dynamic): Task {
		var id = readRequiredString(d, "id");
		var title = readRequiredString(d, "title");
		var done = readRequiredBool(d, "done");
		var notes = readStringOrDefault(d, "notes", "");
		var tags = readStringArrayOrDefault(d, "tags", []);
		var project = readStringOrDefault(d, "project", "inbox");
		var createdAt = readRequiredInt(d, "createdAt");
		var updatedAt = readIntOrDefault(d, "updatedAt", createdAt);
		var due = readOptionalInt(d, "due");
		return new Task(id, title, done, notes, tags, project, createdAt, updatedAt, due);
	}

	static function readRequiredString(raw: Dynamic, field: String): String {
		var value: Dynamic = Reflect.field(raw, field);
		if (value == null) throw "Missing task field: " + field;
		return Std.string(value);
	}

	static function readOptionalString(raw: Dynamic, field: String): Null<String> {
		var value: Dynamic = Reflect.field(raw, field);
		if (value == null) return null;
		if (Std.string(value) == "null") return null;
		return Std.string(value);
	}

	static function readRequiredBool(raw: Dynamic, field: String): Bool {
		var value: Dynamic = Reflect.field(raw, field);
		if (value == null) throw "Missing task field: " + field;
		var s = Std.string(value).toLowerCase();
		if (s == "true") return true;
		if (s == "false") return false;
		throw "Invalid bool field: " + field;
		return false;
	}

	static function readRequiredInt(raw: Dynamic, field: String): Int {
		var value: Dynamic = Reflect.field(raw, field);
		if (value == null) throw "Missing task field: " + field;
		return readInt(value, field);
	}

	static function readOptionalInt(raw: Dynamic, field: String): Null<Int> {
		var value: Dynamic = Reflect.field(raw, field);
		if (value == null) return null;
		if (Std.string(value) == "null") return null;
		return readInt(value, field);
	}

	static function readIntOrDefault(raw: Dynamic, field: String, fallback: Int): Int {
		var value = readOptionalInt(raw, field);
		if (value == null) return fallback;
		return (value : Int);
	}

	static function readInt(value: Dynamic, field: String): Int {
		var parsed = Std.parseFloat(Std.string(value));
		if (!Math.isNaN(parsed)) return Std.int(parsed);
		throw "Invalid int field: " + field;
		return 0;
	}

	static function readOptionalStringArray(raw: Dynamic, field: String): Null<Array<String>> {
		var value: Dynamic = Reflect.field(raw, field);
		if (value == null) return null;
		if (Std.string(value) == "null") return null;
		var replacer: (Dynamic, Dynamic) -> Dynamic = null;
		var json = Json.stringify(value, replacer, null);
		var normalized: Dynamic = Json.parse(json);
		var arr: Array<Dynamic> = cast normalized;
		if (arr == null) return null;
		var out: Array<String> = [];
		for (entry in arr) out.push(Std.string(entry));
		return out;
	}

	static function readStringOrDefault(raw: Dynamic, field: String, fallback: String): String {
		var value = readOptionalString(raw, field);
		if (value == null) return fallback;
		return (value : String);
	}

	static function readStringArrayOrDefault(raw: Dynamic, field: String, fallback: Array<String>): Array<String> {
		var value = readOptionalStringArray(raw, field);
		if (value == null) return fallback;
		return (value : Array<String>);
	}
}
