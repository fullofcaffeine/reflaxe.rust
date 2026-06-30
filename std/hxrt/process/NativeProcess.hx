package hxrt.process;

import haxe.io.Bytes;
import rust.HxRef;
import rust.Ref;

/**
	Typed native boundary for `sys.io.Process`.

	Why
	- `sys.io.Process` is a low-level stdlib surface used by production consumers for subprocess
	  ownership, stdio pipes, and exit status.
	- Metal consumers must be able to use this surface without `ERaw` fallback nodes from inline
	  `untyped __rust__` snippets in the std override.

	What
	- Exposes process spawn/lifecycle and pipe IO as typed Haxe functions.
	- Keeps `ProcessHandle` opaque while giving callers concrete `String`, `Bool`, `Int`,
	  `Null<Int>`, `Bytes`, and `HxRef<ProcessHandle>` values.
	- Carries an explicit `argsProvided` flag because the current generated Rust shape lowers
	  optional `Array<String>` constructor arguments to a concrete array; the flag preserves the
	  stdlib distinction between omitted args (shell fallback) and an explicitly empty argument list.

	How
	- Binds to the `hxrt::process` runtime module.
	- The Rust runtime owns the OS process and pipe handles; Haxe code passes an `HxRef` handle and
	  returns immediately to typed stdlib code.
**/
@:native("hxrt::process")
extern class NativeProcess {
	@:native("spawn_haxe")
	public static function spawn(cmd:String, args:Array<String>, detached:Null<Bool>, argsProvided:Bool):HxRef<ProcessHandle>;

	public static function pid(handle:Ref<HxRef<ProcessHandle>>):Int;

	@:native("wait_exit_code")
	public static function waitExitCode(handle:Ref<HxRef<ProcessHandle>>):Int;

	@:native("try_wait_exit_code")
	public static function tryWaitExitCode(handle:Ref<HxRef<ProcessHandle>>):Null<Int>;

	@:native("close")
	public static function closeHandle(handle:Ref<HxRef<ProcessHandle>>):Void;

	public static function kill(handle:Ref<HxRef<ProcessHandle>>):Void;

	@:native("write_stdin")
	public static function writeStdin(handle:Ref<HxRef<ProcessHandle>>, bytes:Bytes, pos:Int, len:Int):Int;

	@:native("flush_stdin")
	public static function flushStdin(handle:Ref<HxRef<ProcessHandle>>):Void;

	@:native("close_stdin")
	public static function closeStdin(handle:Ref<HxRef<ProcessHandle>>):Void;

	@:native("read_stdout")
	public static function readStdout(handle:Ref<HxRef<ProcessHandle>>, bytes:Bytes, pos:Int, len:Int):Int;

	@:native("read_stderr")
	public static function readStderr(handle:Ref<HxRef<ProcessHandle>>, bytes:Bytes, pos:Int, len:Int):Int;
}
