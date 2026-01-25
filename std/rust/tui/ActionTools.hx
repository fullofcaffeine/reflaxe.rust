package rust.tui;

/**
 * Conversion helpers between native action codes and `rust.tui.Action`.
 *
 * Why:
 * - The Rust backend returns compact integer codes for performance and a simple FFI surface.
 * - Haxe apps should operate on an enum (`Action`) instead of magic numbers.
 *
 * What:
 * - `fromCode` maps backend codes into an `Action` value.
 * - `toCode` maps an `Action` back to a backend code (useful for scripted tests).
 *
 * How:
 * - The canonical codes are defined by `rust.tui.TuiDemo.pollAction(...)`:
 *   `0:none, 1:up, 2:down, 3:toggle, 4:quit`.
 */
class ActionTools {
	public static function fromCode(code: Int): Action {
		return switch (code) {
			case 0: None;
			case 1: Up;
			case 2: Down;
			case 3: Toggle;
			case 4: Quit;
			case _: Quit;
		};
	}

	public static function toCode(action: Action): Int {
		return switch (action) {
			case None: 0;
			case Up: 1;
			case Down: 2;
			case Toggle: 3;
			case Quit: 4;
		};
	}
}

