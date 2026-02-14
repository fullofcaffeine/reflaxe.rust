package domain;

/**
 * CommandParse
 *
 * Why
 * - Parsing is an unavoidable text boundary; this enum captures success/failure without
 *   exceptions or untyped payload bridges.
 *
 * What
 * - `Parsed(command)` carries a validated typed command.
 * - `Invalid(reason)` carries a deterministic parse failure message.
 *
 * How
 * - Returned by `protocol.Codec.parseCommand`.
 */
enum CommandParse {
	Parsed(command:ChatCommand);
	Invalid(reason:String);
}
