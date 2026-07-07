package rust.process;

import rust.Result;
import rust.process.CommandError;

/**
	`rust.process.CommandChild`

	Why
	- Portable `sys.io.Process` exposes Haxe-style live handles and stream wrappers, which correctly
	  require the portable `hxrt.process` runtime.
	- Metal code sometimes needs a much narrower Rust-native lifecycle handle: spawn an explicit
	  command, write one stdin payload, close that pipe, wait, or kill and wait, all without adopting
	  portable stream semantics.
	- Keeping that handle behind a typed extern prevents app-side `std::process::Child` snippets and
	  lets the no-hxrt policy inspect one stable helper shape.

	What
	- A Rust-owned child process handle returned by `NativeCommands.spawnChildFromSpec(...)`.
	- `writeStdinAndClose(...)` writes one UTF-8 payload to the piped child stdin and drops the pipe.
	- `wait()` waits for child completion and returns the exit code, using `1` when Rust reports
	  termination without an integer code.
	- `killAndWait()` requests termination and then waits so the child is reaped.
	- This is intentionally not a reusable stream API, async process API, shell wrapper, detached
	  process API, or portable `sys.io.Process` replacement.

	How
	- The extern maps to `crate::native_process_tools::CommandChild`.
	- The helper owns `std::process::Child`; mutating methods lower to `&mut self` so the handle stays
	  in one Rust owner while lifecycle operations progress.
	- In `metal + rust_no_hxrt`, this type must remain free of `hxrt`, `Dynamic`, Haxe `Array`, and
	  app-side raw Rust snippets; the metal policy fixture checks that output shape.
**/
@:native("crate::native_process_tools::CommandChild")
@:rustExtraSrc("rust/native/native_process_tools.rs")
extern class CommandChild {
	@:rustMutating
	public function writeStdinAndClose(stdinUtf8:String):Result<Bool, CommandError>;

	@:rustMutating
	public function wait():Result<Int, CommandError>;

	@:rustMutating
	public function killAndWait():Result<Int, CommandError>;
}
