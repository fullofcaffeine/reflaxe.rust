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
	public var prevConfig(default, null): Null<String>;
	public var dir(default, null): String;

	public function new(prevConfig: Null<String>, dir: String) {
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
	public static function __link(): Void {}

	static function seeded(): App {
		var s = new Store();
		s.seedDemo();
		var app = new App(s);
		app.setTerminalSize(W, H);
		return app;
	}

	public static function renderScenarioTasks(): String {
		var app = seeded();
		var events: Array<Event> = [
			Tick(50),
			Key(Down, KeyMods.None),
			Key(Char(" "), KeyMods.None),
			Key(Down, KeyMods.None),
			Key(Enter, KeyMods.None),
			Tick(50),
		];
		for (e in events) app.handle(e);
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioPalette(): String {
		var app = seeded();
		var events: Array<Event> = [
			Key(Char(":"), KeyMods.None),
			Key(Char("g"), KeyMods.None),
			Key(Char("o"), KeyMods.None),
			Key(Char(":"), KeyMods.None),
			Tick(50),
		];
		for (e in events) app.handle(e);
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioEditTitle(): String {
		var app = seeded();
		var events: Array<Event> = [
			Key(Enter, KeyMods.None),
			Key(Char("e"), KeyMods.None),
			Key(Char("X"), KeyMods.None),
			Key(Char("!"), KeyMods.None),
			Key(Enter, KeyMods.None),
			Tick(50),
		];
		for (e in events) app.handle(e);
		return Tui.renderUiToString(app.view(), W, H);
	}

	/**
		Persistence regression: saving then loading preserves task payload fields.
	**/
	public static function persistenceRoundtrip(): Bool {
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
				ok = out.title == "ship compiler"
				&& !out.done
				&& out.notes == "check persistence"
				&& out.tags.length == 2
				&& out.tags[0] == "haxe"
				&& out.tags[1] == "rust"
				&& out.project == "reflaxe";
			}
		} catch (e: haxe.Exception) {
			exitSandbox(sandbox);
			throw e;
		}
		exitSandbox(sandbox);
		return ok;
	}

	/**
		Persistence regression: legacy v0 payloads migrate to v1 and are normalized on disk.
	**/
	public static function persistenceMigratesV0(): Bool {
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
					ok = normalized.indexOf('"version": 1') != -1
						&& normalized.indexOf('"title": "legacy task"') != -1;
				}
			}
		} catch (e: haxe.Exception) {
			exitSandbox(sandbox);
			throw e;
		}
		exitSandbox(sandbox);
		return ok;
	}

	/**
		Persistence regression: autosave uses debounce timing, not every tick.
	**/
	public static function persistenceAutosaveDebounce(): Bool {
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
		} catch (e: haxe.Exception) {
			exitSandbox(sandbox);
			throw e;
		}
		exitSandbox(sandbox);
		return ok;
	}

	static function enterSandbox(label: String): SandboxContext {
		var prev = Sys.getEnv("REFLAXE_RUST_TUI_CONFIG_DIR");
		var dir = newSandboxDir(label);
		Sys.putEnv("REFLAXE_RUST_TUI_CONFIG_DIR", dir);
		return new SandboxContext(prev, dir);
	}

	static function exitSandbox(sandbox: SandboxContext): Void {
		var prev = sandbox.prevConfig;
		Sys.putEnv("REFLAXE_RUST_TUI_CONFIG_DIR", prev != null ? prev : "");
		deleteTreeSafe(sandbox.dir);
	}

	static function newSandboxDir(label: String): String {
		var base = Sys.getEnv("TMPDIR");
		if (base == null || base.length == 0) base = Sys.getEnv("TEMP");
		if (base == null || base.length == 0) base = ".";

		sandboxCounter = sandboxCounter + 1;
		var dir = base + "/reflaxe_rust_tui_todo_" + label + "_" + sandboxCounter;
		if (FileSystem.exists(dir)) {
			deleteTreeSafe(dir);
		}
		FileSystem.createDirectory(dir);
		return dir;
	}

	static function deleteTreeSafe(path: String): Void {
		if (!FileSystem.exists(path)) return;
		if (!FileSystem.isDirectory(path)) {
			try FileSystem.deleteFile(path) catch (_: haxe.Exception) {}
			return;
		}

		for (entry in FileSystem.readDirectory(path)) {
			var child = path + "/" + entry;
			if (FileSystem.isDirectory(child)) {
				deleteTreeSafe(child);
			} else {
				try FileSystem.deleteFile(child) catch (_: haxe.Exception) {}
			}
		}

		try FileSystem.deleteDirectory(path) catch (_: haxe.Exception) {}
	}
}
