#if tui_rusty
import rust.Vec;
import rust.VecTools;
#end
import rust.tui.Action;
import rust.tui.Tui;
import Harness;

class Main {
	static function main(): Void {
		var tasks = buildTasks();

		var selected = 0;
		var running = true;

		#if tui_headless
		Tui.setHeadless(true);
		#else
		Tui.setHeadless(false);
		#end

		Tui.enter();
		while (running) {
			var lines = "";
			var j = 0;
			while (j < tasks.length) {
				lines = lines + tasks[j].line(j == selected) + "\n";
				j = j + 1;
			}

			Tui.render(lines);

			var action = Tui.poll(250);
			if (action == None) continue;

			switch (action) {
				case Up:
					if (selected > 0) selected = selected - 1;
				case Down:
					if (selected < tasks.length - 1) selected = selected + 1;
				case Toggle:
					tasks[selected].toggle();
				case Quit:
					running = false;
				case None:
					// handled above
			}
		}

		Tui.exit();
	}

	static function buildTasks(): Array<Task> {
		#if tui_rusty
		var v = new Vec<Task>();
		v.push(new Task("bootstrap reflaxe.rust", true));
		v.push(new Task("add enums + switch", false));
		v.push(new Task("ship ratatui demo", false));
		v.push(new Task("Yay!", true));
		v.push(new Task("ship ratatui demo", false));

		// Convert once so the UI loop doesn't allocate/clone every frame.
		// Elements are `HxRef<Task>` under the hood, so moving them through the Vec is fine.
		return VecTools.toArray(v);
		#else
		return [
			new Task("bootstrap reflaxe.rust", true),
			new Task("add enums + switch", false),
			new Task("ship ratatui demo", false),
			new Task("Yay!", true),
			new Task("ship ratatui demo", false),
		];
		#end
	}
}
