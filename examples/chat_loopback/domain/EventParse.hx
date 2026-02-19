package domain;

/**
 * EventParse
 *
 * Why
 * - `ChatEvent` parsing crosses an unavoidable text boundary for socket-based multi-instance mode.
 * - Keeping parse results typed avoids `Dynamic` payload plumbing in the app/runtime layer.
 *
 * What
 * - `Parsed(event)` carries a validated typed event.
 * - `Invalid(reason)` carries deterministic parse-failure details.
 *
 * How
 * - Returned by `protocol.Codec.parseEvent`.
 */
enum EventParse {
	EventParsed(event:ChatEvent);
	EventInvalid(reason:String);
}
