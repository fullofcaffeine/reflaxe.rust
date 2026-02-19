package protocol;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.CommandParse;
import domain.EventParse;

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
			case Send(user, channel, body):
				"SEND"
				+ FIELD_SEPARATOR
				+ escapeToken(user)
				+ FIELD_SEPARATOR
				+ escapeToken(channel)
				+ FIELD_SEPARATOR
				+ escapeToken(body);
			case Presence(user, online):
				"PRESENCE" + FIELD_SEPARATOR + escapeToken(user) + FIELD_SEPARATOR + (online ? "1" : "0");
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
				if (fields.length != 4) {
					Invalid("send-arity");
				} else {
					var user = unescapeToken(fields[1]);
					var channel = unescapeToken(fields[2]);
					var body = unescapeToken(fields[3]);
					if (StringTools.trim(user) == "") {
						Invalid("empty-user");
					} else if (StringTools.trim(channel) == "") {
						Invalid("empty-channel");
					} else if (StringTools.trim(body) == "") {
						Invalid("empty-body");
					} else {
						Parsed(Send(user, channel, body));
					}
				}
			case "PRESENCE":
				if (fields.length != 3) {
					Invalid("presence-arity");
				} else {
					var user = unescapeToken(fields[1]);
					var onlineToken = fields[2];
					if (StringTools.trim(user) == "") {
						Invalid("empty-user");
					} else if (onlineToken == "1") {
						Parsed(Presence(user, true));
					} else if (onlineToken == "0") {
						Parsed(Presence(user, false));
					} else {
						Invalid("presence-online");
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
			case Delivered(id, user, channel, body, fingerprint, origin):
				"DELIVERED"
				+ FIELD_SEPARATOR
				+ id
				+ FIELD_SEPARATOR
				+ escapeToken(user)
				+ FIELD_SEPARATOR
				+ escapeToken(channel)
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

	public static function parseEvent(line:String):EventParse {
		if (line == null || line.length == 0) {
			return EventInvalid("empty-line");
		}

		var fields = line.split(FIELD_SEPARATOR);
		if (fields.length == 0) {
			return EventInvalid("missing-event");
		}

		var head = fields[0];
		return switch (head) {
			case "DELIVERED":
				if (fields.length != 7) {
					EventInvalid("delivered-arity");
				} else {
					var id = parseIntToken(fields[1]);
					var fingerprint = parseIntToken(fields[5]);
					if (id == null) {
						EventInvalid("delivered-int");
					} else if (fingerprint == null) {
						EventInvalid("delivered-int");
					} else {
						EventParsed(Delivered(id, unescapeToken(fields[2]), unescapeToken(fields[3]), unescapeToken(fields[4]), fingerprint,
							unescapeToken(fields[6])));
					}
				}
			case "HISTORY":
				if (fields.length != 3) {
					EventInvalid("history-arity");
				} else {
					var parsedCount = parseIntToken(fields[1]);
					if (parsedCount == null) {
						EventInvalid("history-count");
					} else {
						var expectedCount:Int = parsedCount;
						if (expectedCount < 0) {
							EventInvalid("history-count");
						} else {
							var entries = new Array<String>();
							if (fields[2].length > 0) {
								for (token in fields[2].split(MESSAGE_SEPARATOR)) {
									entries.push(unescapeToken(token));
								}
							}
							if (entries.length != expectedCount) {
								EventInvalid("history-size");
							} else {
								EventParsed(HistorySnapshot(entries));
							}
						}
					}
				}
			case "BYE":
				if (fields.length == 2) EventParsed(Bye(unescapeToken(fields[1]))) else EventInvalid("bye-arity");
			case "REJECTED":
				if (fields.length == 2) EventParsed(Rejected(unescapeToken(fields[1]))) else EventInvalid("rejected-arity");
			case _:
				EventInvalid("unknown-event:" + head);
		};
	}

	static function parseIntToken(value:String):Null<Int> {
		if (value == null) {
			return null;
		}

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
