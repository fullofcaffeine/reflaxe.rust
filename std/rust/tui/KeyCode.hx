package rust.tui;

/**
	Keyboard key codes for `rust.tui.Event.Key(...)`.

	Why
	- We want a stable, target-agnostic key model that Haxe apps can switch on.
	- Backends differ (crossterm, termion, web); we normalize to a small set of keys that
	  matter for app-level UX.

	What
	- A structured key enum with common navigation keys and a `Char` variant.
	- `Char` is used for printable keys and is represented as a 1-character string.

	How
	- The Rust backend maps crossterm's `KeyCode` into this enum.
	- Keys we don't model yet are lowered to `Unknown` so apps can ignore them safely.
**/
enum KeyCode {
	Unknown;

	Char(ch: String);

	Enter;
	Esc;
	Tab;
	Backspace;
	Delete;

	Up;
	Down;
	Left;
	Right;

	Home;
	End;
	PageUp;
	PageDown;
}

