package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;
import haxe.ds.StringMap;

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
	static inline final PRESENCE_TTL_SECONDS:Float = 1.2;

	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];
	var activeUsers:StringMap<Float> = new StringMap();

	public function new() {}

	public function profileName():String {
		return "portable";
	}

	public function handle(command:ChatCommand):ChatEvent {
		return switch (command) {
			case Send(user, channel, body):
				var trimmedUser = StringTools.trim(user);
				var trimmedChannel = StringTools.trim(channel);
				var trimmedBody = StringTools.trim(body);
				if (trimmedUser == "") {
					Rejected("empty-user");
				} else if (trimmedChannel == "") {
					Rejected("empty-channel");
				} else if (trimmedBody == "") {
					Rejected("empty-body");
				} else {
					touchUser(trimmedUser);
					var message = new ChatMessage(nextId++, trimmedUser, trimmedChannel, trimmedBody, trimmedBody.length, profileName());
					messages.push(message);
					toDeliveredEvent(message);
				}
			case Presence(user, online):
				var trimmedUser = StringTools.trim(user);
				if (trimmedUser == "") {
					Rejected("empty-user");
				} else {
					if (online) {
						touchUser(trimmedUser);
					} else {
						activeUsers.remove(trimmedUser);
					}
					HistorySnapshot(historyEntries());
				}
			case History:
				HistorySnapshot(historyEntries());
			case Quit:
				Bye(profileName() + ":" + messages.length);
		};
	}

	public function pollEvents():Array<ChatEvent> {
		return [];
	}

	function toDeliveredEvent(message:ChatMessage):ChatEvent {
		return Delivered(message.id, message.user, message.channel, message.body, message.fingerprint, message.origin);
	}

	function historyEntries():Array<String> {
		prunePresence();
		var entries = new Array<String>();
		for (message in messages) {
			entries.push(formatHistoryEntry(message));
		}
		for (presenceEntry in presenceEntries()) {
			entries.push(presenceEntry);
		}
		return entries;
	}

	function formatHistoryEntry(message:ChatMessage):String {
		return message.id
			+ ":"
			+ message.user
			+ ":"
			+ message.channel
			+ ":"
			+ message.body
			+ ":"
			+ message.fingerprint
			+ ":"
			+ message.origin;
	}

	function touchUser(user:String):Void {
		activeUsers.set(user, Sys.time());
	}

	function prunePresence():Void {
		var now = Sys.time();
		for (user in activeUsers.keys()) {
			var seen = activeUsers.get(user);
			if (seen == null || (now - seen) > PRESENCE_TTL_SECONDS) {
				activeUsers.remove(user);
			}
		}
	}

	function presenceEntries():Array<String> {
		var users = new Array<String>();
		for (user in activeUsers.keys()) {
			users.push(user);
		}
		users.sort(compareUserNames);

		var entries = new Array<String>();
		for (user in users) {
			entries.push("@presence:" + user);
		}
		return entries;
	}

	static function compareUserNames(a:String, b:String):Int {
		if (a < b) {
			return -1;
		}
		if (a > b) {
			return 1;
		}
		return 0;
	}
}
