package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;
import rust.Option;
import rust.Result;

typedef ValidatedSend = {
	user:String,
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
	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];

	public function new() {}

	public function profileName():String {
		return "rusty";
	}

	public function handle(command:ChatCommand):ChatEvent {
		return switch (command) {
			case Send(user, body):
				switch (validateSend(user, body)) {
					case Ok(valid):
						var message = appendMessage(valid.user, valid.body);
						toDeliveredEvent(message);
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

	function validateSend(user:String, body:String):Result<ValidatedSend, String> {
		var trimmedUser = StringTools.trim(user);
		var trimmedBody = StringTools.trim(body);
		if (trimmedUser == "") {
			return Err("empty-user");
		}
		if (trimmedBody == "") {
			return Err("empty-body");
		}
		return Ok({
			user: trimmedUser,
			body: trimmedBody
		});
	}

	function appendMessage(user:String, body:String):ChatMessage {
		var fingerprint = computeFingerprint(body, nextId);
		var message = new ChatMessage(nextId++, user, body, fingerprint, profileName());
		messages.push(message);
		return message;
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
