package app;

/**
	Stable command identifiers used by the command palette.

	Why
	- We want command execution to be switch-based (easy to audit + deterministic for tests).

	What
	- Navigation, task operations, and persistence commands.
**/
enum CommandId {
	GoDashboard;
	GoTasks;
	GoHelp;

	NewTask;
	ToggleTask;
	DeleteTask;
	EditTitle;

	Save;
	CycleFx;
	Quit;
}
