import app.ChatUiApp;
import profile.RuntimeFactory;
import rust.tui.Event;
import rust.tui.Tui;

class Main {
	static function main():Void {
		Harness.__link();
		ChatTests.__link();

		var app = new ChatUiApp(RuntimeFactory.create());

		#if chat_tui_headless
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
				if (ev == None) {
					ev = Tick(50);
				}
				running = !app.handle(ev);
			}
		} catch (_:haxe.Exception) {
			// Ensure terminal cleanup on unexpected runtime failures.
		}
		Tui.exit();
	}
}
