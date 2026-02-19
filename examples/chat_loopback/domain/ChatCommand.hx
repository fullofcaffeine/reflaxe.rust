package domain;

/**
 * ChatCommand
 *
 * Why
 * - Models the wire protocol as a typed command surface instead of raw token arrays.
 *
 * What
 * - `Send(user, channel, body)` appends a channel-scoped message.
 * - `Presence(user, online)` updates user liveness (`online=true` heartbeat, `online=false` explicit leave).
 * - `History` requests a snapshot.
 * - `Quit` requests a graceful shutdown marker.
 *
 * How
 * - Commands are parsed by `protocol.Codec.parseCommand` and consumed by `profile.ChatRuntime`.
 */
enum ChatCommand {
	Send(user:String, channel:String, body:String);
	Presence(user:String, online:Bool);
	History;
	Quit;
}
