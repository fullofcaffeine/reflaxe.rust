package protocol;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.CommandParse;

/**
 * Codec
 *
 * Why
 * - Demonstrates a typed parser/formatter boundary for text protocols.
 * - Keeps all command/event handling in concrete enums/classes instead of untyped maps.
 *
 * What
 * - Encodes commands/events into one-line wire strings.
 * - Parses incoming command lines into `CommandParse` (`Parsed` or `Invalid`).
 *
 * How
 * - Uses a tiny deterministic token protocol with `|` as field separator and `%xx` escaping
 *   for separator characters.
 * - Callers cross the text boundary only here, then stay in typed domain objects.
 */
class Codec {
	static inline final FIELD_SEPARATOR = "|";
	static inline final MESSAGE_SEPARATOR = ",";

	public static function encodeCommand(command:ChatCommand):String {
		return switch (command) {
			case Send(user, body):
				"SEND" + FIELD_SEPARATOR + escapeToken(user) + FIELD_SEPARATOR + escapeToken(body);
			case History:
				"HISTORY";
			case Quit:
				"QUIT";
		};
	}

	public static function parseCommand(line:String):CommandParse {
		if (line == null || line.length == 0) {
			return Invalid("empty-line");
		}

		var fields = line.split(FIELD_SEPARATOR);
		if (fields.length == 0) {
			return Invalid("missing-command");
		}

		var head = fields[0];
		return switch (head) {
			case "SEND":
				if (fields.length != 3) {
					Invalid("send-arity");
				} else {
					var user = unescapeToken(fields[1]);
					var body = unescapeToken(fields[2]);
					if (StringTools.trim(user) == "") {
						Invalid("empty-user");
					} else if (StringTools.trim(body) == "") {
						Invalid("empty-body");
					} else {
						Parsed(Send(user, body));
					}
				}
			case "HISTORY":
				if (fields.length == 1) Parsed(History) else Invalid("history-arity");
			case "QUIT":
				if (fields.length == 1) Parsed(Quit) else Invalid("quit-arity");
			case _:
				Invalid("unknown-command:" + head);
		};
	}

	public static function encodeEvent(event:ChatEvent):String {
		return switch (event) {
			case Delivered(id, user, body, fingerprint, origin):
				"DELIVERED"
				+ FIELD_SEPARATOR
				+ id
				+ FIELD_SEPARATOR
				+ escapeToken(user)
				+ FIELD_SEPARATOR
				+ escapeToken(body)
				+ FIELD_SEPARATOR
				+ fingerprint
				+ FIELD_SEPARATOR
				+ escapeToken(origin);
			case HistorySnapshot(entries):
				var tokens = new Array<String>();
				for (entry in entries) {
					tokens.push(escapeToken(entry));
				}
				"HISTORY" + FIELD_SEPARATOR + entries.length + FIELD_SEPARATOR + tokens.join(MESSAGE_SEPARATOR);
			case Bye(reason):
				"BYE" + FIELD_SEPARATOR + escapeToken(reason);
			case Rejected(reason):
				"REJECTED" + FIELD_SEPARATOR + escapeToken(reason);
		};
	}

	static function escapeToken(value:String):String {
		var escaped = StringTools.replace(value, "%", "%25");
		escaped = StringTools.replace(escaped, "|", "%7C");
		escaped = StringTools.replace(escaped, ",", "%2C");
		escaped = StringTools.replace(escaped, ":", "%3A");
		escaped = StringTools.replace(escaped, ";", "%3B");
		return escaped;
	}

	static function unescapeToken(value:String):String {
		var unescaped = StringTools.replace(value, "%3B", ";");
		unescaped = StringTools.replace(unescaped, "%3A", ":");
		unescaped = StringTools.replace(unescaped, "%2C", ",");
		unescaped = StringTools.replace(unescaped, "%7C", "|");
		unescaped = StringTools.replace(unescaped, "%25", "%");
		return unescaped;
	}
}
