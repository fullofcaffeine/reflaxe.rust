package domain;

/**
 * ChatCommand
 *
 * Why
 * - Models the wire protocol as a typed command surface instead of raw token arrays.
 *
 * What
 * - `Send(user, body)` appends a message.
 * - `History` requests a snapshot.
 * - `Quit` requests a graceful shutdown marker.
 *
 * How
 * - Commands are parsed by `protocol.Codec.parseCommand` and consumed by `profile.ChatRuntime`.
 */
enum ChatCommand {
	Send(user:String, body:String);
	History;
	Quit;
}
