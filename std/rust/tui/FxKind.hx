package rust.tui;

/**
	Deterministic text effects for rich TUI views.

	Why
	- Real TUI apps often want subtle animation (attention cues, motion, pulse) without giving up
	  deterministic tests.
	- By modeling effects as a typed enum, Haxe app code stays portable and tests can assert exact
	  rendered frames under a fixed tick sequence.

	What
	- `None`: no transformation.
	- `Marquee`: horizontal scrolling text (useful for long status lines/headlines).
	- `Typewriter`: reveal text progressively.
	- `Pulse`: deterministic casing pulse for emphasis.
	- `Glitch`: lightweight, deterministic character jitter for "high-energy" UI accents.
	- `ParticleBurst`: center-origin particle animation intended for celebratory overlays.

	How
	- Effects are resolved in the Rust renderer (`std/rust/tui/native/tui_demo.rs`).
	- App code controls animation by incrementing a `phase` value (typically on `Event.Tick`).
**/
enum FxKind {
	None;
	Marquee;
	Typewriter;
	Pulse;
	Glitch;
	ParticleBurst;
}
