package rust.tui;

@:rustExtraSrc("rust/tui/native/tui_demo.rs")
@:rustCargo({ name: "ratatui", version: "0.26" })
@:rustCargo({ name: "crossterm", version: "0.27" })
@:native("crate::tui_demo")
extern class TuiDemo {
	@:native("run_frame")
	public static function runFrame(frame: Int, tasks: String): Void;

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
	 */
	@:native("poll_action")
	public static function pollAction(timeoutMs: Int): Int;
}
