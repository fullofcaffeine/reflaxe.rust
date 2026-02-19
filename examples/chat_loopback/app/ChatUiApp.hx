package app;

import domain.ChatCommand;
import domain.ChatEvent;
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import profile.ChatRuntime;
import rust.tui.Constraint;
import rust.tui.Event;
import rust.tui.FxKind;
import rust.tui.KeyCode;
import rust.tui.KeyMods;
import rust.tui.LayoutDir;
import rust.tui.StyleToken;
import rust.tui.UiNode;

private typedef ParsedHistoryEntry = {
	var id:Int;
	var user:String;
	var channel:String;
	var body:String;
	var fingerprint:Int;
	var origin:String;
};

/**
	ChatUiApp

	Why
	- `chat_loopback` should be both a profile-comparison harness and a visually impressive,
	  modern interactive TUI.
	- We still need deterministic rendering for CI (`Tui.renderUiToString`) while keeping rich motion.

	What
	- Event-driven chat state machine with:
	  - neon control-rail layout
	  - animated telemetry panel + typed diagnostics stream
	  - channel-scoped timeline feed (`#ops`, `#compiler`, `#shiproom`, `#nightwatch`)
	  - dedicated activity log for online/offline transitions
	  - composer + modal command help (`Ctrl+H`, while plain `?` stays regular chat text)
	  - typed command dispatch through `profile.ChatRuntime`

	How
	- All behavior is modeled in typed Haxe (`Event`, `UiNode`, `ChatCommand`, `ChatEvent`).
	- Animation advances only through explicit `Tick(dtMs)`, so tests can replay exact frame sequences.
	- Emoji is opt-in by capability: wide terminals show emoji by default, otherwise we auto-fallback
	  to ASCII-safe markers (`REFLAXE_RUST_ASCII_ONLY=1` forces ASCII).
**/
class ChatUiApp {
	static inline final MAX_TIMELINE = 80;
	static inline final MAX_DIAGNOSTICS = 24;
	static inline final MAX_ACTIVITY = 24;
	static inline final ANIMATION_STEP_MS = 50;
	static inline final TADA_DURATION_MS = 1800;
	static inline final PRESENCE_PREFIX = "@presence:";
	static inline final GLOBAL_TIMELINE = "*";
	static final DISCOVERY_MOODS = [
		"focused",
		"calm",
		"debugging",
		"ship-mode",
		"curious",
		"locked-in",
		"vibing",
		"steady"
	];

	final runtime:ChatRuntime;
	final channels:Array<String>;
	final operators:Array<String>;
	final operatorMoods:Array<String>;

	public var shouldQuit(default, null):Bool = false;
	public var inputBuffer(default, null):String = "";

	var timeline:Array<String>;
	var timelineChannels:Array<String>;
	var selectedChannel:Int = 0;
	var selectedOperator:Int = 0;
	var fxPhase:Int = 0;
	var linkPercent:Int = 72;
	var commandCount:Int = 0;
	var statusLine:String = "sunset relay online";
	var showHelp:Bool = false;
	var termWidth:Int = 100;
	var termHeight:Int = 30;
	var fixedOperatorName:Null<String> = null;
	var operatorLocked:Bool = false;
	var animationCarryMs:Int = 0;
	var tadaRemainingMs:Int = 0;
	var diagnostics:Array<String>;
	var activityLog:Array<String>;
	var onlineUsers:StringMap<Bool>;
	var seenMessageIds:IntMap<Bool>;

	public function new(runtime:ChatRuntime, ?forcedUserName:String) {
		this.runtime = runtime;
		this.timeline = [];
		this.timelineChannels = [];
		this.diagnostics = [];
		this.activityLog = [];
		this.onlineUsers = new StringMap();
		this.seenMessageIds = new IntMap();
		this.channels = ["#ops", "#compiler", "#shiproom", "#nightwatch"];
		if (forcedUserName != null && StringTools.trim(forcedUserName) != "") {
			var normalized = StringTools.trim(forcedUserName);
			this.fixedOperatorName = normalized;
			this.operatorLocked = true;
			this.operators = [normalized];
			this.operatorMoods = ["dialed-in"];
			this.onlineUsers.set(normalized, true);
		} else {
			this.operators = ["alice", "bob", "zoe", "maya"];
			this.operatorMoods = ["calm", "shipping", "debug", "hyperfocus"];
		}

		var bootIcon = emojiEnabled() ? "🎉" : "BOOT";
		addGlobalTimeline(bootIcon + " sunset loopback online (" + runtime.profileName() + ")");
		addDiagnostic("runtime profile " + runtime.profileName());
		addDiagnostic("server logs quiet by default (enable -D chat_server_logs only for debug)");
		addActivity("session started (" + runtime.profileName() + ")");
		if (fixedOperatorName != null) {
			var operatorName:String = fixedOperatorName;
			addGlobalTimeline((emojiEnabled() ? "🪪" : "ID") + " identity " + operatorName);
			addDiagnostic("identity lock " + operatorName);
			addActivity(operatorName + " online");
		}
		addGlobalTimeline((emojiEnabled() ? "🧭" : "TIP") + " type a message and launch it with Enter");
		addGlobalTimeline((emojiEnabled() ? "✨" : "CMD") + " commands: /history /help /clear /quit");
		addGlobalTimeline((emojiEnabled() ? "⌨" : "KEY") + " shortcuts: Ctrl+H help, Tab room, Ctrl+C quit");
	}

	public function setTerminalSize(width:Int, height:Int):Void {
		termWidth = width;
		termHeight = height;
	}

	public function fixedIdentity():Null<String> {
		return fixedOperatorName;
	}

	public function tadaActive():Bool {
		return tadaRemainingMs > 0;
	}

	public function handle(ev:Event):Bool {
		switch (ev) {
			case Quit:
				shouldQuit = true;
			case Resize(w, h):
				setTerminalSize(w, h);
			case Tick(dtMs):
				advanceAnimation(dtMs);
				drainPolledEvents();
			case None:
				// no-op
			case Key(code, mods):
				handleKey(code, mods);
		}
		return shouldQuit;
	}

	public function view():UiNode {
		var base = Layout(Vertical, [Fixed(1), Fill, Fixed(5), Fixed(1)], [topTabs(), bodyPane(), composerPane(), statusBar()]);
		if (tadaRemainingMs > 0 || showHelp) {
			var layers = new Array<UiNode>();
			layers.push(base);
			if (tadaRemainingMs > 0) {
				layers.push(tadaOverlay());
			}
			if (showHelp) {
				layers.push(helpModal());
			}
			return Overlay(layers);
		}
		return base;
	}

	function advanceAnimation(dtMs:Int):Void {
		if (dtMs <= 0) {
			return;
		}
		if (tadaRemainingMs > 0) {
			tadaRemainingMs = tadaRemainingMs - dtMs;
			if (tadaRemainingMs < 0) {
				tadaRemainingMs = 0;
			}
		}
		animationCarryMs = animationCarryMs + dtMs;
		var step = Std.int(animationCarryMs / ANIMATION_STEP_MS);
		if (step <= 0) {
			return;
		}
		animationCarryMs = animationCarryMs - (step * ANIMATION_STEP_MS);
		if (step > 6) {
			step = 6;
		}
		fxPhase = (fxPhase + step) % 4096;
		linkPercent = 58 + ((fxPhase * 7 + commandCount * 11) % 42);
	}

	function handleKey(code:KeyCode, mods:KeyMods):Void {
		switch (code) {
			case Char("c") if (mods.has(Ctrl)):
				shouldQuit = true;
			case Char("h") if (mods.has(Ctrl)):
				showHelp = !showHelp;
			case Char("H") if (mods.has(Ctrl)):
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
				addDiagnostic("channel switched to " + channels[selectedChannel]);
			case Up:
				if (!operatorLocked && operators.length > 1 && selectedOperator > 0) {
					selectedOperator = selectedOperator - 1;
					addDiagnostic("operator set to " + operators[selectedOperator]);
				}
			case Down:
				if (!operatorLocked && operators.length > 1 && selectedOperator < operators.length - 1) {
					selectedOperator = selectedOperator + 1;
					addDiagnostic("operator set to " + operators[selectedOperator]);
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

	function drainPolledEvents():Void {
		var incoming = runtime.pollEvents();
		if (incoming.length > 0) {
			addDiagnostic("poll received " + incoming.length + " event(s)");
		}
		for (event in incoming) {
			applyEvent(event);
		}
	}

	function submitInput():Void {
		var raw = StringTools.trim(inputBuffer);
		inputBuffer = "";

		if (raw.length == 0) {
			statusLine = "composer empty";
			addDiagnostic("ignored empty composer submit");
			return;
		}

		if (StringTools.startsWith(raw, "/")) {
			runSlashCommand(raw);
			return;
		}

		clampSelectedOperator();
		if (operators.length == 0) {
			statusLine = "no active operator";
			addDiagnostic("cannot send: no active operator");
			return;
		}

		var speaker = operators[selectedOperator];
		if (operatorLocked && fixedOperatorName != null) {
			speaker = fixedOperatorName;
		}
		var activeChannel = channels[selectedChannel];
		addDiagnostic("send " + speaker + " -> " + activeChannel);
		applyEvent(runtime.handle(Send(speaker, activeChannel, raw)));
	}

	function runSlashCommand(raw:String):Void {
		switch (raw) {
			case "/help":
				showHelp = true;
				statusLine = "help overlay opened";
				addDiagnostic("command /help");
			case "/history":
				addDiagnostic("command /history");
				applyEvent(runtime.handle(History));
			case "/clear":
				timeline = [];
				timelineChannels = [];
				addTimeline((emojiEnabled() ? "🧹" : "CLR") + " timeline cleared", channels[selectedChannel]);
				statusLine = "timeline reset";
				addDiagnostic("command /clear");
			case "/quit":
				addDiagnostic("command /quit");
				applyEvent(runtime.handle(Quit));
			case _:
				addTimeline((emojiEnabled() ? "⚠" : "ERR") + " unknown command `" + raw + "`", channels[selectedChannel]);
				statusLine = "unknown command";
				addDiagnostic("unknown command " + raw);
		}
	}

	function applyEvent(event:ChatEvent):Void {
		switch (event) {
			case Delivered(id, user, channel, body, fingerprint, origin):
				ensureOperator(user);
				markUserOnline(user);
				seenMessageIds.set(id, true);
				incrementCommandCount(1);
				addTimeline(chatLead() + " " + id + " [" + channel + "] " + user + " ▸ " + body + "  [" + origin + ":" + fingerprint + "]", channel);
				statusLine = "delivered via " + origin + " @ " + channel;
				addDiagnostic("delivered #" + id + " channel=" + channel + " origin=" + origin + " fp=" + fingerprint);
			case HistorySnapshot(entries):
				var imported = importHistoryEntries(entries);
				if (imported == 0) {
					statusLine = "history refreshed";
				} else {
					statusLine = "history synced +" + imported;
				}
				addDiagnostic("history snapshot entries=" + entries.length + " imported=" + imported);
			case Bye(reason):
				addGlobalTimeline((emojiEnabled() ? "👋" : "BYE") + " " + reason);
				statusLine = "session closed";
				addActivity("session closed");
				addDiagnostic("session close " + reason);
				shouldQuit = true;
			case Rejected(reason):
				addGlobalTimeline((emojiEnabled() ? "⚠" : "REJ") + " " + reason);
				statusLine = "runtime rejected input";
				addDiagnostic("rejected " + reason);
		}
	}

	function addTimeline(line:String, channel:String):Void {
		timeline.push(line);
		timelineChannels.push(channel);
		while (timeline.length > MAX_TIMELINE) {
			timeline.splice(0, 1);
			timelineChannels.splice(0, 1);
		}
	}

	function addGlobalTimeline(line:String):Void {
		addTimeline(line, GLOBAL_TIMELINE);
	}

	function incrementCommandCount(delta:Int):Void {
		if (delta <= 0) {
			return;
		}
		var before = commandDensityPercentFor(commandCount);
		commandCount = commandCount + delta;
		var after = commandDensityPercentFor(commandCount);
		if (before < 100 && after >= 100) {
			triggerTada();
		}
	}

	function triggerTada():Void {
		tadaRemainingMs = TADA_DURATION_MS;
		statusLine = "momentum 100 • tada!";
		addActivity("tada burst at momentum 100");
		addDiagnostic("chat momentum reached 100");
	}

	function addDiagnostic(line:String):Void {
		diagnostics.push(line);
		while (diagnostics.length > MAX_DIAGNOSTICS) {
			var first = diagnostics[0];
			diagnostics.remove(first);
		}
	}

	function addActivity(line:String):Void {
		activityLog.push(line);
		while (activityLog.length > MAX_ACTIVITY) {
			activityLog.splice(0, 1);
		}
	}

	function markUserOnline(user:String):Void {
		var normalized = StringTools.trim(user);
		if (normalized == "") {
			return;
		}
		if (!onlineUsers.exists(normalized)) {
			addActivity(normalized + " online");
		}
		onlineUsers.set(normalized, true);
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
		return Tabs(["SUNSET LOOPBACK", "PROFILE " + runtimeLabel, "PIXEL PARADE"], 0, Title);
	}

	function bodyPane():UiNode {
		return Layout(Horizontal, [Percent(24), Percent(52), Percent(24)], [leftRail(), timelinePane(), telemetryPane()]);
	}

	function leftRail():UiNode {
		return Block("party control", [
			Layout(Vertical, [Percent(34), Percent(33), Fill], [
				List("channels", channelLines(), selectedChannel, Accent),
				List("operators", operatorLines(), selectedOperator, Muted),
				List("activity log", activityLines(), -1, Success)
			]),
		], Accent);
	}

	function timelinePane():UiNode {
		return Block("campfire feed", [List("timeline", visibleTimeline(), -1, Normal)], Success);
	}

	function telemetryPane():UiNode {
		return Block("spark meters", [
			Layout(Vertical, [Fixed(4), Fixed(4), Fill], [
				Gauge("link glow", linkPercent, Success),
				Gauge("chat momentum", commandDensityPercent(), Warning),
				Layout(Vertical, [Percent(52), Percent(48)], [
					FxText("confetti bus", fxText(), fxKind(), fxPhase, Accent),
					List("diag stream", diagnosticLines(), -1, Muted)
				])
			]),
		], Warning);
	}

	function composerPane():UiNode {
		var cursor = (fxPhase % 14 < 7) ? (emojiEnabled() ? "▌" : "|") : " ";
		clampSelectedOperator();
		var operatorLabel = operators.length > 0 ? operators[selectedOperator] : "nobody";
		var prompt = (emojiEnabled() ? "🛰" : ">>") + " " + operatorLabel + "@" + channels[selectedChannel] + ": ";
		var controls = (!operatorLocked)
			&& operators.length > 1 ? "enter send  |  tab room  |  up/down operator  |  Ctrl+H help" : "enter send  |  tab room  |  Ctrl+H help";
		var body = prompt + inputBuffer + cursor + "\n" + controls;
		return Block("message launcher", [Paragraph(body, true, Normal)], Accent);
	}

	function statusBar():UiNode {
		var pulse = fxPhase % 200;
		var icon = emojiEnabled() ? "🌈" : "*";
		var text = icon + " " + statusLine + "  | cmds=" + commandCount + "  | channel=" + channels[selectedChannel] + "  | pulse=" + pulse;
		return Paragraph(text, false, Muted);
	}

	function helpModal():UiNode {
		return Modal("Party Commands", [
			"Enter      send message",
			"/history   request runtime snapshot",
			"/clear     wipe local timeline only",
			"/quit      ask runtime to close",
			"Tab        cycle channels",
			"Up/Down    active operator",
			"Ctrl+H     toggle help",
			"Ctrl+C/q   exit",
		], 68, 62, Warning);
	}

	function commandDensityPercent():Int {
		return commandDensityPercentFor(commandCount);
	}

	function commandDensityPercentFor(count:Int):Int {
		var scaled = count * 9;
		if (scaled > 100) {
			return 100;
		}
		return scaled;
	}

	function tadaOverlay():UiNode {
		var boom = emojiEnabled() ? "🎉" : "TADA";
		var sparkle = emojiEnabled() ? "✨" : "*";
		var effect = if ((fxPhase % 24) < 8) Marquee else if ((fxPhase % 24) < 16) Pulse else Glitch;
		var body = boom
			+ " MOMENTUM 100 "
			+ boom
			+ "\n"
			+ sparkle
			+ " full-frame party mode "
			+ sparkle
			+ "\nchannel "
			+ channels[selectedChannel]
			+ " lit";
		return Block("tada overdrive", [FxText("confetti storm", body, effect, fxPhase * 3, Warning)], Accent);
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
			var online = onlineUsers.exists(operators[i]) ? (emojiEnabled() ? "🟢" : "+") : (emojiEnabled() ? "🟡" : "~");
			out.push(online + " " + operators[i] + " · " + operatorMoods[i]);
		}
		return out;
	}

	function visibleTimeline():Array<String> {
		var maxLines = termHeight - 11;
		if (maxLines < 8) {
			maxLines = 8;
		}
		var activeChannel = channels[selectedChannel];
		var filtered = new Array<String>();
		for (i in 0...timeline.length) {
			var lineChannel = timelineChannels[i];
			if (lineChannel == GLOBAL_TIMELINE || lineChannel == activeChannel) {
				filtered.push(timeline[i]);
			}
		}
		if (filtered.length <= maxLines) {
			return filtered;
		}
		return filtered.slice(filtered.length - maxLines, filtered.length);
	}

	function activityLines():Array<String> {
		var maxLines = termHeight < 26 ? 4 : 7;
		if (activityLog.length <= maxLines) {
			return activityLog.copy();
		}
		return activityLog.slice(activityLog.length - maxLines, activityLog.length);
	}

	function diagnosticLines():Array<String> {
		var maxLines = termHeight < 26 ? 4 : 7;
		if (diagnostics.length <= maxLines) {
			return diagnostics.copy();
		}
		return diagnostics.slice(diagnostics.length - maxLines, diagnostics.length);
	}

	function importHistoryEntries(entries:Array<String>):Int {
		var imported = 0;
		var presenceUsers = new Array<String>();
		for (entry in entries) {
			if (StringTools.startsWith(entry, PRESENCE_PREFIX)) {
				var presenceUser = StringTools.trim(entry.substr(PRESENCE_PREFIX.length));
				if (presenceUser != "") {
					presenceUsers.push(presenceUser);
					ensureOperator(presenceUser);
				}
				continue;
			}

			var parsed = parseHistoryEntry(entry);
			if (parsed != null) {
				ensureOperator(parsed.user);
				markUserOnline(parsed.user);
				if (!seenMessageIds.exists(parsed.id)) {
					seenMessageIds.set(parsed.id, true);
					incrementCommandCount(1);
					imported = imported + 1;
					addTimeline(chatLead() + " " + parsed.id + " [" + parsed.channel + "] " + parsed.user + " ▸ " + parsed.body + "  [" + parsed.origin
						+ ":" + parsed.fingerprint + "]",
						parsed.channel);
				}
			} else {
				var userFromHistory = historyEntryUser(entry);
				if (userFromHistory != null) {
					ensureOperator(userFromHistory);
				}
			}
		}
		syncPresenceRoster(presenceUsers);
		return imported;
	}

	function parseHistoryEntry(entry:String):Null<ParsedHistoryEntry> {
		var firstSep = entry.indexOf(":");
		if (firstSep <= 0) {
			return null;
		}
		var secondSep = entry.indexOf(":", firstSep + 1);
		if (secondSep == -1) {
			return null;
		}
		var thirdSep = entry.indexOf(":", secondSep + 1);
		if (thirdSep == -1) {
			return null;
		}

		var id = parseIntToken(entry.substr(0, firstSep));
		if (id == null) {
			return null;
		}
		var idValue:Int = id;
		var user = StringTools.trim(entry.substr(firstSep + 1, secondSep - firstSep - 1));
		if (user == "") {
			return null;
		}
		var channel = StringTools.trim(entry.substr(secondSep + 1, thirdSep - secondSep - 1));
		if (channel == "") {
			return null;
		}

		var tail = parseHistoryTail(entry, thirdSep + 1);
		if (tail == null) {
			return null;
		}
		return {
			id: idValue,
			user: user,
			channel: channel,
			body: tail.body,
			fingerprint: tail.fingerprint,
			origin: tail.origin
		};
	}

	function parseHistoryTail(entry:String, bodyStart:Int):Null<{body:String, fingerprint:Int, origin:String}> {
		var cursor = entry.length - 1;
		while (cursor > bodyStart) {
			var fpEnd = lastIndexOfCode(entry, 58, cursor);
			if (fpEnd <= bodyStart) {
				break;
			}
			var fpStart = lastIndexOfCode(entry, 58, fpEnd - 1);
			if (fpStart <= bodyStart) {
				cursor = fpEnd - 1;
				continue;
			}

			var fingerprintToken = parseIntToken(entry.substr(fpStart + 1, fpEnd - fpStart - 1));
			if (fingerprintToken == null) {
				cursor = fpEnd - 1;
				continue;
			}
			var fingerprint:Int = fingerprintToken;

			return {
				body: entry.substr(bodyStart, fpStart - bodyStart),
				fingerprint: fingerprint,
				origin: entry.substr(fpEnd + 1)
			};
		}
		return null;
	}

	function lastIndexOfCode(value:String, code:Int, startIndex:Int):Int {
		var index = startIndex;
		if (index >= value.length) {
			index = value.length - 1;
		}
		while (index >= 0) {
			if (StringTools.fastCodeAt(value, index) == code) {
				return index;
			}
			index = index - 1;
		}
		return -1;
	}

	function parseIntToken(value:String):Null<Int> {
		var token = StringTools.trim(value);
		if (token.length == 0) {
			return null;
		}

		var sign = 1;
		var index = 0;
		if (token.charAt(0) == "-") {
			sign = -1;
			index = 1;
		}
		if (index >= token.length) {
			return null;
		}

		var out = 0;
		while (index < token.length) {
			var code = StringTools.fastCodeAt(token, index);
			if (code < 48 || code > 57) {
				return null;
			}
			out = out * 10 + (code - 48);
			index = index + 1;
		}
		return sign * out;
	}

	function ensureOperator(user:String):Void {
		var normalized = StringTools.trim(user);
		if (normalized == "") {
			return;
		}
		if (operators.indexOf(normalized) != -1) {
			return;
		}
		operators.push(normalized);
		operatorMoods.push(moodFor(normalized));
		clampSelectedOperator();
	}

	function syncPresenceRoster(presenceUsers:Array<String>):Void {
		var online = new StringMap<Bool>();
		for (presenceUser in presenceUsers) {
			online.set(presenceUser, true);
		}
		if (fixedOperatorName != null) {
			online.set(fixedOperatorName, true);
		}

		for (user in online.keys()) {
			if (!onlineUsers.exists(user)) {
				addActivity(user + " online");
			}
		}
		for (user in onlineUsers.keys()) {
			if (!online.exists(user)) {
				addActivity(user + " offline");
			}
		}
		onlineUsers = online;

		var index = operators.length - 1;
		while (index >= 0) {
			var user = operators[index];
			if (!online.exists(user)) {
				var removed = operators[index];
				operators.splice(index, 1);
				operatorMoods.splice(index, 1);
				addDiagnostic("operator offline " + removed);
			}
			index = index - 1;
		}
		for (user in online.keys()) {
			ensureOperator(user);
		}

		if (operators.length == 0 && fixedOperatorName != null) {
			operators.push(fixedOperatorName);
			operatorMoods.push("dialed-in");
		} else if (operators.length == 0) {
			operators.push("alice");
			operatorMoods.push("calm");
		}
		clampSelectedOperator();
	}

	function clampSelectedOperator():Void {
		if (operators.length == 0) {
			selectedOperator = 0;
			return;
		}
		if (selectedOperator < 0) {
			selectedOperator = 0;
			return;
		}
		if (selectedOperator >= operators.length) {
			selectedOperator = operators.length - 1;
		}
	}

	function moodFor(user:String):String {
		var hash = 0;
		for (i in 0...user.length) {
			hash = hash ^ StringTools.fastCodeAt(user, i);
			hash = hash ^ (hash << 5);
			hash = hash ^ (hash >> 2);
			hash = hash & 0x7fffffff;
		}
		return DISCOVERY_MOODS[hash % DISCOVERY_MOODS.length];
	}

	function historyEntryUser(entry:String):Null<String> {
		var firstSep = entry.indexOf(":");
		if (firstSep <= 0) {
			return null;
		}
		var secondSep = entry.indexOf(":", firstSep + 1);
		if (secondSep == -1) {
			return null;
		}
		var user = StringTools.trim(entry.substr(firstSep + 1, secondSep - firstSep - 1));
		if (user == "") {
			return null;
		}
		return user;
	}
}
