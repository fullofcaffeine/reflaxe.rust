package model;

typedef TaskDataV1 = {
	var id:String;
	var title:String;
	var done:Bool;
	@:optional var notes:Null<String>;
	@:optional var tags:Null<Array<String>>;
	@:optional var project:Null<String>;
	var createdAt:Int;
	@:optional var updatedAt:Null<Int>;
	@:optional var due:Null<Int>;
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

	public var id(default, null):String;
	public var title:String;
	public var done:Bool;
	public var notes:String;
	public var tags:Array<String>;
	public var project:String;
	public var createdAt(default, null):Int;
	public var updatedAt(default, null):Int;
	public var due:Null<Int>;

	function new(id:String, title:String, done:Bool, notes:String, tags:Array<String>, project:String, createdAt:Int, updatedAt:Int, due:Null<Int>) {
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

	public static function make(title:String, done:Bool):Task {
		var now = Std.int(Date.now().getTime());
		__counter = __counter + 1;
		var id = now + "-" + __counter;
		return new Task(id, title, done, "", [], "inbox", now, now, null);
	}

	public function touch():Void {
		updatedAt = Std.int(Date.now().getTime());
	}

	public function toggle():Void {
		done = !done;
		touch();
	}

	public function setTitle(t:String):Void {
		title = t;
		touch();
	}

	public function listLine():String {
		var mark = done ? "x" : " ";
		var proj = project != null && project.length > 0 ? ("[" + project + "] ") : "";
		return "[" + mark + "] " + proj + title;
	}

	public function detailText():String {
		var out = "Title: " + title + "\n";
		out = out + "Project: " + project + "\n";
		out = out + "Tags: " + (tags.length == 0 ? "-" : tags.join(", ")) + "\n";
		out = out + "Done: " + (done ? "yes" : "no") + "\n";
		out = out + "\nNotes:\n" + (notes.length == 0 ? "(none)" : notes);
		return out;
	}

	public function toData():TaskDataV1 {
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

	public static function fromData(d:TaskDataV1):Task {
		var notes = d.notes != null ? d.notes : "";
		var tags = d.tags != null ? d.tags : [];
		var project = d.project != null ? d.project : "inbox";
		var updatedAt = d.updatedAt != null ? d.updatedAt : d.createdAt;
		return new Task(d.id, d.title, d.done, notes, tags, project, d.createdAt, updatedAt, d.due);
	}
}
