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
 * - `Bye(reason)` for graceful exit acknowledgements.
 * - `Rejected(reason)` for validation/parser failures.
 *
 * How
 * - Produced by profile runtimes and formatted by `protocol.Codec.encodeEvent`.
 */
enum ChatEvent {
	Delivered(id:Int, user:String, body:String, fingerprint:Int, origin:String);
	HistorySnapshot(entries:Array<String>);
	Bye(reason:String);
	Rejected(reason:String);
}
