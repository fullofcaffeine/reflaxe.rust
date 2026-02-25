/**
 * Rust target implementation of core `Sys` APIs.
 *
 * Intentionally minimal for now (Milestone 8 acceptance coverage).
 */

import SysTypes.SysPrintValue;
import hxrt.sys.NativeSys;

class Sys {
	public static function print(v:SysPrintValue):Void {
		NativeSys.print(v);
	}

	public static function println(v:SysPrintValue):Void {
		NativeSys.println(v);
	}

	public static function args():Array<String> {
		return NativeSys.args();
	}

	/**
	 * Return the value of an environment variable.
	 *
	 * Why:
	 * - Many CLI apps use environment variables for configuration.
	 *
	 * What:
	 * - Returns the variable value when present.
	 *
	 * How:
	 * - Uses Rust `std::env::var`.
	 *
	 * Current limitation:
	 * - Haxe `Sys.getEnv` can return `null` when the variable is missing.
	 *   This backend currently represents Haxe `String` as a non-null Rust `String`,
	 *   so we return `""` (empty string) when the variable is missing.
	 */
	public static function getEnv(s:String):String {
		return NativeSys.getEnv(s);
	}

	/**
	 * Set or remove an environment variable.
	 *
	 * How:
	 * - `v == null` removes the variable, otherwise sets it.
	 */
	public static function putEnv(s:String, v:Null<String>):Void {
		NativeSys.putEnv(s, v);
	}

	/**
	 * Return the current environment as a map.
	 *
	 * What:
	 * - Returns a `Map<String, String>` with the environment variables at call time.
	 *
	 * How:
	 * - Reads typed key/value pairs from `hxrt::sys::environment_pairs` via `NativeSys`.
	 * - Builds the `haxe.ds.StringMap` in typed Haxe code.
	 */
	public static function environment():Map<String, String> {
		var out = new haxe.ds.StringMap<String>();
		for (entry in NativeSys.environmentPairs()) {
			if (entry.length < 2)
				continue;
			out.set(entry[0], entry[1]);
		}
		return out;
	}

	/** Suspend execution for the given duration in seconds. */
	public static function sleep(seconds:Float):Void {
		NativeSys.sleep(seconds);
	}

	/** Not implemented yet for the Rust target (returns `false`). */
	public static function setTimeLocale(loc:String):Bool {
		var _ = loc;
		return false;
	}

	public static function getCwd():String {
		return NativeSys.getCwd();
	}

	public static function setCwd(path:String):Void {
		NativeSys.setCwd(path);
	}

	public static function systemName():String {
		return NativeSys.systemName();
	}

	public static function command(cmd:String, ?args:Array<String>):Int {
		return NativeSys.command(cmd, args);
	}

	public static function exit(code:Int):Void {
		NativeSys.exit(code);
	}

	public static function time():Float {
		return NativeSys.time();
	}

	/** POC: use wall-clock time for now (not CPU time). */
	public static function cpuTime():Float {
		return time();
	}

	public static function executablePath():String {
		return programPath();
	}

	public static function programPath():String {
		return NativeSys.programPath();
	}

	public static function getChar(echo:Bool):Int {
		var c = stdin().readByte();
		if (echo)
			stdout().writeByte(c);
		return c;
	}

	public static function stdin():haxe.io.Input {
		return new sys.io.Stdin();
	}

	public static function stdout():haxe.io.Output {
		return new sys.io.Stdout();
	}

	public static function stderr():haxe.io.Output {
		return new sys.io.Stderr();
	}
}
