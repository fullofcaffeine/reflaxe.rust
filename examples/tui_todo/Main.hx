import app.App;
import model.Store;
import rust.tui.Event;
import rust.tui.Tui;

class Main {
	static function main(): Void {
		var store = new Store();
		try {
			store.load();
		} catch (e: Dynamic) {
			// Fall back to demo data if persistence fails (missing permissions, parse errors, etc).
			store.seedDemo();
		}

		var app = new App(store);

		#if tui_headless
		Harness.__link();
		Tui.setHeadless(true);
		#else
		Tui.setHeadless(false);
		#end

		Tui.enter();
		try {
			var running = true;
			while (running) {
				Tui.renderUi(app.view());

				var ev = Tui.pollEvent(50);
				if (ev == None) ev = Tick(50);

				running = !app.handle(ev);
			}
		} catch (e: Dynamic) {
			// Ensure terminal state is restored even on unexpected failures.
		}

		Tui.exit();

		// Best-effort final save.
		if (store.dirty) {
			try {
				store.save();
			} catch (e: Dynamic) {}
		}
	}
}
