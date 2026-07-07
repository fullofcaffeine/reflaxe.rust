package rust.process;

/**
	`rust.process.CommandEnv`

	Why
	- Metal command execution needs explicit environment overrides without adopting portable
	  `sys.io.Process` runtime handles or shell-shaped string snippets.
	- Environment names and values are OS boundary strings, but app code should still pass them
	  through a typed Rust-native value instead of positional `Vec<String>` pairs.

	What
	- A small owned set of environment overrides for `rust.process.NativeCommands`.
	- `set(key, value)` records one `std::process::Command::env(...)` override.
	- This first slice intentionally does not expose inherited-environment clearing, variable
	  removal, cwd+env combinations, live process handles, stdin piping, or async process APIs.

	How
	- The extern maps to `crate::native_process_tools::CommandEnv`.
	- The Rust helper stores owned `(String, String)` pairs and applies them directly to
	  `std::process::Command`.
	- In `metal + rust_no_hxrt`, this type must remain free of `hxrt`, `Dynamic`, Haxe `Array`, and
	  raw Rust snippets; the metal policy fixture checks that generated shape.
**/
@:native("crate::native_process_tools::CommandEnv")
@:rustExtraSrc("rust/native/native_process_tools.rs")
extern class CommandEnv {
	public function new();

	@:rustMutating
	public function set(key:String, value:String):Void;
}
