package rust.tui;

/**
	Named styles used by the demo TUI renderer.

	Why
	- Passing full color/style structs through the Haxe<->Rust boundary is possible, but it
	  increases the surface area and makes snapshots noisier.
	- For examples we mostly need a consistent "design system": title/accent/selected/muted, etc.

	What
	- A small set of semantic style tokens.
	- The Rust backend maps each token to a concrete ratatui `Style` (colors + modifiers).

	How
	- Use these tokens in `UiNode` widgets that accept a `style`.
	- If you need a new style, add a new token and update the Rust mapping in
	  `std/rust/tui/native/tui_demo.rs`.
**/
enum StyleToken {
	Normal;
	Muted;
	Title;
	Accent;
	Selected;
	Success;
	Warning;
	Danger;
}

