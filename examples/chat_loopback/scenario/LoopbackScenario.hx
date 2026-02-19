package scenario;

import domain.ChatCommand;
import domain.ChatEvent;
import haxe.Exception;
import profile.ChatRuntime;
import protocol.Codec;
import sys.net.Host;
import sys.net.Socket;

/**
 * LoopbackScenario
 *
 * Why
 * - Provides one deterministic chat protocol scenario that can run under all profiles.
 * - Keeps network behavior local (127.0.0.1) so CI remains deterministic and offline.
 *
 * What
 * - Opens one TCP listener + one client.
 * - Executes a fixed command script (`SEND`, `SEND`, `HISTORY`, `QUIT`).
 * - Returns a transcript of encoded response lines.
 *
 * How
 * - Uses short `Socket.select` polling windows to avoid indefinite blocking in CI.
 * - Converts protocol text into typed commands via `Codec.parseCommand` before dispatching.
 */
class LoopbackScenario {
	static inline final IO_TIMEOUT_SECONDS:Float = 3.0;
	static inline final SELECT_SLICE_SECONDS:Float = 0.1;

	public static function run(runtime:ChatRuntime):Array<String> {
		var loop = new Host("127.0.0.1");
		var server = new Socket();
		var client = new Socket();
		var connection:Null<Socket> = null;
		var transcript = new Array<String>();
		var failure:Null<Exception> = null;

		try {
			server.bind(loop, 0);
			server.listen(1);
			var serverPort = server.host().port;

			client.connect(loop, serverPort);
			waitReadable(server, IO_TIMEOUT_SECONDS, "accept");
			connection = server.accept();

			for (command in commandPlan()) {
				roundTrip(runtime, client, connection, command, transcript);
			}
		} catch (error:Exception) {
			failure = error;
		}

		if (connection != null) {
			connection.close();
		}
		client.close();
		server.close();

		if (failure != null) {
			throw failure;
		}

		return transcript;
	}

	public static function invalidCommandRejected(runtime:ChatRuntime):Bool {
		var event = decodeAndDispatch(runtime, "WAT|oops");
		return switch (event) {
			case Rejected(reason):
				StringTools.startsWith(reason, "parse:");
			case _:
				false;
		};
	}

	static function roundTrip(runtime:ChatRuntime, client:Socket, connection:Socket, command:ChatCommand, transcript:Array<String>):Void {
		client.write(Codec.encodeCommand(command) + "\n");
		client.output.flush();

		waitReadable(connection, IO_TIMEOUT_SECONDS, "server read");
		var inbound = connection.input.readLine();
		var event = decodeAndDispatch(runtime, inbound);
		connection.write(Codec.encodeEvent(event) + "\n");
		connection.output.flush();

		waitReadable(client, IO_TIMEOUT_SECONDS, "client read");
		transcript.push(client.input.readLine());
	}

	static function decodeAndDispatch(runtime:ChatRuntime, wireLine:String):ChatEvent {
		return switch (Codec.parseCommand(wireLine)) {
			case Parsed(command):
				runtime.handle(command);
			case Invalid(reason):
				Rejected("parse:" + reason);
		};
	}

	static function commandPlan():Array<ChatCommand> {
		return [
			Send("alice", "#ops", "hello-team"),
			Send("bob", "#ops", "ship-it"),
			History,
			Quit
		];
	}

	/**
	 * Waits for socket readability with a bounded timeout.
	 */
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
