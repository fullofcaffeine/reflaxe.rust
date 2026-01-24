import rust.tui.TuiDemo;

class Main {
	static function main(): Void {
		var tasks = [
			new Task("bootstrap reflaxe.rust", true),
			new Task("add enums + switch", false),
			new Task("ship ratatui demo", false),
		];

		var selected = 0;
		var running = true;

		TuiDemo.enter();
		while (running) {
			var lines = "";
			var j = 0;
			while (j < tasks.length) {
				lines = lines + tasks[j].line(j == selected) + "\n";
				j = j + 1;
			}

			TuiDemo.render(lines);

			var code = TuiDemo.pollAction(250);
			if (code == 0) continue;

			var action = switch (code) {
				case 1: Action.Up;
				case 2: Action.Down;
				case 3: Action.Toggle;
				case 4: Action.Quit;
				case _: Action.Quit;
			};

			switch (action) {
				case Up:
					if (selected > 0) selected = selected - 1;
				case Down:
					if (selected < tasks.length - 1) selected = selected + 1;
				case Toggle:
					tasks[selected].toggle();
				case Quit:
					running = false;
			}
		}

		TuiDemo.exit();
	}
}
