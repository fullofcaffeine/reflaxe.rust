package rust.tui;

@:rustCargo({ name: "ratatui", version: "0.26" })
@:native("crate::tui_demo")
extern class TuiDemo {
	@:native("run_frame")
	public static function runFrame(frame: Int, tasks: String): Void;
}
