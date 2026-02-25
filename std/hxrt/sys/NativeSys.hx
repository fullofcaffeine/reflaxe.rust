package hxrt.sys;

import SysTypes.SysPrintValue;

/**
	`hxrt.sys.NativeSys` (Rust runtime binding)

	Why
	- `Sys`/`sys.io.Std*` previously relied on many inline `untyped __rust__` calls.
	- Those calls inflate metal fallback diagnostics and scatter native-boundary logic across std code.

	What
	- Typed extern binding to `hxrt::sys` helpers for process/env/time/std stream operations.

	How
	- `@:native("hxrt::sys")` maps this class to the runtime module.
	- Each function has a concrete Haxe signature so callers remain fully typed after crossing
	  the unavoidable runtime boundary.
**/
@:native("hxrt::sys")
extern class NativeSys {
	@:native("print")
	public static function print(v:SysPrintValue):Void;

	@:native("println")
	public static function println(v:SysPrintValue):Void;

	@:native("args")
	public static function args():Array<String>;

	@:native("get_env")
	public static function getEnv(s:String):String;

	@:native("put_env")
	public static function putEnv(s:String, v:Null<String>):Void;

	/**
		Return environment key/value pairs as a fully typed nested array.

		Why
		- `std/Sys.cross.hx::environment()` must avoid inline `untyped __rust__` in first-party std code.
		- Returning typed pairs keeps the dynamic/native boundary centralized in `hxrt::sys`.

		How
		- Binds to `hxrt::sys::environment_pairs`.
		- Each inner array has exactly two entries: `[key, value]`.
	**/
	@:native("environment_pairs")
	public static function environmentPairs():Array<Array<String>>;

	@:native("sleep")
	public static function sleep(seconds:Float):Void;

	@:native("get_cwd")
	public static function getCwd():String;

	@:native("set_cwd")
	public static function setCwd(path:String):Void;

	@:native("system_name")
	public static function systemName():String;

	@:native("command")
	public static function command(cmd:String, args:Null<Array<String>>):Int;

	@:native("exit")
	public static function exit(code:Int):Void;

	@:native("time")
	public static function time():Float;

	@:native("program_path")
	public static function programPath():String;

	@:native("stdin_read_byte")
	public static function stdinReadByte():Int;

	@:native("stdin_read_bytes")
	public static function stdinReadBytes(s:haxe.io.Bytes, pos:Int, len:Int):Int;

	@:native("stdout_write_byte")
	public static function stdoutWriteByte(value:Int):Void;

	@:native("stdout_write_bytes")
	public static function stdoutWriteBytes(s:haxe.io.Bytes, pos:Int, len:Int):Int;

	@:native("stdout_flush")
	public static function stdoutFlush():Void;

	@:native("stderr_write_byte")
	public static function stderrWriteByte(value:Int):Void;

	@:native("stderr_write_bytes")
	public static function stderrWriteBytes(s:haxe.io.Bytes, pos:Int, len:Int):Int;

	@:native("stderr_flush")
	public static function stderrFlush():Void;
}
