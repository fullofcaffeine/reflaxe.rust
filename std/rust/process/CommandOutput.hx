package rust.process;

import rust.Result;

/**
	`rust.process.CommandOutput`

	Why
	- `std::process::Command::output()` returns status, stdout, and stderr from one owned process
	  execution. Metal Haxe code needs that Rust-shaped result without importing portable
	  `sys.io.Process` live-stream semantics or the `hxrt.process` runtime handle.
	- Exposing raw fields would couple Haxe callers to the helper module's Rust storage details.
	  Methods keep the boundary typed and let the helper own byte-to-UTF-8 validation.

	What
	- Owned command output value returned by `rust.process.NativeCommands.outputUtf8(...)` and the
	  related owned-output helpers.
	- `statusCode()` exposes the process exit code, using `1` when Rust reports termination without
	  an integer code.
	- `stdoutUtf8()` and `stderrUtf8()` decode captured bytes as UTF-8 and return explicit
	  `rust.Result` values.
	- This is still an owned-output API, not a live child process, pipe, shell, async task, or
	  portable `sys.io.Process` replacement.

	How
	- The extern maps to `crate::native_process_tools::CommandOutput`, a small Rust helper struct.
	- The helper stores raw stdout/stderr bytes and performs UTF-8 conversion only when requested.
	- In `metal + rust_no_hxrt`, this type must stay free of `hxrt`, `Dynamic`, Haxe `Array`, and
	  app-side raw Rust snippets; the metal policy fixture checks that output shape.
**/
@:native("crate::native_process_tools::CommandOutput")
@:rustExtraSrc("rust/native/native_process_tools.rs")
extern class CommandOutput {
	public function statusCode():Int;
	public function stdoutUtf8():Result<String, String>;
	public function stderrUtf8():Result<String, String>;
}
