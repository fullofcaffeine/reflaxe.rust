import app.ChatUiApp;
import app.FunnyName;
import domain.ChatCommand;
import domain.ChatEvent;
import profile.RemoteRuntime;
import profile.RuntimeFactory;
import protocol.Codec;
import rust.tui.Event;
import rust.tui.KeyCode;
import rust.tui.KeyMods;
import rust.tui.Tui;
import scenario.ChatServer;
import scenario.LoopbackScenario;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Thread;

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
	static inline final REMOTE_POLL_WAIT_SECONDS:Float = 0.30;
	static inline final SERVER_BOOT_WAIT_SECONDS:Float = 0.12;

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
		if (!StringTools.startsWith(lines[0], "DELIVERED|1|alice|#ops|hello-team|")) {
			return false;
		}
		if (!StringTools.startsWith(lines[1], "DELIVERED|2|bob|#ops|ship-it|")) {
			return false;
		}
		if (!StringTools.startsWith(lines[2], "HISTORY|")) {
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
		var command = Send("zoe", "#ops", "typed-boundary");
		var encoded = Codec.encodeCommand(command);
		var commandOk = switch (Codec.parseCommand(encoded)) {
			case Parsed(Send(user, channel, body)): user == "zoe" && channel == "#ops" && body == "typed-boundary";
			case _:
				false;
		};

		var presenceEncoded = Codec.encodeCommand(Presence("zoe", true));
		var presenceOk = switch (Codec.parseCommand(presenceEncoded)) {
			case Parsed(Presence(user, online)): user == "zoe" && online;
			case _:
				false;
		};

		var event = Delivered(7, "zoe", "#ops", "typed-boundary", 313, "portable");
		var encodedEvent = Codec.encodeEvent(event);
		var eventOk = switch (Codec.parseEvent(encodedEvent)) {
			case EventParsed(Delivered(id, user, channel, body, fingerprint, origin)): id == 7 && user == "zoe" && channel == "#ops" && body == "typed-boundary" && fingerprint == 313 && origin == "portable";
			case _:
				false;
		};

		return commandOk && presenceOk && eventOk;
	}

	public static function renderScenarioShowcase():String {
		var app = seeded();
		sendText(app, "hello neon");
		app.handle(Key(Tab, KeyMods.None));
		sendText(app, "ship release");
		app.handle(Tick(80));
		app.handle(Tick(80));
		return Tui.renderUiToString(app.view(), W, H);
	}

	public static function renderScenarioHelpModal():String {
		var app = seeded();
		app.handle(Key(Char("h"), KeyMods.Ctrl));
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
		if (frame.indexOf("SUNSET LOOPBACK") == -1) {
			return false;
		}
		if (frame.indexOf("party control") == -1) {
			return false;
		}
		if (frame.indexOf("campfire feed") == -1) {
			return false;
		}
		if (frame.indexOf("spark meters") == -1) {
			return false;
		}
		if (frame.indexOf("diag stream") == -1) {
			return false;
		}
		if (frame.indexOf("message launcher") == -1) {
			return false;
		}
		if (frame.indexOf("ship release") == -1) {
			return false;
		}
		return frame.indexOf("💬") != -1 || frame.indexOf("MSG") != -1;
	}

	public static function helpModalVisible():Bool {
		var frame = normalizeFrame(renderScenarioHelpModal());
		if (frame.indexOf("Party Commands") == -1) {
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
		if (a.indexOf("spark meters") == -1) {
			return false;
		}
		if (a.indexOf("message launcher") == -1) {
			return false;
		}
		return a.indexOf("timeline") != -1;
	}

	public static function interactiveInputFlowWorks():Bool {
		var app = seeded();
		sendText(app, "typed ? boundary");
		var frame = normalizeFrame(Tui.renderUiToString(app.view(), W, H));
		return frame.indexOf("typed ? boundary") != -1;
	}

	public static function channelIsolationAndActivityLogWorks():Bool {
		var app = new ChatUiApp(RuntimeFactory.create(), "host_user");
		app.setTerminalSize(W, H);

		sendText(app, "ops-only message");
		app.handle(Key(Tab, KeyMods.None));
		sendText(app, "compiler-only message");
		sendText(app, "/history");

		var compilerFrame = normalizeFrame(Tui.renderUiToString(app.view(), W, H));
		if (compilerFrame.indexOf("compiler-only message") == -1) {
			return false;
		}
		if (compilerFrame.indexOf("ops-only message") != -1) {
			return false;
		}
		if (compilerFrame.indexOf("activity log") == -1) {
			return false;
		}
		if (compilerFrame.indexOf("online") == -1) {
			return false;
		}

		app.handle(Key(Tab, KeyMods.None));
		app.handle(Key(Tab, KeyMods.None));
		app.handle(Key(Tab, KeyMods.None));
		var opsFrame = normalizeFrame(Tui.renderUiToString(app.view(), W, H));
		if (opsFrame.indexOf("ops-only message") == -1) {
			return false;
		}
		if (opsFrame.indexOf("compiler-only message") != -1) {
			return false;
		}
		return true;
	}

	public static function historyPresenceSyncWorks():Bool {
		var runtime = RuntimeFactory.create();
		runtime.handle(Send("guest_peer", "#ops", "joined the room"));

		var app = new ChatUiApp(runtime, "host_user");
		app.setTerminalSize(W, H);
		sendText(app, "/history");
		var frame = normalizeFrame(Tui.renderUiToString(app.view(), W, H));
		return frame.indexOf("host_user") != -1 && frame.indexOf("guest_peer") != -1;
	}

	public static function diagnosticsPanelShowsSignals():Bool {
		var app = seeded();
		sendText(app, "signal check");
		app.handle(Key(Tab, KeyMods.None));
		sendText(app, "/history");
		app.handle(Tick(70));
		var frame = normalizeFrame(Tui.renderUiToString(app.view(), W, H));
		if (frame.indexOf("diag stream") == -1) {
			return false;
		}
		var hasActionSignal = frame.indexOf("send ") != -1
			|| frame.indexOf("channel switched") != -1
			|| frame.indexOf("history snapshot") != -1;
		return hasActionSignal;
	}

	public static function historySnapshotsAvoidSpamLines():Bool {
		var runtime = RuntimeFactory.create();
		runtime.handle(Send("remote_peer", "#ops", "hello there"));

		var app = new ChatUiApp(runtime, "host_user");
		app.setTerminalSize(W, H);
		sendText(app, "/history");
		sendText(app, "/history");
		var frame = normalizeFrame(Tui.renderUiToString(app.view(), W, H));
		if (frame.indexOf("history(") != -1) {
			return false;
		}
		return frame.indexOf("remote_peer") != -1;
	}

	public static function chatServerLogsAreQuietByDefault():Bool {
		return !ChatServer.loggingEnabled();
	}

	public static function remoteRealtimeFlowStable():Bool {
		var port = reserveLocalPort();
		startServer(port);

		var alpha = new RemoteRuntime("127.0.0.1", port, "alpha");
		var beta = new RemoteRuntime("127.0.0.1", port, "beta");

		if (!isDelivered(alpha.handle(Send("alpha", "#ops", "ping alpha")))) {
			return false;
		}
		if (!isDelivered(beta.handle(Send("beta", "#ops", "pong beta")))) {
			return false;
		}

		var snapshot = alpha.handle(History);
		var initialCount = historyCount(snapshot);
		if (initialCount < 2) {
			return false;
		}

		Sys.sleep(REMOTE_POLL_WAIT_SECONDS);
		var firstPoll = beta.pollEvents();
		var firstCount = pollHistoryCount(firstPoll);
		if (firstCount == null) {
			return false;
		}
		var first:Int = firstCount;
		if (first < initialCount) {
			return false;
		}

		Sys.sleep(REMOTE_POLL_WAIT_SECONDS);
		var secondPoll = beta.pollEvents();
		if (secondPoll.length != 0) {
			return false;
		}

		if (!isDelivered(alpha.handle(Send("alpha", "#ops", "third wave")))) {
			return false;
		}

		Sys.sleep(REMOTE_POLL_WAIT_SECONDS);
		var thirdPoll = beta.pollEvents();
		var thirdCount = pollHistoryCount(thirdPoll);
		if (thirdCount == null) {
			return false;
		}
		var third:Int = thirdCount;
		if (third <= first) {
			return false;
		}

		if (historyPresenceCount(thirdPoll[0]) != 2) {
			return false;
		}

		alpha.handle(Presence("alpha", false));
		Sys.sleep(REMOTE_POLL_WAIT_SECONDS);
		var dropPoll = beta.pollEvents();
		var dropCount = pollHistoryCount(dropPoll);
		if (dropCount == null) {
			return false;
		}
		if (historyPresenceCount(dropPoll[0]) != 1) {
			return false;
		}

		return true;
	}

	public static function foldedIdentitySeedAvoidsSaturation():Bool {
		var nearEpochA = 1739990400.100;
		var nearEpochB = 1739990400.900;
		var a = FunnyName.foldTimeForSeed(nearEpochA);
		var b = FunnyName.foldTimeForSeed(nearEpochB);
		return a != b;
	}

	public static function generatedIdentityVariesAcrossCalls():Bool {
		var a = FunnyName.generateAuto(1739990400.100, 7000, 11);
		var b = FunnyName.generateAuto(1739990400.900, 7000, 22);
		return a != b;
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

	static function reserveLocalPort():Int {
		var socket = new Socket();
		socket.bind(new Host("127.0.0.1"), 0);
		var port = socket.host().port;
		socket.close();
		return port;
	}

	static function startServer(port:Int):Void {
		Thread.create(() -> {
			ChatServer.run(RuntimeFactory.create(), "127.0.0.1", port);
		});
		Sys.sleep(SERVER_BOOT_WAIT_SECONDS);
	}

	static function isDelivered(event:ChatEvent):Bool {
		return switch (event) {
			case Delivered(_, _, _, _, _, _):
				true;
			case _:
				false;
		};
	}

	static function historyCount(event:ChatEvent):Int {
		return switch (event) {
			case HistorySnapshot(entries):
				entries.length;
			case _:
				-1;
		};
	}

	static function pollHistoryCount(events:Array<ChatEvent>):Null<Int> {
		if (events.length != 1) {
			return null;
		}
		return switch (events[0]) {
			case HistorySnapshot(entries):
				entries.length;
			case _:
				null;
		};
	}

	static function historyPresenceCount(event:ChatEvent):Int {
		return switch (event) {
			case HistorySnapshot(entries):
				var count = 0;
				for (entry in entries) {
					if (StringTools.startsWith(entry, "@presence:")) {
						count = count + 1;
					}
				}
				count;
			case _:
				-1;
		};
	}
}
