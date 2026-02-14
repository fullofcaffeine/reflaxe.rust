package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;

/**
 * PortableRuntime
 *
 * Why
 * - Demonstrates a Haxe-first runtime style for the flagship scenario.
 *
 * What
 * - Uses only standard Haxe data/modeling with no Rust-first surface types.
 * - Applies basic validation and stores chat history in `Array<ChatMessage>`.
 *
 * How
 * - Fingerprint is `body.length` (simple deterministic marker).
 * - Returns typed `ChatEvent` variants for all command paths.
 */
class PortableRuntime implements ChatRuntime {
	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];

	public function new() {}

	public function profileName():String {
		return "portable";
	}

	public function handle(command:ChatCommand):ChatEvent {
		return switch (command) {
			case Send(user, body):
				var trimmedUser = StringTools.trim(user);
				var trimmedBody = StringTools.trim(body);
				if (trimmedUser == "") {
					Rejected("empty-user");
				} else if (trimmedBody == "") {
					Rejected("empty-body");
				} else {
					var message = new ChatMessage(nextId++, trimmedUser, trimmedBody, trimmedBody.length, profileName());
					messages.push(message);
					toDeliveredEvent(message);
				}
			case History:
				HistorySnapshot(historyEntries());
			case Quit:
				Bye(profileName() + ":" + messages.length);
		};
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
