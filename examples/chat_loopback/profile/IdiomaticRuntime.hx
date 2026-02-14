package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;

/**
 * IdiomaticRuntime
 *
 * Why
 * - Shows an idiomatic profile implementation that keeps portable semantics while producing
 *   cleaner Rust output patterns.
 *
 * What
 * - Same command behavior as portable runtime.
 * - Uses small helper functions and explicit immutable locals for readability/noise reduction.
 *
 * How
 * - Fingerprint is an ascii-sum marker of the normalized body.
 * - Keeps fully typed command/event flow.
 */
class IdiomaticRuntime implements ChatRuntime {
	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];

	public function new() {}

	public function profileName():String {
		return "idiomatic";
	}

	public function handle(command:ChatCommand):ChatEvent {
		return switch (command) {
			case Send(user, body):
				handleSend(user, body);
			case History:
				HistorySnapshot(historyEntries());
			case Quit:
				Bye(profileName() + ":" + messages.length);
		};
	}

	function handleSend(user:String, body:String):ChatEvent {
		final trimmedUser = StringTools.trim(user);
		final trimmedBody = StringTools.trim(body);
		if (trimmedUser == "") {
			return Rejected("empty-user");
		}
		if (trimmedBody == "") {
			return Rejected("empty-body");
		}

		final fingerprint = asciiFingerprint(trimmedBody);
		final message = new ChatMessage(nextId++, trimmedUser, trimmedBody, fingerprint, profileName());
		messages.push(message);
		return toDeliveredEvent(message);
	}

	function asciiFingerprint(value:String):Int {
		var bytes = haxe.io.Bytes.ofString(value);
		var sum = 0;
		for (index in 0...bytes.length) {
			sum += bytes.get(index);
		}
		return sum;
	}

	function toDeliveredEvent(message:ChatMessage):ChatEvent {
		return Delivered(message.id, message.user, message.body, message.fingerprint, message.origin);
	}

	function historyEntries():Array<String> {
		var entries = new Array<String>();
		for (message in messages) {
			entries.push(formatHistoryEntry(message));
		}
		return entries;
	}

	function formatHistoryEntry(message:ChatMessage):String {
		return message.id + ":" + message.user + ":" + message.body + ":" + message.fingerprint + ":" + message.origin;
	}
}
