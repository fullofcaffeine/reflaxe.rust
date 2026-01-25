import rust.tui.Action;
import rust.tui.Tui;
import Harness;

class Main {
	static function main(): Void {
		var tasks = [
			new Task("bootstrap reflaxe.rust", true),
			new Task("add enums + switch", false),
			new Task("ship ratatui demo", false),
			new Task("Yay!", true),
			new Task("ship ratatui demo", false),
		];

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
}
