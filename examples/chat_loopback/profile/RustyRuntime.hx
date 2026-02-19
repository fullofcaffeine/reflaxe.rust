package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;
import haxe.ds.StringMap;
import rust.Option;
import rust.Result;

typedef ValidatedSend = {
	user:String,
	channel:String,
	body:String
};

/**
 * RustyRuntime
 *
 * Why
 * - Demonstrates Rust-first API style in Haxe by using explicit `Result`/`Option` flow
 *   instead of exception-centric control paths.
 *
 * What
 * - Keeps the same external command semantics as other profiles.
 * - Validation returns `Result<ValidatedSend, String>`.
 * - Quit summary reads latest message through `Option<String>`.
 *
 * How
 * - Runtime stays typed end-to-end and converts result/option states into `ChatEvent` values.
 */
class RustyRuntime implements ChatRuntime {
	static inline final PRESENCE_TTL_SECONDS:Float = 1.2;

	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];
	var activeUsers:StringMap<Float> = new StringMap();

	public function new() {}

	public function profileName():String {
		return "rusty";
	}

	public function handle(command:ChatCommand):ChatEvent {
		return switch (command) {
			case Send(user, channel, body):
				switch (validateSend(user, channel, body)) {
					case Ok(valid):
						var message = appendMessage(valid.user, valid.channel, valid.body);
						toDeliveredEvent(message);
					case Err(error):
						Rejected(error);
				}
			case Presence(user, online):
				switch (validatePresenceUser(user)) {
					case Ok(validUser):
						if (online) {
							touchUser(validUser);
						} else {
							activeUsers.remove(validUser);
						}
						HistorySnapshot(historyEntries());
					case Err(error):
						Rejected(error);
				}
			case History:
				HistorySnapshot(historyEntries());
			case Quit:
				var latestSummary = switch (latestBody()) {
					case Some(body):
						"latest=" + body;
					case None:
						"latest=<none>";
				};
				Bye(profileName() + ":" + messages.length + ":" + latestSummary);
		};
	}

	public function pollEvents():Array<ChatEvent> {
		return [];
	}

	function validateSend(user:String, channel:String, body:String):Result<ValidatedSend, String> {
		var trimmedUser = StringTools.trim(user);
		var trimmedChannel = StringTools.trim(channel);
		var trimmedBody = StringTools.trim(body);
		if (trimmedUser == "") {
			return Err("empty-user");
		}
		if (trimmedChannel == "") {
			return Err("empty-channel");
		}
		if (trimmedBody == "") {
			return Err("empty-body");
		}
		return Ok({
			user: trimmedUser,
			channel: trimmedChannel,
			body: trimmedBody
		});
	}

	function appendMessage(user:String, channel:String, body:String):ChatMessage {
		touchUser(user);
		var fingerprint = computeFingerprint(body, nextId);
		var message = new ChatMessage(nextId++, user, channel, body, fingerprint, profileName());
		messages.push(message);
		return message;
	}

	function validatePresenceUser(user:String):Result<String, String> {
		var trimmedUser = StringTools.trim(user);
		if (trimmedUser == "") {
			return Err("empty-user");
		}
		return Ok(trimmedUser);
	}

	function latestBody():Option<String> {
		if (messages.length == 0) {
			return None;
		}
		var latest = messages[messages.length - 1];
		return Some(latest.body);
	}

	function computeFingerprint(body:String, id:Int):Int {
		return body.length * 31 + id;
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
