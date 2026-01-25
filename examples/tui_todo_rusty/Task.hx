class Task {
	public var text: String;
	public var done: Bool;

	public function new(text: String, done: Bool) {
		this.text = text;
		this.done = done;
	}

	public function toggle(): Void {
		this.done = !this.done;
	}

	public function line(selected: Bool): String {
		var sel = selected ? ">" : " ";
		var mark = this.done ? "x" : " ";
		return sel + "[" + mark + "] " + this.text;
	}
}

