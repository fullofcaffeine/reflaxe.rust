#if tui_rusty
import rust.Vec;
import rust.VecTools;
#end
import rust.tui.Action;
import rust.tui.Tui;

/**
 * Deterministic runner for CI tests.
 *
 * Why:
 * - TUIs are interactive, so regressions can be hard to catch with unit tests alone.
 * - We use ratatui's `TestBackend` (via `Tui.renderToString`) to render frames off-screen and assert
 *   on the output in `cargo test`, without requiring a real terminal.
 *
 * What:
 * - Applies a scripted sequence of `Action`s to a small todo list and returns the rendered frame as
 *   a string.
 *
 * How:
 * - Keep this file "pure Haxe" (no `__rust__`): all native logic lives behind `std/` APIs.
 * - Rust tests call into the compiled output at `crate::harness::Harness::render_scenario()`.
 */
@:keep
class Harness {
	public static function renderScenario(): String {
		var tasks = buildTasks();

		var selected = 0;

		var actions: Array<Action> = [Down, Toggle, Down, Toggle, Up];
		for (action in actions) {
			switch (action) {
				case Up:
					if (selected > 0) selected = selected - 1;
				case Down:
					if (selected < tasks.length - 1) selected = selected + 1;
				case Toggle:
					tasks[selected].toggle();
				case Quit | None:
					// not used by this scenario
			}
		}

		return Tui.renderToString(buildLines(tasks, selected));
	}

	static function buildLines(tasks: Array<Task>, selected: Int): String {
		var lines = "";
		var i = 0;
		while (i < tasks.length) {
			lines = lines + tasks[i].line(i == selected) + "\n";
			i = i + 1;
		}
		return lines;
	}

	static function buildTasks(): Array<Task> {
		#if tui_rusty
		var v = new Vec<Task>();
		v.push(new Task("bootstrap reflaxe.rust", true));
		v.push(new Task("add enums + switch", false));
		v.push(new Task("ship ratatui demo", false));
		return VecTools.toArray(v);
		#else
		return [
			new Task("bootstrap reflaxe.rust", true),
			new Task("add enums + switch", false),
			new Task("ship ratatui demo", false),
		];
		#end
	}
}
