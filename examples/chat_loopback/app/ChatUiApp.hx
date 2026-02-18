package app;

import domain.ChatCommand;
import domain.ChatEvent;
import profile.ChatRuntime;
import rust.tui.Constraint;
import rust.tui.Event;
import rust.tui.FxKind;
import rust.tui.KeyCode;
import rust.tui.KeyMods;
import rust.tui.LayoutDir;
import rust.tui.StyleToken;
import rust.tui.UiNode;

/**
	ChatUiApp

	Why
	- `chat_loopback` should be both a profile-comparison harness and a visually impressive,
	  modern interactive TUI.
	- We still need deterministic rendering for CI (`Tui.renderUiToString`) while keeping rich motion.

	What
	- Event-driven chat state machine with:
	  - neon control-rail layout
	  - animated telemetry panel
	  - timeline + composer + modal command help
	  - typed command dispatch through `profile.ChatRuntime`

	How
	- All behavior is modeled in typed Haxe (`Event`, `UiNode`, `ChatCommand`, `ChatEvent`).
	- Animation advances only through explicit `Tick(dtMs)`, so tests can replay exact frame sequences.
	- Emoji is opt-in by capability: wide terminals show emoji by default, otherwise we auto-fallback
	  to ASCII-safe markers (`REFLAXE_RUST_ASCII_ONLY=1` forces ASCII).
**/
class ChatUiApp {
	static inline final MAX_TIMELINE = 80;

	final runtime:ChatRuntime;
	final channels:Array<String>;
	final operators:Array<String>;
	final operatorMoods:Array<String>;

	public var shouldQuit(default, null):Bool = false;
	public var inputBuffer(default, null):String = "";

	var timeline:Array<String>;
	var selectedChannel:Int = 0;
	var selectedOperator:Int = 0;
	var fxPhase:Int = 0;
	var linkPercent:Int = 72;
	var commandCount:Int = 0;
	var statusLine:String = "relay online";
	var showHelp:Bool = false;
	var termWidth:Int = 100;
	var termHeight:Int = 30;

	public function new(runtime:ChatRuntime) {
		this.runtime = runtime;
		this.timeline = [];
		this.channels = ["#ops", "#compiler", "#shiproom", "#nightwatch"];
		this.operators = ["alice", "bob", "zoe", "maya"];
		this.operatorMoods = ["calm", "shipping", "debug", "hyperfocus"];

		var bootIcon = emojiEnabled() ? "🚀" : "BOOT";
		addTimeline(bootIcon + " neon loopback online (" + runtime.profileName() + ")");
		addTimeline((emojiEnabled() ? "🧭" : "TIP") + " type a message then press Enter");
		addTimeline((emojiEnabled() ? "⚡" : "CMD") + " commands: /history /help /clear /quit");
	}

	public function setTerminalSize(width:Int, height:Int):Void {
		termWidth = width;
		termHeight = height;
	}

	public function handle(ev:Event):Bool {
		switch (ev) {
			case Quit:
				shouldQuit = true;
			case Resize(w, h):
				setTerminalSize(w, h);
			case Tick(dtMs):
				advanceAnimation(dtMs);
			case None:
				// no-op
			case Key(code, mods):
				handleKey(code, mods);
		}
		return shouldQuit;
	}

	public function view():UiNode {
		var base = Layout(Vertical, [Fixed(1), Fill, Fixed(5), Fixed(1)], [topTabs(), bodyPane(), composerPane(), statusBar()]);
		if (showHelp) {
			return Overlay([base, helpModal()]);
		}
		return base;
	}

	function advanceAnimation(dtMs:Int):Void {
		var step = Std.int(dtMs / 35);
		if (step < 1) {
			step = 1;
		}
		fxPhase = (fxPhase + step) % 4096;
		linkPercent = 58 + ((fxPhase * 7 + commandCount * 11) % 42);
	}

	function handleKey(code:KeyCode, mods:KeyMods):Void {
		switch (code) {
			case Char("c") if (mods.has(Ctrl)):
				shouldQuit = true;
			case Char("?"):
				showHelp = !showHelp;
			case Esc:
				if (showHelp) {
					showHelp = false;
				} else {
					inputBuffer = "";
				}
			case Tab:
				selectedChannel = (selectedChannel + 1) % channels.length;
				statusLine = "room -> " + channels[selectedChannel];
			case Up:
				if (selectedOperator > 0) {
					selectedOperator = selectedOperator - 1;
				}
			case Down:
				if (selectedOperator < operators.length - 1) {
					selectedOperator = selectedOperator + 1;
				}
			case Backspace:
				if (inputBuffer.length > 0) {
					inputBuffer = inputBuffer.substr(0, inputBuffer.length - 1);
				}
			case Enter:
				submitInput();
			case Char("q") if (inputBuffer.length == 0 && !showHelp):
				shouldQuit = true;
			case Char(ch):
				if (ch != "\n" && ch != "\r") {
					inputBuffer = inputBuffer + ch;
				}
			case _:
				// no-op
		}
	}

	function submitInput():Void {
		var raw = StringTools.trim(inputBuffer);
		inputBuffer = "";

		if (raw.length == 0) {
			statusLine = "composer empty";
			return;
		}

		if (StringTools.startsWith(raw, "/")) {
			runSlashCommand(raw);
			return;
		}

		var speaker = operators[selectedOperator];
		applyEvent(runtime.handle(Send(speaker, raw)));
	}

	function runSlashCommand(raw:String):Void {
		switch (raw) {
			case "/help":
				showHelp = true;
				statusLine = "help overlay opened";
			case "/history":
				applyEvent(runtime.handle(History));
			case "/clear":
				timeline = [];
				addTimeline((emojiEnabled() ? "🧹" : "CLR") + " timeline cleared");
				statusLine = "timeline reset";
			case "/quit":
				applyEvent(runtime.handle(Quit));
			case _:
				addTimeline((emojiEnabled() ? "⚠" : "ERR") + " unknown command `" + raw + "`");
				statusLine = "unknown command";
		}
	}

	function applyEvent(event:ChatEvent):Void {
		switch (event) {
			case Delivered(id, user, body, fingerprint, origin):
				commandCount = commandCount + 1;
				addTimeline(chatLead() + " " + id + " " + user + " ▸ " + body + "  [" + origin + ":" + fingerprint + "]");
				statusLine = "delivered via " + origin;
			case HistorySnapshot(entries):
				var compact = entries.length > 0 ? entries.join(" · ") : "<empty>";
				addTimeline((emojiEnabled() ? "🗂" : "HIS") + " history(" + entries.length + ") " + compact);
				statusLine = "history refreshed";
			case Bye(reason):
				addTimeline((emojiEnabled() ? "👋" : "BYE") + " " + reason);
				statusLine = "session closed";
				shouldQuit = true;
			case Rejected(reason):
				addTimeline((emojiEnabled() ? "⚠" : "REJ") + " " + reason);
				statusLine = "runtime rejected input";
		}
	}

	function addTimeline(line:String):Void {
		timeline.push(line);
		while (timeline.length > MAX_TIMELINE) {
			var first = timeline[0];
			timeline.remove(first);
		}
	}

	function chatLead():String {
		return emojiEnabled() ? "💬" : "MSG";
	}

	function emojiEnabled():Bool {
		var forcedAscii = Sys.getEnv("REFLAXE_RUST_ASCII_ONLY");
		if (forcedAscii != null && StringTools.trim(forcedAscii) == "1") {
			return false;
		}
		return termWidth >= 72;
	}

	function topTabs():UiNode {
		var runtimeLabel = runtime.profileName();
		return Tabs(["NEON LOOPBACK", "PROFILE " + runtimeLabel, "MOTION GRID"], 0, Title);
	}

	function bodyPane():UiNode {
		return Layout(Horizontal, [Percent(24), Percent(52), Percent(24)], [leftRail(), timelinePane(), telemetryPane()]);
	}

	function leftRail():UiNode {
		return Block("relay matrix", [
			Layout(Vertical, [Percent(45), Percent(55)], [
				List("channels", channelLines(), selectedChannel, Accent),
				List("operators", operatorLines(), selectedOperator, Selected)
			]),
		], Accent);
	}

	function timelinePane():UiNode {
		return Block("live feed", [List("timeline", visibleTimeline(), -1, Normal)], Title);
	}

	function telemetryPane():UiNode {
		return Block("telemetry", [
			Layout(Vertical, [Fixed(4), Fixed(4), Fill], [
				Gauge("link stability", linkPercent, Success),
				Gauge("command density", commandDensityPercent(), Warning),
				FxText("signal theater", fxText(), fxKind(), fxPhase, Accent)
			]),
		], Warning);
	}

	function composerPane():UiNode {
		var cursor = (fxPhase % 14 < 7) ? (emojiEnabled() ? "▌" : "|") : " ";
		var prompt = (emojiEnabled() ? "🛰" : ">>") + " " + operators[selectedOperator] + "@" + channels[selectedChannel] + ": ";
		var body = prompt + inputBuffer + cursor + "\n" + "enter send  |  tab room  |  up/down operator  |  ? help";
		return Block("composer", [Paragraph(body, true, Normal)], Selected);
	}

	function statusBar():UiNode {
		var pulse = fxPhase % 200;
		var icon = emojiEnabled() ? "✨" : "*";
		var text = icon + " " + statusLine + "  | cmds=" + commandCount + "  | channel=" + channels[selectedChannel] + "  | pulse=" + pulse;
		return Paragraph(text, false, Muted);
	}

	function helpModal():UiNode {
		return Modal("Command Cheatsheet", [
			"Enter      send message",
			"/history   request runtime snapshot",
			"/clear     wipe local timeline only",
			"/quit      ask runtime to close",
			"Tab        cycle channels",
			"Up/Down    active operator",
			"Ctrl+C/q   exit",
		], 68, 62, Warning);
	}

	function commandDensityPercent():Int {
		var scaled = commandCount * 9;
		if (scaled > 100) {
			return 100;
		}
		return scaled;
	}

	function fxKind():FxKind {
		return switch (selectedChannel) {
			case 0: Pulse;
			case 1: Marquee;
			case 2: Typewriter;
			case _: Glitch;
		};
	}

	function fxText():String {
		var icon = emojiEnabled() ? "🧠" : "FX";
		var mood = operatorMoods[selectedOperator];
		return icon + " profile: " + runtime.profileName() + "\nchannel: " + channels[selectedChannel] + "\noperator mood: " + mood + "\ncommands sent: "
			+ commandCount;
	}

	function channelLines():Array<String> {
		var out = new Array<String>();
		for (i in 0...channels.length) {
			var marker = i == selectedChannel ? (emojiEnabled() ? "▶" : ">") : " ";
			out.push(marker + " " + channels[i]);
		}
		return out;
	}

	function operatorLines():Array<String> {
		var out = new Array<String>();
		for (i in 0...operators.length) {
			var online = i <= selectedOperator ? (emojiEnabled() ? "🟢" : "+") : (emojiEnabled() ? "🟡" : "~");
			out.push(online + " " + operators[i] + " · " + operatorMoods[i]);
		}
		return out;
	}

	function visibleTimeline():Array<String> {
		var maxLines = termHeight - 11;
		if (maxLines < 8) {
			maxLines = 8;
		}
		if (timeline.length <= maxLines) {
			return timeline.copy();
		}
		return timeline.slice(timeline.length - maxLines, timeline.length);
	}
}
