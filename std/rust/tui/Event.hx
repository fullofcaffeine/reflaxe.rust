package rust.tui;

/**
	High-level events emitted by the TUI backend.

	Why
	- The original demo API used a tiny `Action` enum (up/down/toggle/quit).
	- For richer apps (multi-screen, text input, resize-aware layouts, animations), we need a
	  more expressive input/event model.

	What
	- `Key(code, mods)` for keyboard input.
	- `Resize(w, h)` for terminal resizes.
	- `Tick(dtMs)` for time-based updates (animations, timers). This is primarily produced by
	  app code (or headless/scripted runners) rather than the backend.
	- `Quit` to request termination (e.g. 'q' or Esc).
	- `None` when no event is available within the polling timeout.

	How
	- `rust.tui.Tui.pollEvent(...)` maps to `rust.tui.TuiDemo.pollEvent(...)` which returns an
	  `Event` value directly from native Rust.
	- In headless mode, the backend returns `Quit` so applications don't spin forever in CI.
**/
enum Event {
	None;
	Quit;

	Key(code: KeyCode, mods: KeyMods);
	Resize(w: Int, h: Int);

	/**
		Time progression event.

		Notes:
		- The current backend does not synthesize `Tick` events on its own.
		- Apps that want animation/timer updates should generate `Tick` (e.g. based on `Date.now()`)
		  or use a scripted harness that injects ticks deterministically.
	**/
	Tick(dtMs: Int);
}

