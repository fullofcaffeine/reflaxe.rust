package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;
import haxe.ds.StringMap;
import rust.Option;
import rust.Result;
import rust.metal.Code;

typedef MetalValidatedSend = {
	user:String,
	channel:String,
	body:String
};

/**
 * MetalRuntime
 *
 * Why
 * - Demonstrates the `metal` profile contract: Rust-first typed flow plus occasional low-level
 *   control through framework-provided typed interop facades.
 *
 * What
 * - Uses the same `Result`/`Option` control style as `RustyRuntime`.
 * - Computes message fingerprints via `rust.metal.Code` typed injection hooks.
 *
 * How
 * - `Code.stmt(...)` and `Code.expr(...)` keep low-level Rust snippets behind a typed API and
 *   stay compatible with strict boundary enforcement (`reflaxe_rust_strict_examples`).
 * - Command/event surfaces remain fully typed; only the fingerprint helper crosses the low-level
 *   boundary.
 */
class MetalRuntime implements ChatRuntime {
	static inline final PRESENCE_TTL_SECONDS:Float = 1.2;

	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];
	var activeUsers:StringMap<Float> = new StringMap();

	public function new() {}

	public function profileName():String {
		return "metal";
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

	function validateSend(user:String, channel:String, body:String):Result<MetalValidatedSend, String> {
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
		// Keep a statement-path example in addition to expression injection.
		Code.stmt("let _ = &{0};", body);

		var bodyLength:Int = Code.expr("{0}.len() as i32", body);
		var mixed:Int = Code.expr("((({0} as i64) * 97 + ({1} as i64)) % 1000003) as i32", bodyLength, id);
		return mixed;
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
