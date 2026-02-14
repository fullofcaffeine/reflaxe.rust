import domain.ChatCommand;
import profile.RuntimeFactory;
import protocol.Codec;
import scenario.LoopbackScenario;

/**
 * Harness
 *
 * Why
 * - Exposes deterministic entrypoints for Rust-side tests (`native/chat_tests.rs`) without
 *   requiring interactive I/O.
 *
 * What
 * - Runs the loopback transcript scenario.
 * - Exposes parser/codec assertions and profile label helpers.
 *
 * How
 * - `Main` always calls `Harness.__link()` so this module is reachable in all compile variants.
 */
class Harness {
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
}
