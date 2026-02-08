package rust.tui;

@:rustExtraSrc("rust/tui/native/tui_demo.rs")
@:rustCargo({ name: "ratatui", version: "0.26" })
@:rustCargo({ name: "crossterm", version: "0.27" })
@:native("crate::tui_demo")
extern class TuiDemo {
	/**
	 * Force headless (true) or interactive (false) mode.
	 *
	 * If not set, `enter()` will auto-detect based on whether stdin/stdout are TTYs.
	 * Even if set to interactive, `enter()` may fall back to headless if terminal initialization
	 * fails (e.g. CI / non-TTY environments).
	 *
	 * Notes:
	 * - Headless mode is primarily intended for deterministic tests via `renderToString(...)`.
	 * - When headless, `pollAction(...)` immediately returns `quit` so application loops don't spin forever.
	 * - When headless, `render(...)` is a no-op (to keep CI logs quiet); use `renderToString(...)` instead.
	 */
	@:native("set_headless")
	public static function setHeadless(headless: Bool): Void;

	@:native("run_frame")
	public static function runFrame(frame: Int, tasks: String): Void;

	/**
	 * Render the provided `tasks` lines to a deterministic string using ratatui's `TestBackend`.
	 *
	 * Why:
	 * - Lets us test/CI-verify TUIs without requiring a real TTY (similar to "Playwright", but for TUIs).
	 *
	 * What:
	 * - Returns a full buffer dump (including borders/title) as a single `String`.
	 *
	 * How:
	 * - Calls into the bundled Rust module (`crate::tui_demo::render_to_string`) which renders to an
	 *   off-screen buffer and converts it to a string. This does not touch global terminal state.
	 */
	@:native("render_to_string")
	public static function renderToString(tasks: String): String;

	@:native("enter")
	public static function enter(): Void;

	@:native("exit")
	public static function exit(): Void;

	@:native("render")
	public static function render(tasks: String): Void;

	/**
	 * Returns an action code:
	 * - 0 = none
	 * - 1 = up
	 * - 2 = down
	 * - 3 = toggle
	 * - 4 = quit
	 *
	 * Notes:
	 * - In headless mode, this returns `4` immediately (quit).
	 * - To test TUI rendering deterministically, prefer `renderToString(...)`.
	 */
	@:native("poll_action")
	public static function pollAction(timeoutMs: Int): Int;
}
