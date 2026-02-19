package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import haxe.Exception;
import haxe.io.Eof;
import haxe.io.Error as HxIoError;
import protocol.Codec;
import sys.net.Host;
import sys.net.Socket;

/**
 * RemoteRuntime
 *
 * Why
 * - Multiple local TUI instances need one shared chat state.
 * - Keeping networking behind `ChatRuntime` lets `ChatUiApp` stay typed and profile-agnostic.
 *
 * What
 * - Request/response socket client for a `ChatServer` endpoint.
 * - Polls periodic history snapshots and (when identity is known) sends typed presence heartbeats.
 * - Emits updates only when snapshot digest actually changes.
 *
 * How
 * - Opens a short-lived localhost socket per request (`SEND` / `PRESENCE` / `HISTORY` / `QUIT`).
 * - Crosses text boundaries only via `protocol.Codec` (`encodeCommand`, `parseEvent`).
 */
class RemoteRuntime implements ChatRuntime {
	static inline final REQUEST_TIMEOUT_SECONDS:Float = 0.20;
	static inline final POLL_INTERVAL_SECONDS:Float = 0.20;
	static inline final SELECT_SLICE_SECONDS:Float = 0.02;

	final host:String;
	final port:Int;
	final endpoint:String;
	final presenceUser:Null<String>;

	var nextPollAt:Float = 0.0;
	var lastHistoryDigest:String = "";
	var disconnected:Bool = false;

	public function new(host:String, port:Int, ?presenceUser:String) {
		this.host = host;
		this.port = port;
		this.endpoint = host + ":" + port;
		this.presenceUser = presenceUser;
		this.nextPollAt = Sys.time() + POLL_INTERVAL_SECONDS;
	}

	public function profileName():String {
		return "network@" + endpoint;
	}

	public function handle(command:ChatCommand):ChatEvent {
		if (disconnected) {
			return Bye("disconnected");
		}

		var isQuit = switch (command) {
			case Quit: true;
			case _: false;
		};
		var event = request(command, "handle");
		switch (event) {
			case HistorySnapshot(entries):
				lastHistoryDigest = entries.join("\u001f");
			case _:
		}
		if (isQuit) {
			if (presenceUser != null) {
				try {
					request(Presence(presenceUser, false), "quit presence");
				} catch (_:Exception) {}
			}
			disconnected = true;
		}
		return event;
	}

	public function pollEvents():Array<ChatEvent> {
		if (disconnected) {
			return [];
		}

		var now = Sys.time();
		if (now < nextPollAt) {
			return [];
		}
		nextPollAt = now + POLL_INTERVAL_SECONDS;

		var event = if (presenceUser != null) {
			request(Presence(presenceUser, true), "poll presence");
		} else {
			request(History, "poll");
		};
		return switch (event) {
			case HistorySnapshot(entries):
				var digest = entries.join("\u001f");
				if (digest == lastHistoryDigest) {
					[];
				} else {
					lastHistoryDigest = digest;
					[event];
				}
			case Rejected(reason):
				if (StringTools.startsWith(reason, "network:")) {
					disconnected = true;
					[Bye("disconnected")];
				} else {
					[];
				}
			case Bye(_):
				disconnected = true;
				[event];
			case Delivered(_, _, _, _, _, _):
				[event];
		};
	}

	function request(command:ChatCommand, label:String):ChatEvent {
		var socket = new Socket();
		var outcome:ChatEvent = Rejected("network:unknown");
		try {
			socket.connect(new Host(host), port);
			socket.setBlocking(true);
			socket.write(Codec.encodeCommand(command) + "\n");
			socket.output.flush();
			waitReadable(socket, REQUEST_TIMEOUT_SECONDS, label + " read");
			var line = socket.input.readLine();
			socket.close();
			outcome = switch (Codec.parseEvent(line)) {
				case EventParsed(event):
					event;
				case EventInvalid(reason):
					Rejected("parse-event:" + reason);
			};
		} catch (error:Exception) {
			try {
				socket.close();
			} catch (_:Exception) {}
			outcome = Rejected("network:" + error.message);
		} catch (_:Eof) {
			try {
				socket.close();
			} catch (_:Exception) {}
			outcome = Rejected("network:eof");
		} catch (error:HxIoError) {
			try {
				socket.close();
			} catch (_:Exception) {}
			outcome = switch (error) {
				case Blocked:
					Rejected("network:blocked");
				case _:
					Rejected("network:io");
			};
		}
		return outcome;
	}

	static function waitReadable(socket:Socket, timeoutSeconds:Float, label:String):Void {
		var deadline = Sys.time() + timeoutSeconds;
		while (true) {
			var now = Sys.time();
			if (now >= deadline) {
				break;
			}
			var remaining = deadline - now;
			var wait = remaining < SELECT_SLICE_SECONDS ? remaining : SELECT_SLICE_SECONDS;
			var ready = Socket.select([socket], [], [], wait);
			if (ready.read.length > 0) {
				return;
			}
		}
		throw new Exception("select timeout waiting for " + label);
	}
}
