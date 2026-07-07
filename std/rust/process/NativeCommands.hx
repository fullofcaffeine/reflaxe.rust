package rust.process;

import rust.PathBuf;
import rust.Ref;
import rust.Result;
import rust.Vec;
import rust.process.CommandOutput;

/**
	`rust.process.NativeCommands`

	Why
	- Portable `sys.io.Process` preserves Haxe process semantics: live child handles, Haxe
	  `Input`/`Output` streams, omitted-args shell fallback, exceptions, and close/kill lifecycle.
	  That contract justifiably uses `hxrt.process.ProcessHandle`.
	- Metal code sometimes needs the narrower Rust contract: run an explicit executable with
	  explicit arguments and inspect owned output without importing Haxe stream/runtime behavior.
	- A typed facade keeps app code away from raw `std::process::Command` snippets while preserving
	  the generated Rust shape for no-hxrt inspection.

	What
	- First M44 Rust-native process helper surface.
	- `statusCode(...)` runs a command and returns its process exit code.
	- `stdoutUtf8(...)` captures stdout and decodes it as UTF-8.
	- `outputUtf8(...)` captures status, stdout, and stderr in one owned `CommandOutput` value.
	- `statusCodeInDir(...)` and `outputUtf8InDir(...)` run the same owned command shape with an
	  explicit Rust `current_dir(...)`.
	- `statusCodeWithEnv(...)` and `outputUtf8WithEnv(...)` run the same owned command shape with
	  explicit `CommandEnv` overrides.
	- `statusCodeInDirWithEnv(...)` and `outputUtf8InDirWithEnv(...)` combine explicit
	  `current_dir(...)` and ordered `CommandEnv` mutations for the same owned-output contract.
	- `statusCodeWithStdin(...)` and `outputUtf8WithStdin(...)` write one owned UTF-8 string to
	  child stdin while keeping the child handle and pipe lifecycle inside the helper.
	- Fallible operations return `rust.Result<..., String>` so callers handle errors explicitly.
	- This is not a replacement for `sys.io.Process` and intentionally does not expose live pipes,
	  detached handles, reusable stdin pipes, or async process APIs yet.

	How
	- `@:native("crate::native_process_tools::NativeCommands")` binds to a small Rust helper module.
	- `@:rustExtraSrc("rust/native/native_process_tools.rs")` copies that helper into generated
	  crates.
	- The executable is passed as `rust.PathBuf` by reference and args are passed as
	  `rust.Ref<rust.Vec<String>>`. Do not use Haxe `Array<String>` here: `Array` carries Haxe
	  runtime semantics and would weaken the no-hxrt proof.
	- In `metal + rust_no_hxrt`, these helpers should not require `hxrt`; policy fixtures gate the
	  generated crate shape for this subset.
**/
@:native("crate::native_process_tools::NativeCommands")
@:rustExtraSrc("rust/native/native_process_tools.rs")
extern class NativeCommands {
	public static function statusCode(program:Ref<PathBuf>, args:Ref<Vec<String>>):Result<Int, String>;
	public static function stdoutUtf8(program:Ref<PathBuf>, args:Ref<Vec<String>>):Result<String, String>;
	public static function outputUtf8(program:Ref<PathBuf>, args:Ref<Vec<String>>):Result<CommandOutput, String>;
	public static function statusCodeInDir(program:Ref<PathBuf>, args:Ref<Vec<String>>, cwd:Ref<PathBuf>):Result<Int, String>;
	public static function outputUtf8InDir(program:Ref<PathBuf>, args:Ref<Vec<String>>, cwd:Ref<PathBuf>):Result<CommandOutput, String>;
	public static function statusCodeWithEnv(program:Ref<PathBuf>, args:Ref<Vec<String>>, env:Ref<CommandEnv>):Result<Int, String>;
	public static function outputUtf8WithEnv(program:Ref<PathBuf>, args:Ref<Vec<String>>, env:Ref<CommandEnv>):Result<CommandOutput, String>;
	public static function statusCodeInDirWithEnv(program:Ref<PathBuf>, args:Ref<Vec<String>>, cwd:Ref<PathBuf>, env:Ref<CommandEnv>):Result<Int, String>;
	public static function outputUtf8InDirWithEnv(program:Ref<PathBuf>, args:Ref<Vec<String>>, cwd:Ref<PathBuf>, env:Ref<CommandEnv>):Result<CommandOutput, String>;
	public static function statusCodeWithStdin(program:Ref<PathBuf>, args:Ref<Vec<String>>, stdinUtf8:String):Result<Int, String>;
	public static function outputUtf8WithStdin(program:Ref<PathBuf>, args:Ref<Vec<String>>, stdinUtf8:String):Result<CommandOutput, String>;
}
