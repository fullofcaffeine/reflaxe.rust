package rust.tui;

/**
	Size constraints for `UiNode.Layout`.

	Why
	- Ratatui uses constraints (`Length`, `Percentage`, `Min`, `Max`) to compute layout splits.
	- We mirror the common set in a target-neutral way.

	What
	- `Fixed(cells)` maps to ratatui `Constraint::Length`.
	- `Percent(p)` maps to ratatui `Constraint::Percentage`.
	- `Min(cells)` / `Max(cells)` map to ratatui `Constraint::Min` / `Constraint::Max`.
	- `Fill` is a convenience meaning "take remaining space" (currently mapped as `Min(0)`).

	How
	- Layout computes areas left-to-right or top-to-bottom depending on `LayoutDir`.
**/
enum Constraint {
	Fixed(cells: Int);
	Percent(p: Int);
	Min(cells: Int);
	Max(cells: Int);
	Fill;
}

