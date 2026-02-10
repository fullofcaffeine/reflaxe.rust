package app;

/**
	Top-level screens of the TUI todo app.

	Why
	- This example is a compiler harness, so we want a clear state machine that exercises
	  enums + switch lowering heavily.

	What
	- Dashboard: high-level stats + progress.
	- Tasks: list view (with optional preview on wide terminals).
	- Details: focused view for a single task.
	- Help: keybindings and usage notes.
**/
enum Screen {
	Dashboard;
	Tasks;
	Details(taskId: String);
	Help;
}

