package rust.process;

import rust.PathBuf;
import rust.Ref;
import rust.Vec;

/**
	`rust.process.CommandSpec`

	Why
	- The first `NativeCommands` slices intentionally exposed narrow one-shot helpers for program,
	  args, cwd, env, and stdin combinations. That kept each Rust lowering inspectable, but adding
	  every new option as another method would make the API harder to read and harder to gate.
	- Metal code needs a typed command configuration value that still emits direct
	  `std::process::Command` builder calls and still avoids portable `sys.io.Process` runtime
	  semantics.

	What
	- An owned Rust-native command specification for `NativeCommands.statusCodeFromSpec(...)` and
	  `NativeCommands.outputUtf8FromSpec(...)`.
	- The constructor clones the executable `PathBuf` and argument `Vec<String>` into the spec.
	- `inDir(...)` stores an optional cwd, `withEnv(...)` stores a cloned `CommandEnv`, and
	  `withStdin(...)` stores one owned UTF-8 stdin payload.
	- This is a reusable config value for owned one-shot executions, not a live child process,
	  reusable pipe, async task, shell wrapper, or portable `sys.io.Process` replacement.

	How
	- The extern maps to `crate::native_process_tools::CommandSpec`.
	- `@:rustExtraSrc("rust/native/native_process_tools.rs")` copies the helper module into
	  generated crates, matching the other process facades.
	- Inputs are typed as `rust.Ref<...>` where the Rust helper only needs to clone from a borrow.
	  That keeps Haxe callsites ergonomic while the backend emits Rust `&T` parameters.
	- In `metal + rust_no_hxrt`, this type must stay free of `hxrt`, `Dynamic`, Haxe `Array`, and
	  app-side raw Rust snippets; the metal policy fixture checks that output shape.
**/
@:native("crate::native_process_tools::CommandSpec")
@:rustExtraSrc("rust/native/native_process_tools.rs")
extern class CommandSpec {
	public function new(program:Ref<PathBuf>, args:Ref<Vec<String>>);

	@:rustMutating
	public function inDir(cwd:Ref<PathBuf>):Void;

	@:rustMutating
	public function withEnv(env:Ref<CommandEnv>):Void;

	@:rustMutating
	public function withStdin(stdinUtf8:String):Void;
}
