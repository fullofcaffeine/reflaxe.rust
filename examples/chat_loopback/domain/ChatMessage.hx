package domain;

/**
 * ChatMessage
 *
 * Why
 * - Keeps chat payloads strongly typed across profile runtimes and wire encoding.
 * - Avoids untyped map payloads for command/event data in examples.
 *
 * What
 * - Immutable message record containing identity, sender, body, profile-specific fingerprint,
 *   channel, and profile origin marker.
 *
 * How
 * - Constructed by profile runtime implementations (`PortableRuntime`, `IdiomaticRuntime`,
 *   `RustyRuntime`, `MetalRuntime`) and serialized by `protocol.Codec`.
 */
class ChatMessage {
	public var id(default, null):Int;
	public var user(default, null):String;
	public var channel(default, null):String;
	public var body(default, null):String;
	public var fingerprint(default, null):Int;
	public var origin(default, null):String;

	public function new(id:Int, user:String, channel:String, body:String, fingerprint:Int, origin:String) {
		this.id = id;
		this.user = user;
		this.channel = channel;
		this.body = body;
		this.fingerprint = fingerprint;
		this.origin = origin;
	}
}
