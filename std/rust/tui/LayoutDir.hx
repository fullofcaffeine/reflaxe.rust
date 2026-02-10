package rust.tui;

/**
	Layout direction for `UiNode.Layout`.

	Why
	- Most TUIs are built by splitting the screen into rows/columns with constraints.

	What
	- Horizontal: split into columns (left/right).
	- Vertical: split into rows (top/bottom).

	How
	- `UiNode.Layout(Vertical, [...], [...])` is typically used for header/body/footer.
**/
enum LayoutDir {
	Horizontal;
	Vertical;
}

