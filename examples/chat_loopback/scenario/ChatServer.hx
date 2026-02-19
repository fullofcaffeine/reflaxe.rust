package scenario;

import haxe.Exception;
import haxe.io.Eof;
import haxe.io.Error as HxIoError;
import domain.ChatEvent;
import profile.ChatRuntime;
import protocol.Codec;
import sys.net.Host;
import sys.net.Socket;

private typedef ConnectedClient = {
	var socket:Socket;
	var label:String;
};

/**
 * ChatServer
 *
 * Why
 * - Multi-instance localhost chat needs one shared runtime state and many connected clients.
 *
 * What
 * - TCP server that accepts multiple local clients and applies typed `ChatCommand` requests
 *   against one `ChatRuntime`.
 * - Responses are encoded typed `ChatEvent` lines.
 *
 * How
 * - Uses short `Socket.select` windows to avoid blocking forever.
 * - Parser/formatter boundaries are centralized in `protocol.Codec`.
 */
class ChatServer {
	static inline final SELECT_WAIT_SECONDS:Float = 0.08;

	/**
	 * Why
	 * - The TUI runs in an alternate-screen renderer; ad-hoc stdout writes from background threads
	 *   will corrupt the frame and produce "random line" artifacts.
	 *
	 * What
	 * - Compile-time switch for server diagnostic logs.
	 *
	 * How
	 * - Disabled by default; opt in with `-D chat_server_logs` when debugging transport behavior.
	 */
	public static inline function loggingEnabled():Bool {
		#if chat_server_logs
		return true;
		#else
		return false;
		#end
	}

	public static function run(runtime:ChatRuntime, host:String, port:Int):Void {
		var listener = new Socket();
		var clients:Array<ConnectedClient> = [];
		var bindHost = new Host(host);
		listener.bind(bindHost, port);
		listener.listen(32);

		#if chat_server_logs
		var boundPort = listener.host().port;
		Sys.println("[chat-server] listening on " + host + ":" + boundPort + " profile=" + runtime.profileName());
		#end

		while (true) {
			var read = new Array<Socket>();
			read.push(listener);
			for (client in clients) {
				read.push(client.socket);
			}

			var ready = Socket.select(read, [], [], SELECT_WAIT_SECONDS);
			if (ready.read.length == 0) {
				continue;
			}

			for (socket in ready.read) {
				if (socket == listener) {
					var accepted = listener.accept();
					accepted.setBlocking(true);
					var remote = accepted.peer();
					var label = remote.host.toString() + ":" + remote.port;
					clients.push({socket: accepted, label: label});
					#if chat_server_logs
					Sys.println("[chat-server] client connected " + label);
					#end
				} else {
					var idx = indexOfClient(clients, socket);
					if (idx == -1) {
						continue;
					}
					var keep = handleClient(runtime, clients[idx]);
					if (!keep) {
						#if chat_server_logs
						var label = clients[idx].label;
						#end
						try {
							clients[idx].socket.close();
						} catch (_:Exception) {}
						clients.splice(idx, 1);
						#if chat_server_logs
						Sys.println("[chat-server] client closed " + label);
						#end
					}
				}
			}
		}
	}

	static function handleClient(runtime:ChatRuntime, client:ConnectedClient):Bool {
		var line:String = null;
		try {
			line = client.socket.input.readLine();
		} catch (_:Eof) {
			return false;
		} catch (error:HxIoError) {
			return switch (error) {
				case Blocked:
					true;
				case _:
					false;
			};
		} catch (_:Exception) {
			return false;
		}

		var keep = true;
		var event = switch (Codec.parseCommand(line)) {
			case Parsed(command):
				switch (command) {
					case Quit:
						keep = false;
						Bye("disconnect");
					case _:
						runtime.handle(command);
				}
			case Invalid(reason):
				Rejected("parse:" + reason);
		}

		try {
			client.socket.write(Codec.encodeEvent(event) + "\n");
			client.socket.output.flush();
		} catch (_:Eof) {
			return false;
		} catch (error:HxIoError) {
			return switch (error) {
				case Blocked:
					true;
				case _:
					false;
			};
		} catch (_:Exception) {
			return false;
		}
		return keep;
	}

	static function indexOfClient(clients:Array<ConnectedClient>, socket:Socket):Int {
		for (i in 0...clients.length) {
			if (clients[i].socket == socket) {
				return i;
			}
		}
		return -1;
	}
}
