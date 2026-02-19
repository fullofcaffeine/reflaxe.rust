import app.ChatUiApp;
import app.FunnyName;
import domain.ChatCommand;
import domain.ChatEvent;
import haxe.Exception;
import profile.ChatRuntime;
import profile.RemoteRuntime;
import profile.RuntimeFactory;
import rust.tui.Tui;
import scenario.ChatServer;
import sys.thread.Thread;

/**
	Entry point for `chat_loopback`.

	Modes:
	- default: auto-connect to `127.0.0.1:7000`; if no room exists, auto-host one and join it
	- `--server [port]`: shared localhost chat server (multi-client)
	- `--connect <host:port|port>`: interactive client backed by `RemoteRuntime`
	- `--local`: force local single-process runtime
**/
class Main {
	static inline final DEFAULT_HOST = "127.0.0.1";
	static inline final DEFAULT_PORT = 7000;
	static inline final DEFAULT_CHANNEL = "#ops";
	static inline final UI_POLL_MS = 16;
	static inline final AUTO_SERVER_BOOT_SECONDS:Float = 0.12;
	static inline final HEADLESS_MAX_TICKS = 20;

	static function main():Void {
		Harness.__link();
		ChatTests.__link();

		var args = Sys.args();
		var serverPort = parseServerPort(args);
		if (serverPort != null) {
			ChatServer.run(RuntimeFactory.create(), DEFAULT_HOST, serverPort);
			return;
		}

		var runtime:ChatRuntime = RuntimeFactory.create();
		var generatedUser:Null<String> = null;
		var explicitConnect = args.indexOf("--connect") != -1;
		var forceLocal = args.indexOf("--local") != -1;
		var connectTarget = parseConnectTarget(args);
		if (connectTarget == null && !forceLocal) {
			connectTarget = {
				host: DEFAULT_HOST,
				port: DEFAULT_PORT
			};
		}

		if (connectTarget != null) {
			var candidateIdentity = FunnyName.generateAutoForPort(connectTarget.port);
			var remoteAttempt = connectRemote(connectTarget.host, connectTarget.port, candidateIdentity);
			if (remoteAttempt.runtime == null && !explicitConnect) {
				#if !chat_tui_headless
				ensureAutoServer(connectTarget.host, connectTarget.port);
				Sys.sleep(AUTO_SERVER_BOOT_SECONDS);
				remoteAttempt = connectRemote(connectTarget.host, connectTarget.port, candidateIdentity);
				#end
			}

			if (remoteAttempt.runtime != null) {
				runtime = remoteAttempt.runtime;
				generatedUser = candidateIdentity;
			} else if (explicitConnect) {
				var reasonValue = remoteAttempt.failureReason;
				if (reasonValue == null) {
					reasonValue = "unavailable";
				}
				var reasonText:String = reasonValue;
				throw new Exception("unable to connect to chat server (" + connectTarget.host + ":" + connectTarget.port + "): " + reasonText);
			}
		}

		var app = new ChatUiApp(runtime, generatedUser);
		var startupIdentity = app.fixedIdentity();
		if (startupIdentity != null) {
			try {
				runtime.handle(Send(startupIdentity, DEFAULT_CHANNEL, "joined the room"));
			} catch (_:Exception) {
				// Non-fatal: startup presence is best-effort.
			}
		}

		#if chat_tui_headless
		Tui.setHeadless(true);
		#else
		Tui.setHeadless(false);
		#end

		Tui.enter();
		try {
			var running = true;
			#if chat_tui_headless
			var headlessTicks = 0;
			#end
			while (running) {
				Tui.renderUi(app.view());
				var ev = Tui.pollEvent(UI_POLL_MS);
				if (ev == None) {
					ev = Tick(UI_POLL_MS);
				}
				running = !app.handle(ev);
				#if chat_tui_headless
				headlessTicks = headlessTicks + 1;
				if (headlessTicks >= HEADLESS_MAX_TICKS) {
					running = false;
				}
				#end
			}
		} catch (_:haxe.Exception) {
			// Ensure terminal cleanup on unexpected runtime failures.
		}
		if (startupIdentity != null) {
			try {
				runtime.handle(Presence(startupIdentity, false));
			} catch (_:Exception) {
				// Best-effort graceful leave marker.
			}
		}
		Tui.exit();
	}

	static function connectRemote(host:String, port:Int, presenceUser:Null<String>):{runtime:Null<RemoteRuntime>, failureReason:Null<String>} {
		var remote = new RemoteRuntime(host, port, presenceUser);
		var probe = remote.handle(History);
		return switch (probe) {
			case Rejected(reason):
				if (StringTools.startsWith(reason, "network:")) {
					{runtime: null, failureReason: reason};
				} else {
					{runtime: remote, failureReason: null};
				}
			case _:
				{runtime: remote, failureReason: null};
		};
	}

	static function ensureAutoServer(host:String, port:Int):Void {
		Thread.create(() -> {
			var bindHost = host.substr(0);
			try {
				ChatServer.run(RuntimeFactory.create(), bindHost, port);
			} catch (_:Exception) {
				// Another process likely already hosts the room, or bind failed.
			}
		});
	}

	static function parseServerPort(args:Array<String>):Null<Int> {
		var idx = args.indexOf("--server");
		if (idx == -1) {
			return null;
		}

		if (idx + 1 >= args.length) {
			return DEFAULT_PORT;
		}

		var candidate = parseIntToken(args[idx + 1]);
		if (candidate == null) {
			return DEFAULT_PORT;
		}
		return candidate;
	}

	static function parseConnectTarget(args:Array<String>):Null<{host:String, port:Int}> {
		var idx = args.indexOf("--connect");
		if (idx == -1) {
			return null;
		}
		if (idx + 1 >= args.length) {
			throw new Exception("`--connect` requires `<host:port>` or `<port>`");
		}

		var raw = StringTools.trim(args[idx + 1]);
		if (raw.length == 0) {
			throw new Exception("`--connect` requires a non-empty target");
		}

		if (raw.indexOf(":") == -1) {
			var onlyPort = parseIntToken(raw);
			if (onlyPort == null) {
				throw new Exception("invalid `--connect` port: " + raw);
			}
			return {host: DEFAULT_HOST, port: onlyPort};
		}

		var fields = raw.split(":");
		var poppedPortText = fields.pop();
		if (poppedPortText == null) {
			throw new Exception("invalid `--connect` target: " + raw);
		}
		var portText:String = poppedPortText;
		var host = StringTools.trim(fields.join(":"));
		if (host.length == 0) {
			host = DEFAULT_HOST;
		}
		var port = parseIntToken(portText);
		if (port == null) {
			throw new Exception("invalid `--connect` port: " + portText);
		}
		return {host: host, port: port};
	}

	static function parseIntToken(value:String):Null<Int> {
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
}
