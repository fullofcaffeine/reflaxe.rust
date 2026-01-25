package rust.tui;

/**
 * High-level, Haxe-friendly API for the demo TUI backend.
 *
 * Why:
 * - `rust.tui.TuiDemo` is a low-level extern binding to the bundled Rust implementation.
 * - Examples/apps should prefer a typed, idiomatic Haxe surface that avoids raw integer codes
 *   and hides backend-specific details.
 *
 * What:
 * - Thin wrapper around `TuiDemo` that converts input into `Action` and exposes a deterministic
 *   renderer for tests (`renderToString`).
 *
 * How:
 * - All methods delegate to `TuiDemo`.
 * - `poll(...)` uses `ActionTools.fromCode(...)` to map native codes to `Action`.
 */
class Tui {
	public static inline function setHeadless(headless: Bool): Void {
		TuiDemo.setHeadless(headless);
	}

	public static inline function enter(): Void {
		TuiDemo.enter();
	}

	public static inline function exit(): Void {
		TuiDemo.exit();
	}

	public static inline function render(tasks: String): Void {
		TuiDemo.render(tasks);
	}

	public static inline function renderToString(tasks: String): String {
		return TuiDemo.renderToString(tasks);
	}

	public static inline function poll(timeoutMs: Int): Action {
		return ActionTools.fromCode(TuiDemo.pollAction(timeoutMs));
	}
}

