package profile;

import domain.ChatCommand;
import domain.ChatEvent;
import domain.ChatMessage;
import rust.Option;
import rust.Result;
import rust.metal.Code;

typedef MetalValidatedSend = {
	user:String,
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
	var nextId:Int = 1;
	var messages:Array<ChatMessage> = [];

	public function new() {}

	public function profileName():String {
		return "metal";
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

	function validateSend(user:String, body:String):Result<MetalValidatedSend, String> {
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
		// Keep a statement-path example in addition to expression injection.
		Code.stmt("let _ = &{0};", body);

		var bodyLength:Int = Code.expr("{0}.len() as i32", body);
		var mixed:Int = Code.expr("((({0} as i64) * 97 + ({1} as i64)) % 1000003) as i32", bodyLength, id);
		return mixed;
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
