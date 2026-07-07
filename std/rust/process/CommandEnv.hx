package rust.process;

/**
	`rust.process.CommandEnv`

	Why
	- Metal command execution needs explicit environment overrides without adopting portable
	  `sys.io.Process` runtime handles or shell-shaped string snippets.
	- Environment names and values are OS boundary strings, but app code should still pass them
	  through a typed Rust-native value instead of positional `Vec<String>` pairs.

	What
	- A small owned sequence of environment mutations for `rust.process.NativeCommands`.
	- `set(key, value)` records one `std::process::Command::env(...)` override.
	- `remove(key)` records one `std::process::Command::env_remove(...)` mutation.
	- `clear()` records one `std::process::Command::env_clear()` mutation.
	- This type owns only environment mutations; cwd+env owned-command combinations live on
	  `rust.process.NativeCommands`.
	- This slice intentionally does not expose live process handles, stdin piping, or async process
	  APIs.

	How
	- The extern maps to `crate::native_process_tools::CommandEnv`.
	- The Rust helper stores owned operations and applies them directly, in order, to
	  `std::process::Command` so `set(...); remove(...)` and `clear(); set(...)` mean exactly what
	  their Rust builder equivalents mean.
	- In `metal + rust_no_hxrt`, this type must remain free of `hxrt`, `Dynamic`, Haxe `Array`, and
	  raw Rust snippets; the metal policy fixture checks that generated shape.
**/
@:native("crate::native_process_tools::CommandEnv")
@:rustExtraSrc("rust/native/native_process_tools.rs")
extern class CommandEnv {
	public function new();

	@:rustMutating
	public function set(key:String, value:String):Void;

	@:rustMutating
	public function remove(key:String):Void;

	@:rustMutating
	public function clear():Void;
}
