package rust.process;

/**
	`rust.process.CommandError`

	Why
	- The original owned-command facade returned `Result<..., String>` for a small, stable first
	  slice. That is source-compatible, but callers that need recovery policy should not parse error
	  text to distinguish spawn/wait IO failures from UTF-8 decode failures.
	- Metal/no-hxrt code should still stay on typed Rust-shaped values instead of exceptions,
	  `Dynamic`, or raw `std::process::Command` snippets.

	What
	- Typed error record used by the opt-in `Detailed` command helpers.
	- `isIo()` covers Rust `std::io::Error` paths such as missing executables, failed spawn, wait,
	  and output collection failures.
	- `isUtf8()` covers byte-to-String decode failures from captured stdout/stderr accessors.
	- `isStdin()` covers helper-owned stdin pipe setup/write failures.
	- `message()` returns Rust's human-readable detail for diagnostics; callers should branch on the
	  typed predicates first and use the message only for reporting.

	How
	- The extern maps to `crate::native_process_tools::CommandError`.
	- The helper lives in the same copied Rust module as `NativeCommands`, `CommandOutput`,
	  `CommandEnv`, and `CommandSpec`.
	- In `metal + rust_no_hxrt`, this type must remain a narrow Rust helper with no `hxrt`,
	  `Dynamic`, Haxe exception, or raw-snippet dependency.
**/
@:native("crate::native_process_tools::CommandError")
@:rustExtraSrc("rust/native/native_process_tools.rs")
extern class CommandError {
	public function message():String;
	public function isIo():Bool;
	public function isUtf8():Bool;
	public function isStdin():Bool;
}
