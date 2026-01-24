import rust.tui.TuiDemo;

class Main {
	static function main(): Void {
		var tasks = [
			new Task("bootstrap reflaxe.rust", true),
			new Task("add enums + switch", false),
			new Task("ship ratatui demo", false),
		];

		var actions = [
			Action.Down,
			Action.Toggle,
			Action.Down,
			Action.Toggle,
			Action.Up,
			Action.Quit,
		];

		var selected = 0;
		var frame = 0;
		var i = 0;

		while (i < actions.length) {
			var action = actions[i];

			switch (action) {
				case Up:
					if (selected > 0) selected = selected - 1;
				case Down:
					if (selected < tasks.length - 1) selected = selected + 1;
				case Toggle:
					tasks[selected].toggle();
				case Quit:
					break;
			}

			var lines = "";
			var j = 0;
			while (j < tasks.length) {
				lines = lines + tasks[j].line(j == selected) + "\n";
				j = j + 1;
			}

			TuiDemo.runFrame(frame, lines);
			frame = frame + 1;
			i = i + 1;
		}
	}
}
