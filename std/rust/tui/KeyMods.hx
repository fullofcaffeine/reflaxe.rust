package rust.tui;

/**
	Keyboard modifier flags for `rust.tui.Event.Key(...)`.

	Why
	- Terminal backends typically report modifiers (ctrl/alt/shift) alongside key presses.
	- Haxe doesn't have Rust-style bitflags, so we expose a tiny, portable bitmask type.

	What
	- An `@:enum abstract` over `Int` where each constant is a single bit.
	- Intended to be combined with bitwise `|` and tested with `has(...)`.

	How
	- The Rust backend maps crossterm's `KeyModifiers` into this bitmask.
	- Example:
	  `if (mods.has(Ctrl) && code == Char("k")) { ... }`
**/
enum abstract KeyMods(Int) from Int to Int {
	/** No modifiers. **/
	public var None: KeyMods = 0;
	/** Control key held. **/
	public var Ctrl: KeyMods = 1;
	/** Alt/Meta key held. **/
	public var Alt: KeyMods = 2;
	/** Shift key held. **/
	public var Shift: KeyMods = 4;

	/** Returns true if this modifier set includes `flag`. **/
	public inline function has(flag: KeyMods): Bool {
		return (this & flag) != 0;
	}
}
