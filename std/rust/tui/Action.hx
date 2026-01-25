package rust.tui;

/**
 * Discrete user intents produced by the TUI event loop.
 *
 * Why:
 * - TUIs are usually driven by low-level terminal events (keys, mouse, resize).
 * - For portable Haxe code and stable compiler output, we map those events into a small,
 *   target-agnostic set of actions that app logic can consume.
 *
 * What:
 * - A minimal set of commands used by the demo TUI(s): moving selection, toggling, quitting.
 *
 * How:
 * - `rust.tui.Tui.poll(...)` converts the raw integer returned by the native backend into this enum.
 * - You can still access the raw codes via `rust.tui.TuiDemo.pollAction(...)` when needed, but examples
 *   should prefer this type for clarity and portability.
 */
enum Action {
	None;
	Up;
	Down;
	Toggle;
	Quit;
}

