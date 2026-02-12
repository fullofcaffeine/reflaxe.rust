package app;

import app.Modal.ConfirmAction;
import app.Modal.InputTarget;
import model.Store;
import model.Task;
import rust.tui.Constraint;
import rust.tui.Event;
import rust.tui.FxKind;
import rust.tui.KeyCode;
import rust.tui.KeyMods;
import rust.tui.LayoutDir;
import rust.tui.StyleToken;
import rust.tui.UiNode;
import util.Fuzzy;

/**
	Todo/productivity TUI app state machine.

	Why
	- This example is intended to be a "battle harness" for reflaxe.rust:
	  - lots of enums + switches
	  - nested data types
	  - sys IO via the Store
	  - deterministic rendering in headless mode

	What
	- Owns the current `Screen`, selection, and modals (palette/input/confirm).
	- Produces a `UiNode` tree per frame.
	- Applies `Event`s to update state.

	How
	- Keep the state machine explicit and easy to test (no hidden global singletons).
	- Text input is implemented in Haxe (buffer + key handling), rendered via modals.
**/
class App {
	static inline final AUTOSAVE_DEBOUNCE_MS = 700;

	public final store:Store;

	public var screen(default, null):Screen;
	public var modal(default, null):Modal;

	var selected:Int = 0;
	var spinnerPhase:Int = 0;
	var fxPhase:Int = 0;
	var dashboardFx:FxKind = Marquee;
	var autosaveElapsedMs:Int = 0;
	var observedDirtyVersion:Int = 0;

	var termWidth:Int = 80;
	var termHeight:Int = 24;

	var statusMsg:String = "";

	public function new(store:Store) {
		this.store = store;
		screen = Tasks;
		modal = None;
		observedDirtyVersion = store.dirtyVersion;
	}

	public static function demo():App {
		var s = new Store();
		s.seedDemo();
		return new App(s);
	}

	public function setTerminalSize(w:Int, h:Int):Void {
		termWidth = w;
		termHeight = h;
	}

	public function handle(ev:Event):Bool {
		switch (ev) {
			case Quit:
				return true;
			case Resize(w, h):
				setTerminalSize(w, h);
			case Tick(dtMs):
				spinnerPhase = (spinnerPhase + 1) % 4;
				var fxStep = Std.int(dtMs / 40);
				if (fxStep < 1)
					fxStep = 1;
				fxPhase = (fxPhase + fxStep) % 2048;
				if (store.dirty) {
					if (store.dirtyVersion != observedDirtyVersion) {
						observedDirtyVersion = store.dirtyVersion;
						autosaveElapsedMs = 0;
					}
					autosaveElapsedMs = autosaveElapsedMs + dtMs;
					if (autosaveElapsedMs >= AUTOSAVE_DEBOUNCE_MS) {
						trySave("autosave");
						autosaveElapsedMs = 0;
						observedDirtyVersion = store.dirtyVersion;
					}
				} else {
					autosaveElapsedMs = 0;
					observedDirtyVersion = store.dirtyVersion;
				}
			case None:
				// no-op
			case Key(code, mods):
				if (modal != None) {
					handleModalKey(code);
				} else {
					if (handleNoModalKey(code, mods))
						return true;
				}
		}
		return false;
	}

	function handleNoModalKey(code:KeyCode, mods:KeyMods):Bool {
		switch (code) {
			case Char("c") if (mods.has(Ctrl)):
				return true;
			case Char("q"):
				return true;
			case Char(":"):
				openPalette("");
				return false;
			case Char("?"):
				screen = Help;
				return false;
			case Tab:
				cycleScreen();
				return false;
			case Char("s") if (mods.has(Ctrl)):
				trySave("save");
				return false;
			case Char("f"):
				cycleFxMode();
				statusMsg = "fx: " + fxModeName();
				return false;

			case Char("t"):
				switch (screen) {
					case Dashboard:
						screen = Tasks;
					case _:
				}
				return false;

			case Esc:
				switch (screen) {
					case Help | Details(_):
						screen = Tasks;
					case _:
				}
				return false;

			case Up:
				switch (screen) {
					case Tasks:
						if (selected > 0) selected = selected - 1;
					case _:
				}
				return false;

			case Down:
				switch (screen) {
					case Tasks:
						if (selected < store.tasks.length - 1) selected = selected + 1;
					case _:
				}
				return false;

			case Enter:
				switch (screen) {
					case Tasks:
						var t = currentTask();
						if (t != null) screen = Details(t.id);
					case _:
				}
				return false;

			case Char(" "):
				switch (screen) {
					case Tasks:
						store.toggleAt(selected);
					case Details(taskId):
						var t = store.findById(taskId);
						if (t != null) {
							t.toggle();
							store.markDirty();
						}
					case _:
				}
				return false;

			case Char("n"):
				switch (screen) {
					case Tasks:
						openInput("New task title", "", NewTaskTitle);
					case _:
				}
				return false;

			case Char("d"):
				switch (screen) {
					case Tasks:
						var t = currentTask();
						if (t != null) modal = Confirm("Delete task?\n" + t.title, DeleteTask(t.id));
					case _:
				}
				return false;

			case Char("e"):
				switch (screen) {
					case Details(taskId):
						var t = store.findById(taskId);
						if (t != null) openInput("Edit title", t.title, EditTaskTitle(t.id));
					case _:
				}
				return false;

			case _:
				return false;
		}
	}

	function handleModalKey(code:KeyCode):Bool {
		switch (modal) {
			case None:
				return false;

			case Confirm(_, action):
				switch (code) {
					case Esc:
						modal = None;
						return true;
					case Enter:
						runConfirm(action);
						modal = None;
						return true;
					case _:
						return true;
				}

			case Input(_, buffer, target):
				switch (code) {
					case Esc:
						modal = None;
						return true;
					case Backspace:
						if (buffer.length > 0)
							buffer = buffer.substr(0, buffer.length - 1);
						modal = Input(getInputPrompt(), buffer, target);
						return true;
					case Enter:
						runInput(target, buffer);
						modal = None;
						return true;
					case Char(ch):
						if (ch != "\n" && ch != "\r") {
							buffer = buffer + ch;
							modal = Input(getInputPrompt(), buffer, target);
						}
						return true;
					case _:
						return true;
				}

			case Palette(query, palSel):
				switch (code) {
					case Esc:
						modal = None;
						return true;
					case Up:
						if (palSel > 0)
							palSel = palSel - 1;
						modal = Palette(query, palSel);
						return true;
					case Down:
						var cmds = filteredCommands(query);
						if (palSel < cmds.length - 1)
							palSel = palSel + 1;
						modal = Palette(query, palSel);
						return true;
					case Backspace:
						if (query.length > 0)
							query = query.substr(0, query.length - 1);
						modal = Palette(query, 0);
						return true;
					case Enter:
						runPalette(query, palSel);
						modal = None;
						return true;
					case Char(ch):
						query = query + ch;
						modal = Palette(query, 0);
						return true;
					case _:
						return true;
				}
		}
	}

	function getInputPrompt():String {
		return switch (modal) {
			case Input(prompt, _, _): prompt;
			case _: "Input";
		}
	}

	function openPalette(query:String):Void {
		modal = Palette(query, 0);
	}

	function openInput(prompt:String, initial:String, target:InputTarget):Void {
		modal = Input(prompt, initial, target);
	}

	function runConfirm(action:ConfirmAction):Void {
		switch (action) {
			case DeleteTask(id):
				store.removeById(id);
				if (selected >= store.tasks.length)
					selected = store.tasks.length - 1;
				if (selected < 0)
					selected = 0;
				statusMsg = "deleted";
		}
	}

	function runInput(target:InputTarget, value:String):Void {
		switch (target) {
			case NewTaskTitle:
				var t = store.add(value.length == 0 ? "Untitled task" : value);
				selected = store.tasks.length - 1;
				screen = Details(t.id);
				statusMsg = "created";
			case EditTaskTitle(id):
				var t = store.findById(id);
				if (t != null) {
					t.setTitle(value.length == 0 ? "Untitled task" : value);
					store.markDirty();
					statusMsg = "updated";
				}
		}
	}

	function runPalette(query:String, sel:Int):Void {
		var cmds = filteredCommands(query);
		if (cmds.length == 0)
			return;
		var i = sel;
		if (i < 0)
			i = 0;
		if (i >= cmds.length)
			i = cmds.length - 1;
		runCommand(cmds[i].id);
	}

	function runCommand(id:CommandId):Void {
		switch (id) {
			case GoDashboard:
				screen = Dashboard;
			case GoTasks:
				screen = Tasks;
			case GoHelp:
				screen = Help;
			case NewTask:
				openInput("New task title", "", NewTaskTitle);
			case ToggleTask:
				store.toggleAt(selected);
			case DeleteTask:
				var t = currentTask();
				if (t != null)
					modal = Confirm("Delete task?\n" + t.title, DeleteTask(t.id));
			case EditTitle:
				var t = currentTask();
				if (t != null)
					openInput("Edit title", t.title, EditTaskTitle(t.id));
			case Save:
				trySave("save");
			case CycleFx:
				cycleFxMode();
				statusMsg = "fx: " + fxModeName();
			case Quit:
				// handled by outer loop via Event.Quit; keep for palette symmetry.
				statusMsg = "quit";
		}
	}

	function trySave(source:String):Void {
		try {
			store.save();
			statusMsg = source + ": ok";
		} catch (e:haxe.Exception) {
			statusMsg = source + ": failed";
		}
	}

	function cycleScreen():Void {
		screen = switch (screen) {
			case Dashboard: Tasks;
			case Tasks: Help;
			case Details(_): Help;
			case Help: Dashboard;
		}
	}

	function cycleFxMode():Void {
		dashboardFx = switch (dashboardFx) {
			case Marquee: Typewriter;
			case Typewriter: Pulse;
			case Pulse: Glitch;
			case Glitch: Marquee;
			case None: Marquee;
		}
	}

	function currentTask():Null<Task> {
		return (selected >= 0 && selected < store.tasks.length) ? store.tasks[selected] : null;
	}

	function commands():Array<Command> {
		return [
			new Command(GoDashboard, "Go: Dashboard", ["dashboard", "home"]),
			new Command(GoTasks, "Go: Tasks", ["tasks", "list"]),
			new Command(GoHelp, "Go: Help", ["help", "keys"]),
			new Command(NewTask, "Task: New", ["new", "create"]),
			new Command(ToggleTask, "Task: Toggle done", ["toggle", "done"]),
			new Command(EditTitle, "Task: Edit title", ["edit", "title"]),
			new Command(DeleteTask, "Task: Delete", ["delete", "remove"]),
			new Command(Save, "Save", ["write", "persist"]),
			new Command(CycleFx, "UI: Cycle dashboard FX", ["fx", "visual", "animation"]),
			new Command(Quit, "Quit", ["exit"]),
		];
	}

	function filteredCommands(query:String):Array<Command> {
		var q = query.toLowerCase();
		var scored:Array<{cmd:Command, score:Int}> = [];
		for (c in commands()) {
			var s = Fuzzy.score(q, c.haystack());
			if (s >= 0)
				scored.push({cmd: c, score: s});
		}
		scored.sort((a, b) -> b.score - a.score);
		return scored.map(x -> x.cmd);
	}

	public function view():UiNode {
		var header = UiNode.Tabs(["Dashboard", "Tasks", "Help"], screenTabIndex(), StyleToken.Title);
		var body = viewBody();
		var footer = UiNode.Paragraph(statusLine(), false, StyleToken.Muted);

		var base = UiNode.Layout(Vertical, [Fixed(1), Fill, Fixed(1)], [header, body, footer]);

		return switch (modal) {
			case None:
				base;
			case _:
				UiNode.Overlay([base, viewModal()]);
		}
	}

	function screenTabIndex():Int {
		return switch (screen) {
			case Dashboard: 0;
			case Tasks | Details(_): 1;
			case Help: 2;
		}
	}

	function viewBody():UiNode {
		return switch (screen) {
			case Dashboard:
				viewDashboard();
			case Tasks:
				viewTasks();
			case Details(id):
				viewDetails(id);
			case Help:
				viewHelp();
		}
	}

	function viewDashboard():UiNode {
		var total = store.tasks.length;
		var done = store.countDone();
		var percent = total == 0 ? 0 : Std.int(done * 100 / total);
		var heroText = "Compiler battle harness online\n" + "mode: " + fxModeName() + " | : palette | f cycle fx | tab screens";
		var hero = UiNode.FxText("Hyperfocus", heroText, dashboardFx, fxPhase, StyleToken.Accent);

		var stats = "Tasks: " + total + "\n" + "Done: " + done + "\n" + "Pending: " + (total - done) + "\n" + "Streak score: " + productivityScore(total, done);
		var rhythm = UiNode.Paragraph("Pulse: " + rhythmLine(30), false, StyleToken.Muted);
		var left = UiNode.Block("Stats", [UiNode.Paragraph(stats, false, StyleToken.Normal), rhythm], StyleToken.Normal);

		var right = UiNode.Block("Progress", [
			UiNode.Gauge("Completion", percent, StyleToken.Success),
			UiNode.Paragraph("\nFlow: " + flowMeter(percent), false, StyleToken.Selected)
		], StyleToken.Normal);

		var bottom = UiNode.Layout(Horizontal, [Percent(56), Percent(44)], [left, right]);
		return UiNode.Layout(Vertical, [Fixed(4), Fill], [hero, bottom]);
	}

	function viewTasks():UiNode {
		var lines:Array<String> = [];
		for (t in store.tasks)
			lines.push(t.listLine());

		var list = UiNode.List("Tasks", lines, selected, StyleToken.Normal);

		if (termWidth >= 100) {
			var t = currentTask();
			var preview = UiNode.Block("Preview", [UiNode.Paragraph(t != null ? t.detailText() : "(none)", true, StyleToken.Normal)], StyleToken.Normal);
			return UiNode.Layout(Horizontal, [Percent(60), Percent(40)], [list, preview]);
		}

		return list;
	}

	function viewDetails(id:String):UiNode {
		var t = store.findById(id);
		var body = t != null ? t.detailText() : "(missing task)";
		return UiNode.Block("Task Details", [UiNode.Paragraph(body, true, StyleToken.Normal)], StyleToken.Normal);
	}

	function viewHelp():UiNode {
		var text = "" + "Keys:\n" + "  q              quit\n" + "  Ctrl+C         quit\n" + "  Tab            cycle screens\n"
			+ "  :              command palette\n" + "  ?              help\n" + "  Ctrl+S         save\n" + "  f              cycle dashboard fx\n" + "\n"
			+ "Tasks:\n" + "  Up/Down        move selection\n" + "  Space          toggle done\n" + "  Enter          details\n"
			+ "  n              new task\n" + "  d              delete task\n" + "\n" + "Details:\n" + "  Esc            back\n"
			+ "  e              edit title\n";
		return UiNode.Block("Help", [UiNode.Paragraph(text, true, StyleToken.Normal)], StyleToken.Normal);
	}

	function viewModal():UiNode {
		return switch (modal) {
			case None:
				UiNode.Empty;

			case Confirm(prompt, _):
				UiNode.Modal("Confirm", [prompt, "", "Enter = yes", "Esc = cancel"], 60, 40, StyleToken.Warning);

			case Input(prompt, buffer, _):
				UiNode.Modal(prompt, ["> " + buffer, "", "Enter = ok", "Esc = cancel"], 70, 40, StyleToken.Accent);

			case Palette(query, palSel):
				var cmds = filteredCommands(query);
				var lines:Array<String> = [];
				lines.push("> " + query);
				lines.push("");
				var i = 0;
				while (i < cmds.length && i < 8) {
					var sel = (i == palSel) ? "> " : "  ";
					lines.push(sel + cmds[i].title);
					i = i + 1;
				}
				if (cmds.length == 0)
					lines.push("(no matches)");
				UiNode.Modal("Command Palette", lines, 80, 60, StyleToken.Accent);
		}
	}

	function statusLine():String {
		var sp = ["|", "/", "-", "\\"][spinnerPhase];
		var done = store.countDone();
		var total = store.tasks.length;
		var dirty = store.dirty ? "*" : "";
		var scr = switch (screen) {
			case Dashboard: "dashboard";
			case Tasks: "tasks";
			case Details(_): "details";
			case Help: "help";
		}
		var msg = statusMsg != null && statusMsg.length > 0 ? (" | " + statusMsg) : "";
		return "[" + sp + "] " + scr + " | " + done + "/" + total + dirty + msg;
	}

	function fxModeName():String {
		return switch (dashboardFx) {
			case Marquee: "marquee";
			case Typewriter: "typewriter";
			case Pulse: "pulse";
			case Glitch: "glitch";
			case None: "none";
		}
	}

	function productivityScore(total:Int, done:Int):Int {
		if (total <= 0)
			return 0;
		var completion = Std.int((done * 100) / total);
		return completion + (done * 3) + (total - done);
	}

	function rhythmLine(width:Int):String {
		var glyphs = [".", ":", "-", "=", "+", "*", "#", "%", "@", "*", "+"];
		var out = "";
		var i = 0;
		while (i < width) {
			var idx = (fxPhase + i + (store.tasks.length * 2)) % glyphs.length;
			out = out + glyphs[idx];
			i = i + 1;
		}
		return out;
	}

	function flowMeter(percent:Int):String {
		var p = percent;
		if (p < 0)
			p = 0;
		if (p > 100)
			p = 100;
		var filled = Std.int((p * 10) / 100);
		var out = "";
		var i = 0;
		while (i < 10) {
			out = out + (i < filled ? "#" : ".");
			i = i + 1;
		}
		return "[" + out + "]";
	}
}
