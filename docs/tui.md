# TUI (Ratatui) helpers

`reflaxe.rust` ships a small wrapper around `ratatui` + `crossterm` so examples/apps can build TUIs **without calling `untyped __rust__`** directly.

## `rust.tui.TuiDemo`

Minimal building block used by `examples/tui_todo`.

- `TuiDemo.setHeadless(true|false)` — force headless or interactive mode.
  - If not set, `TuiDemo.enter()` auto-detects based on whether stdin/stdout are TTYs.
- `TuiDemo.enter()` — initializes the terminal (raw mode + alternate screen) for interactive mode.
- `TuiDemo.render(lines)` — renders the given newline-delimited string as a list.
- `TuiDemo.renderToString(lines)` — renders to a deterministic string buffer via ratatui `TestBackend`.
- `TuiDemo.pollAction(timeoutMs)` — returns an action code (0..4) suitable for mapping to an enum.
  - In headless mode this returns `quit` immediately so apps don't spin forever when there's no TTY.
- `TuiDemo.exit()` — restores terminal state (safe to call in headless mode too).

Cargo dependencies are declared from Haxe via metadata on `TuiDemo`:

- `@:rustCargo({ name: "ratatui", version: "0.26" })`
- `@:rustCargo({ name: "crossterm", version: "0.27" })`

## Testing a TUI (Playwright-style, but for terminals)

Use `renderToString(...)` and assert on the output in `cargo test`:

- `examples/tui_todo/Harness.hx` produces a deterministic frame via `Tui.renderToString(...)`.
- `examples/tui_todo/native/tui_tests.rs` calls the compiled Haxe harness and does an **exact frame snapshot** (`assert_eq!`) against a golden string.

This keeps tests:

- deterministic (no real terminal needed)
- fast (pure buffer renders)
- injection-free at the app layer (no `__rust__` in examples)
