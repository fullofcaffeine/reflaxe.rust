# TUI (Ratatui) helpers

`reflaxe.rust` ships a small wrapper around `ratatui` + `crossterm` so examples/apps can build TUIs **without calling `untyped __rust__`** directly.

## `rust.tui.TuiDemo`

Minimal building block used by `examples/tui_todo`.

- `TuiDemo.setHeadless(true|false)` — force headless (deterministic text frames) or interactive mode.
  - If not set, `TuiDemo.enter()` auto-detects based on whether stdin/stdout are TTYs.
- `TuiDemo.enter()` — initializes the terminal (raw mode + alternate screen) for interactive mode.
- `TuiDemo.render(lines)` — renders the given newline-delimited string as a list.
- `TuiDemo.pollAction(timeoutMs)` — returns an action code (0..4) suitable for mapping to an enum.
- `TuiDemo.exit()` — restores terminal state (safe to call in headless mode too).

Cargo dependencies are declared from Haxe via metadata on `TuiDemo`:

- `@:rustCargo({ name: "ratatui", version: "0.26" })`
- `@:rustCargo({ name: "crossterm", version: "0.27" })`
