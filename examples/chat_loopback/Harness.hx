import app.ChatUiApp;
import domain.ChatCommand;
import profile.RuntimeFactory;
import protocol.Codec;
import rust.tui.Event;
import rust.tui.KeyCode;
import rust.tui.KeyMods;
import rust.tui.Tui;
import scenario.LoopbackScenario;

/**
 * Harness
 *
 * Why
 * - Exposes deterministic entrypoints for cargo tests without requiring interactive terminals.
 * - Keeps both protocol-level and UI-level regressions easy to validate in CI.
 *
 * What
 * - Runs the loopback transcript scenario.
 * - Renders scripted modern TUI scenes through `Tui.renderUiToString`.
 * - Exposes parser/codec assertions and profile label helpers.
 *
 * How
 * - `Main` always calls `Harness.__link()` so this module is reachable in all compile variants.
 */
class Harness {
	static inline final W = 108;
	static inline final H = 32;

	public static function __link():Void {}

	public static function profileName():String {
		return RuntimeFactory.create().profileName();
	}

	public static function runTranscript():String {
		var runtime = RuntimeFactory.create();
		var lines = LoopbackScenario.run(runtime);
		return lines.join("\n");
	}

	public static function transcriptHasExpectedShape():Bool {
		var profile = profileName();
		var transcript = runTranscript();
		var lines = transcript.split("\n");
		if (lines.length != 4) {
			return false;
		}
		if (!StringTools.startsWith(lines[0], "DELIVERED|1|alice|hello-team|")) {
			return false;
		}
		if (!StringTools.startsWith(lines[1], "DELIVERED|2|bob|ship-it|")) {
			return false;
		}
		if (!StringTools.startsWith(lines[2], "HISTORY|2|")) {
			return false;
		}
		if (!StringTools.startsWith(lines[3], "BYE|")) {
			return false;
		}
		return lines[3].indexOf(profile) != -1;
	}

	public static function parserRejectsInvalidCommand():Bool {
		return LoopbackScenario.invalidCommandRejected(RuntimeFactory.create());
	}

	public static function codecRoundtripWorks():Bool {
		var command = Send("zoe", "typed-boundary");
		var encoded = Codec.encodeCommand(command);
		return switch (Codec.parseCommand(encoded)) {
			case Parsed(Send(user, body)): user == "zoe" && body == "typed-boundary";
			case _:
				false;
		};
	}

	public static function renderScenarioShowcase():String {
		var app = seeded();
		sendText(app, "hello neon");
		sendText(app, "ship release");
		app.handle(Key(Tab, KeyMods.None));
		app.handle(Tick(80));
		app.handle(Tick(80));
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioHelpModal():String {
		var app = seeded();
		app.handle(Key(Char("?"), KeyMods.None));
		app.handle(Tick(60));
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioPulse():String {
		var app = seeded();
		sendText(app, "pulse check");
		app.handle(Key(Tab, KeyMods.None));
		app.handle(Key(Tab, KeyMods.None));
		app.handle(Tick(70));
		app.handle(Tick(70));
		app.handle(Tick(70));
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function showcaseHasExpectedLayout():Bool {
		var frame = normalizeFrame(renderScenarioShowcase());
		if (frame.split("\n").length != H) {
			return false;
		}
		if (frame.indexOf("NEON LOOPBACK") == -1) {
			return false;
		}
		if (frame.indexOf("relay matrix") == -1) {
			return false;
		}
		if (frame.indexOf("live feed") == -1) {
			return false;
		}
		if (frame.indexOf("telemetry") == -1) {
			return false;
		}
		if (frame.indexOf("composer") == -1) {
			return false;
		}
		if (frame.indexOf("hello neon") == -1) {
			return false;
		}
		return frame.indexOf("💬") != -1 || frame.indexOf("MSG") != -1;
	}

	public static function helpModalVisible():Bool {
		var frame = normalizeFrame(renderScenarioHelpModal());
		if (frame.indexOf("Command Cheatsheet") == -1) {
			return false;
		}
		if (frame.indexOf("/history") == -1) {
			return false;
		}
		return frame.indexOf("Ctrl+C/q") != -1;
	}

	public static function pulseSceneDeterministic():Bool {
		var a = normalizeFrame(renderScenarioPulse());
		var b = normalizeFrame(renderScenarioPulse());
		if (a != b) {
			return false;
		}
		if (a.indexOf("telemetry") == -1) {
			return false;
		}
		if (a.indexOf("composer") == -1) {
			return false;
		}
		return a.indexOf("timeline") != -1;
	}

	public static function interactiveInputFlowWorks():Bool {
		var app = seeded();
		sendText(app, "typed boundary");
		var frame = normalizeFrame(Tui.renderUiToString(app.view(), W, H));
		return frame.indexOf("typed boundary") != -1;
	}

	static function seeded():ChatUiApp {
		var app = new ChatUiApp(RuntimeFactory.create());
		app.setTerminalSize(W, H);
		return app;
	}

	static function sendText(app:ChatUiApp, value:String):Void {
		for (i in 0...value.length) {
			app.handle(Key(Char(value.charAt(i)), KeyMods.None));
		}
		app.handle(Key(Enter, KeyMods.None));
	}

	static function normalizeFrame(value:String):String {
		var trimmed = trimTrailingLineBreaks(value);
		var lines = trimmed.split("\n");
		for (i in 0...lines.length) {
			lines[i] = rtrim(lines[i]);
		}
		return lines.join("\n");
	}

	static function trimTrailingLineBreaks(value:String):String {
		var out = value;
		while (out.length > 0) {
			var last = out.charAt(out.length - 1);
			if (last == "\n" || last == "\r") {
				out = out.substr(0, out.length - 1);
			} else {
				break;
			}
		}
		return out;
	}

	static function rtrim(value:String):String {
		var i = value.length;
		while (i > 0) {
			var c = value.charAt(i - 1);
			if (c == " " || c == "\r" || c == "\t") {
				i = i - 1;
			} else {
				break;
			}
		}
		return value.substr(0, i);
	}
}
