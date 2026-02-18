import app.App;
import model.Store;
import rust.tui.Event;
import rust.tui.Tui;

class Main {
	static function main():Void {
		var store = new Store();
		#if tui_ephemeral
		store.seedDemo();
		#else
		try {
			store.load();
		} catch (e:haxe.Exception) {
			// Fall back to demo data if persistence fails (missing permissions, parse errors, etc).
			store.seedDemo();
		}
		#end

		var app = new App(store);

		// Always link the deterministic harness module so `cargo test` works for both
		// default and CI compile variants.
		Harness.__link();
		TuiTests.__link();
		#if tui_headless
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
				if (ev == None)
					ev = Tick(50);

				running = !app.handle(ev);
			}
		} catch (e:haxe.Exception) {
			// Ensure terminal state is restored even on unexpected failures.
		}

		Tui.exit();

		#if !tui_ephemeral
		// Best-effort final save.
		if (store.dirty) {
			try {
				store.save();
			} catch (e:haxe.Exception) {}
		}
		#end
	}
}
