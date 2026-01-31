import rust.Vec;
import rust.VecTools;
import rust.tui.Action;
import rust.tui.Tui;
import Harness;

class Main {
	static function main(): Void {
		var tasks = new Vec<Task>();
		tasks.push(new Task("bootstrap reflaxe.rust", true));
		tasks.push(new Task("add enums + switch", true));
		tasks.push(new Task("ship ratatui demo", false));
		tasks.push(new Task("ship rusty profile", false));

		// Create an `Array<Task>` view once so we don't clone/convert the Vec on every frame.
		// Elements are `HxRef<Task>` under the hood, so cloning the container preserves identity.
		var a = VecTools.toArray(tasks.clone());

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

			var i = 0;
			while (i < a.length) {
				lines = lines + a[i].line(i == selected) + "\n";
				i = i + 1;
			}

			Tui.render(lines);

			var action = Tui.poll(250);
			if (action == None) continue;

			switch (action) {
				case Up:
					if (selected > 0) selected = selected - 1;
				case Down:
					if (selected < a.length - 1) selected = selected + 1;
				case Toggle:
					a[selected].toggle();
				case Quit:
					running = false;
				case None:
					// handled above
			}
		}
		Tui.exit();
	}
}
