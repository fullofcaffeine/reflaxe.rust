package domain;

/**
 * ChatEvent
 *
 * Why
 * - Keeps server responses typed and profile-agnostic while avoiding class-reference payloads
 *   in enum variants (which complicate Rust trait derives for generated enums).
 *
 * What
 * - `Delivered(...)` for accepted writes.
 * - `HistorySnapshot(entries)` for read-model snapshots (string tokens for deterministic wire output).
 *   - Message entries use `id:user:channel:body:fingerprint:origin`.
 *   - Presence entries use `@presence:<user>` so clients can detect join/leave changes over polling.
 * - `Bye(reason)` for graceful exit acknowledgements.
 * - `Rejected(reason)` for validation/parser failures.
 *
 * How
 * - Produced by profile runtimes and formatted by `protocol.Codec.encodeEvent`.
 */
enum ChatEvent {
	Delivered(id:Int, user:String, channel:String, body:String, fingerprint:Int, origin:String);
	HistorySnapshot(entries:Array<String>);
	Bye(reason:String);
	Rejected(reason:String);
}
