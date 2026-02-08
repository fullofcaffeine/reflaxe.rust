# TUI (Ratatui) helpers

`reflaxe.rust` ships a small wrapper around `ratatui` + `crossterm` so examples/apps can build TUIs **without calling `untyped __rust__`** directly.

## High-level API (`rust.tui.Tui`)

Most Haxe code should use:

- `rust.tui.Tui` — a typed wrapper around the native backend
- `rust.tui.Action` — an enum of user intents (`Up`, `Down`, `Toggle`, `Quit`, `None`)

The low-level native binding (`TuiDemo`) still exists, but examples should prefer `Tui`.

## `rust.tui.TuiDemo`

Minimal building block used by `examples/tui_todo`.

- `TuiDemo.setHeadless(true|false)` — force headless or interactive mode.
  - If not set, `TuiDemo.enter()` auto-detects based on whether stdin/stdout are TTYs.
  - Even if set to interactive, `enter()` may fall back to headless if terminal initialization fails
    (for example when `cargo run` is executed in CI or other non-TTY environments).
- `TuiDemo.enter()` — initializes the terminal (raw mode + alternate screen) for interactive mode.
- `TuiDemo.render(lines)` — renders the given newline-delimited string as a list.
  - In headless mode this is a no-op to avoid spamming CI logs.
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

## Running the demos

**Interactive** (real terminal required):

- `cd examples/tui_todo && haxe compile.hxml`
- `cd examples/tui_todo/out && cargo run -q`

Rusty profile variant:

- `cd examples/tui_todo && haxe compile.rusty.hxml`
- `cd examples/tui_todo/out_rusty && cargo run -q`

**Headless / CI-friendly**:

- `cd examples/tui_todo && haxe compile.ci.hxml`
- `cd examples/tui_todo/out_ci && cargo test`

Notes:
- In headless mode, use `renderToString(...)` for validation; `render(...)` is intentionally a no-op.
- The headless mode flag can be set from Haxe (`-D tui_headless` in the example `compile.ci.hxml`) or by calling `Tui.setHeadless(true)` before `enter()`.
