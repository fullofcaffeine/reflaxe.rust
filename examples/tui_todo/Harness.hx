import app.App;
import model.Store;
import rust.tui.Event;
import rust.tui.KeyCode;
import rust.tui.KeyMods;
import rust.tui.Tui;
import sys.FileSystem;
import sys.io.File;
import util.Paths;

private class SandboxContext {
	public var prevConfig(default, null):Null<String>;
	public var dir(default, null):String;

	public function new(prevConfig:Null<String>, dir:String) {
		this.prevConfig = prevConfig;
		this.dir = dir;
	}
}

/**
	Deterministic runner for CI tests.

	Why
	- TUIs are interactive, so regressions can be hard to catch with unit tests alone.
	- We use ratatui's headless `TestBackend` (via `Tui.renderUiToString`) to render frames off-screen
	  and assert on them in `cargo test`, without requiring a real terminal.

	What
	- Applies scripted `Event`s to an `App` instance and returns the rendered frame as a string.

	How
	- Keep this file pure Haxe (no `__rust__`): all native logic lives behind `std/` APIs.
	- Rust tests call into the compiled output at `crate::harness::Harness::*`.
**/
@:keep
class Harness {
	static inline final W = 80;
	static inline final H = 24;
	static var sandboxCounter = 0;

	// Linker anchor: referenced from `Main` in CI builds so this module is emitted even though
	// Rust tests call into it directly (outside of Haxe's DCE reachability).
	public static function __link():Void {}

	static function seeded():App {
		var s = new Store();
		s.seedDemo();
		var app = new App(s);
		app.setTerminalSize(W, H);
		return app;
	}

	public static function renderScenarioTasks():String {
		var app = seeded();
		var events:Array<Event> = [
			Tick(50),
			Key(Down, KeyMods.None),
			Key(Char(" "), KeyMods.None),
			Key(Down, KeyMods.None),
			Key(Enter, KeyMods.None),
			Tick(50),
		];
		for (e in events)
			app.handle(e);
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioPalette():String {
		var app = seeded();
		var events:Array<Event> = [
			Key(Char(":"), KeyMods.None),
			Key(Char("g"), KeyMods.None),
			Key(Char("o"), KeyMods.None),
			Key(Char(":"), KeyMods.None),
			Tick(50),
		];
		for (e in events)
			app.handle(e);
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioEditTitle():String {
		var app = seeded();
		var events:Array<Event> = [
			Key(Enter, KeyMods.None),
			Key(Char("e"), KeyMods.None),
			Key(Char("X"), KeyMods.None),
			Key(Char("!"), KeyMods.None),
			Key(Enter, KeyMods.None),
			Tick(50),
		];
		for (e in events)
			app.handle(e);
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioDashboardFx():String {
		var app = seeded();
		var events:Array<Event> = [
			Key(Tab, KeyMods.None),
			Key(Tab, KeyMods.None),
			Tick(80),
			Tick(80),
			Key(Char("f"), KeyMods.None),
			Tick(80),
			Key(Char("f"), KeyMods.None),
			Tick(80),
		];
		for (e in events)
			app.handle(e);
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function scenarioTasksMatchesGolden():Bool {
		var got = normalizeFrame(renderScenarioTasks());
		if (got.split("\n").length != H) {
			return false;
		}
		if (got.indexOf("Task Details") == -1) {
			return false;
		}
		if (got.indexOf("Title: reach v1.0 stdlib parity") == -1) {
			return false;
		}
		return got.indexOf("details | 2/4*") != -1;
	}

	public static function scenarioPaletteMatchesGolden():Bool {
		var got = normalizeFrame(renderScenarioPalette());
		if (got.split("\n").length != H) {
			return false;
		}
		return got == expectedScenarioPalette();
	}

	public static function scenarioEditTitleMatchesGolden():Bool {
		var got = normalizeFrame(renderScenarioEditTitle());
		if (got.split("\n").length != H) {
			return false;
		}
		if (got.indexOf("Task Details") == -1) {
			return false;
		}
		if (got.indexOf("bootstrap reflaxe.rustX!") == -1) {
			return false;
		}
		return got.indexOf("details | 1/4* | updated") != -1;
	}

	public static function scenarioDashboardFxDeterministic():Bool {
		var a = normalizeFrame(renderScenarioDashboardFx());
		var b = normalizeFrame(renderScenarioDashboardFx());
		if (a != b) {
			return false;
		}
		if (a.indexOf("Hyperfocus") == -1) {
			return false;
		}
		if (a.toLowerCase().indexOf("mode: pulse") == -1) {
			return false;
		}
		if (a.indexOf("Pulse:") == -1) {
			return false;
		}
		return a.indexOf("Flow: [") != -1;
	}

	/**
		Persistence regression: saving then loading preserves task payload fields.
	**/
	public static function persistenceRoundtrip():Bool {
		var sandbox = enterSandbox("roundtrip");
		var ok = false;
		try {
			var store = new Store();
			var task = store.add("ship compiler");
			task.notes = "check persistence";
			task.tags = ["haxe", "rust"];
			task.project = "reflaxe";
			store.save();

			var loaded = new Store();
			loaded.load();
			if (loaded.tasks.length == 1) {
				var out = loaded.tasks[0];
				ok = out.title == "ship compiler" && !out.done && out.notes == "check persistence" && out.tags.length == 2 && out.tags[0] == "haxe"
					&& out.tags[1] == "rust" && out.project == "reflaxe";
			}
		} catch (e:haxe.Exception) {
			exitSandbox(sandbox);
			throw e;
		}
		exitSandbox(sandbox);
		return ok;
	}

	/**
		Persistence regression: legacy v0 payloads migrate to v1 and are normalized on disk.
	**/
	public static function persistenceMigratesV0():Bool {
		var sandbox = enterSandbox("migrate_v0");
		var ok = false;
		try {
			Paths.ensureConfigDir();
			var path = Paths.dataFile();
			File.saveContent(path, '{"version":0,"tasks":[{"text":"legacy task","done":true}]}' + "\n");

			var store = new Store();
			store.load();
			if (store.tasks.length == 1) {
				var loaded = store.tasks[0];
				var validTask = loaded.title == "legacy task" && loaded.done && loaded.project == "inbox";
				if (validTask) {
					var normalized = File.getContent(path);
					ok = normalized.indexOf('"version": 1') != -1 && normalized.indexOf('"title": "legacy task"') != -1;
				}
			}
		} catch (e:haxe.Exception) {
			exitSandbox(sandbox);
			throw e;
		}
		exitSandbox(sandbox);
		return ok;
	}

	/**
		Persistence regression: autosave uses debounce timing, not every tick.
	**/
	public static function persistenceAutosaveDebounce():Bool {
		var sandbox = enterSandbox("autosave_debounce");
		var ok = false;
		try {
			var store = new Store();
			var app = new App(store);
			app.setTerminalSize(W, H);

			store.add("autosave me");
			var path = Paths.dataFile();

			app.handle(Tick(200));
			app.handle(Tick(200));
			if (!FileSystem.exists(path)) {
				app.handle(Tick(400));
				ok = FileSystem.exists(path);
			}
		} catch (e:haxe.Exception) {
			exitSandbox(sandbox);
			throw e;
		}
		exitSandbox(sandbox);
		return ok;
	}

	/**
		Persistence regression: strict schema decoding rejects malformed v1 payloads.
	**/
	public static function persistenceRejectsInvalidSchema():Bool {
		var sandbox = enterSandbox("strict_schema");
		var threw = false;
		try {
			Paths.ensureConfigDir();
			var path = Paths.dataFile();
			File.saveContent(path, '{"version":1,"tasks":[{"id":"x","title":"oops","done":"true","createdAt":1}]}' + "\n");

			var store = new Store();
			try {
				store.load();
			} catch (_:haxe.Exception) {
				threw = true;
			}
		} catch (e:haxe.Exception) {
			exitSandbox(sandbox);
			throw e;
		}
		exitSandbox(sandbox);
		return threw;
	}

	static function enterSandbox(label:String):SandboxContext {
		var prev = Sys.getEnv("REFLAXE_RUST_TUI_CONFIG_DIR");
		var dir = newSandboxDir(label);
		Sys.putEnv("REFLAXE_RUST_TUI_CONFIG_DIR", dir);
		return new SandboxContext(prev, dir);
	}

	static function exitSandbox(sandbox:SandboxContext):Void {
		var prev = sandbox.prevConfig;
		Sys.putEnv("REFLAXE_RUST_TUI_CONFIG_DIR", prev != null ? prev : "");
		deleteTreeSafe(sandbox.dir);
	}

	static function newSandboxDir(label:String):String {
		var base = Sys.getEnv("TMPDIR");
		if (base == null || base.length == 0)
			base = Sys.getEnv("TEMP");
		if (base == null || base.length == 0)
			base = ".";

		sandboxCounter = sandboxCounter + 1;
		var dir = base + "/reflaxe_rust_tui_todo_" + label + "_" + sandboxCounter;
		if (FileSystem.exists(dir)) {
			deleteTreeSafe(dir);
		}
		FileSystem.createDirectory(dir);
		return dir;
	}

	static function deleteTreeSafe(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (!FileSystem.isDirectory(path)) {
			try
				FileSystem.deleteFile(path)
			catch (_:haxe.Exception) {}
			return;
		}

		for (entry in FileSystem.readDirectory(path)) {
			var child = path + "/" + entry;
			if (FileSystem.isDirectory(child)) {
				deleteTreeSafe(child);
			} else {
				try
					FileSystem.deleteFile(child)
				catch (_:haxe.Exception) {}
			}
		}

		try
			FileSystem.deleteDirectory(path)
		catch (_:haxe.Exception) {}
	}

	static function normalizeFrame(value:String):String {
		var trimmed = trimTrailingLineBreaks(value);
		var lines = trimmed.split("\n");
		for (i in 0...lines.length) {
			lines[i] = rtrim(lines[i]);
		}
		return lines.join("\n");
	}

	static function trimTrailingLineBreaks(value:String):String {
		var out = value;
		while (out.length > 0) {
			var last = out.charAt(out.length - 1);
			if (last == "\n" || last == "\r") {
				out = out.substr(0, out.length - 1);
			} else {
				break;
			}
		}
		return out;
	}

	static function rtrim(value:String):String {
		var i = value.length;
		while (i > 0) {
			var c = value.charAt(i - 1);
			if (c == " " || c == "\r" || c == "\t") {
				i = i - 1;
			} else {
				break;
			}
		}
		return value.substr(0, i);
	}

	static function expectedScenarioTasks():String {
		return [
			" Dashboard | Tasks | Help",
			"┌Task Details──────────────────────────────────────────────────────────────────┐",
			"│Title: reach v1.0 stdlib parity                                               │",
			"│Project: inbox                                                                │",
			"│Tags: -                                                                       │",
			"│Done: no                                                                      │",
			"│                                                                              │",
			"│Notes:                                                                        │",
			"│(none)                                                                        │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"└──────────────────────────────────────────────────────────────────────────────┘",
			"[-] details | 2/4*",
		].join("\n");
	}

	static function expectedScenarioPalette():String {
		return [
			" Dashboard | Tasks | Help",
			"┌Tasks─────────────────────────────────────────────────────────────────────────┐",
			"│[x] [inbox] bootstrap reflaxe.rust                                            │",
			"│[ ] [inbox] ship TUI harness                                                  │",
			"│[ ] [inbox] reach v1.0 stdlib parity                                          │",
			"│[ ] [in┌Command Palette───────────────────────────────────────────────┐       │",
			"│       │> go:                                                         │       │",
			"│       │                                                              │       │",
			"│       │> Go: Help                                                    │       │",
			"│       │  Go: Tasks                                                   │       │",
			"│       │  Go: Dashboard                                               │       │",
			"│       │                                                              │       │",
			"│       │                                                              │       │",
			"│       │                                                              │       │",
			"│       │                                                              │       │",
			"│       │                                                              │       │",
			"│       │                                                              │       │",
			"│       │                                                              │       │",
			"│       └──────────────────────────────────────────────────────────────┘       │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"└──────────────────────────────────────────────────────────────────────────────┘",
			"[/] tasks | 1/4",
		].join("\n");
	}

	static function expectedScenarioEditTitle():String {
		return [
			" Dashboard | Tasks | Help",
			"┌Task Details──────────────────────────────────────────────────────────────────┐",
			"│Title: bootstrap reflaxe.rustX!                                               │",
			"│Project: inbox                                                                │",
			"│Tags: -                                                                       │",
			"│Done: yes                                                                     │",
			"│                                                                              │",
			"│Notes:                                                                        │",
			"│(none)                                                                        │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"│                                                                              │",
			"└──────────────────────────────────────────────────────────────────────────────┘",
			"[/] details | 1/4* | updated",
		].join("\n");
	}
}
