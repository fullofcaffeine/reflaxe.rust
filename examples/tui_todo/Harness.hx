import app.App;
import model.Store;
import rust.tui.Event;
import rust.tui.KeyCode;
import rust.tui.KeyMods;
import rust.tui.Tui;

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
}
