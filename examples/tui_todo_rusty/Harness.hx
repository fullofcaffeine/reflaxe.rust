import rust.Vec;
import rust.VecTools;
import rust.tui.Action;
import rust.tui.Tui;

/**
 * Deterministic runner for CI tests (Rusty profile).
 *
 * Uses `Tui.renderToString` (ratatui TestBackend) so `cargo test` can assert on the frame output
 * without requiring a real terminal.
 */
@:keep
class Harness {
	public static function renderScenario(): String {
		var tasks = new Vec<Task>();
		tasks.push(new Task("bootstrap reflaxe.rust", true));
		tasks.push(new Task("add enums + switch", false));
		tasks.push(new Task("ship ratatui demo", false));

		var selected = 0;

		var actions: Array<Action> = [Down, Toggle, Down, Toggle, Up];
		for (action in actions) {
			var a = VecTools.toArray(tasks.clone());
			switch (action) {
				case Up:
					if (selected > 0) selected = selected - 1;
				case Down:
					if (selected < a.length - 1) selected = selected + 1;
				case Toggle:
					a[selected].toggle();
				case Quit | None:
					// not used by this scenario
			}
		}

		return Tui.renderToString(buildLines(tasks, selected));
	}

	static function buildLines(tasks: Vec<Task>, selected: Int): String {
		var lines = "";
		var a = VecTools.toArray(tasks.clone());
		var i = 0;
		while (i < a.length) {
			lines = lines + a[i].line(i == selected) + "\n";
			i = i + 1;
		}
		return lines;
	}
}

