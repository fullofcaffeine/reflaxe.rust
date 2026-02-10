package app;

/**
	Modal overlays used by the app.

	Why
	- A complex TUI needs transient states: command palette, text input prompts, confirmations.
	- This is an intentionally explicit enum to keep behavior deterministic and compiler-friendly.
**/
enum Modal {
	None;
	Palette(query: String, selected: Int);
	Input(prompt: String, buffer: String, target: InputTarget);
	Confirm(prompt: String, action: ConfirmAction);
}

enum InputTarget {
	NewTaskTitle;
	EditTaskTitle(taskId: String);
}

enum ConfirmAction {
	DeleteTask(taskId: String);
}

