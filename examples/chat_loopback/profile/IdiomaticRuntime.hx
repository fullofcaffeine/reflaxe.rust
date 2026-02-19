package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;
import haxe.ds.StringMap;

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
	static inline final PRESENCE_TTL_SECONDS:Float = 1.2;

	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];
	var activeUsers:StringMap<Float> = new StringMap();

	public function new() {}

	public function profileName():String {
		return "idiomatic";
	}

	public function handle(command:ChatCommand):ChatEvent {
		return switch (command) {
			case Send(user, channel, body):
				handleSend(user, channel, body);
			case Presence(user, online):
				handlePresence(user, online);
			case History:
				HistorySnapshot(historyEntries());
			case Quit:
				Bye(profileName() + ":" + messages.length);
		};
	}

	public function pollEvents():Array<ChatEvent> {
		return [];
	}

	function handleSend(user:String, channel:String, body:String):ChatEvent {
		final trimmedUser = StringTools.trim(user);
		final trimmedChannel = StringTools.trim(channel);
		final trimmedBody = StringTools.trim(body);
		if (trimmedUser == "") {
			return Rejected("empty-user");
		}
		if (trimmedChannel == "") {
			return Rejected("empty-channel");
		}
		if (trimmedBody == "") {
			return Rejected("empty-body");
		}

		final fingerprint = asciiFingerprint(trimmedBody);
		touchUser(trimmedUser);
		final message = new ChatMessage(nextId++, trimmedUser, trimmedChannel, trimmedBody, fingerprint, profileName());
		messages.push(message);
		return toDeliveredEvent(message);
	}

	function handlePresence(user:String, online:Bool):ChatEvent {
		final trimmedUser = StringTools.trim(user);
		if (trimmedUser == "") {
			return Rejected("empty-user");
		}

		if (online) {
			touchUser(trimmedUser);
		} else {
			activeUsers.remove(trimmedUser);
		}
		return HistorySnapshot(historyEntries());
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
		final now = Sys.time();
		for (user in activeUsers.keys()) {
			final seen = activeUsers.get(user);
			if (seen == null || (now - seen) > PRESENCE_TTL_SECONDS) {
				activeUsers.remove(user);
			}
		}
	}

	function presenceEntries():Array<String> {
		final users = new Array<String>();
		for (user in activeUsers.keys()) {
			users.push(user);
		}
		users.sort(compareUserNames);

		final entries = new Array<String>();
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
