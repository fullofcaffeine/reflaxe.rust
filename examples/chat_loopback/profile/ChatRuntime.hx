package profile;

import domain.ChatCommand;
import domain.ChatEvent;

/**
 * ChatRuntime
 *
 * Why
 * - The flagship example needs one domain flow that can run under all profiles while each
 *   profile keeps its own idioms.
 *
 * What
 * - A typed runtime contract with two operations:
 *   - `profileName()` identifies the active profile in output/tests.
 *   - `handle(command)` applies command semantics and returns a typed event.
 *
 * How
 * - `RuntimeFactory` selects a concrete implementation by compile define.
 * - The network scenario talks only to this interface.
 */
interface ChatRuntime {
	function profileName():String;
	function handle(command:ChatCommand):ChatEvent;
}
