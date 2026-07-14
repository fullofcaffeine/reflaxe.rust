/**
 * Rust-target implementation of portable core `Sys` APIs.
 *
 * Why:
 * - Haxe applications expect path, process, and standard-stream failures to cross `try/catch`;
 *   ordinary Rust panics are not compatible with that contract.
 *
 * What:
 * - Exposes the admitted portable environment, process, time, path, and std-stream operations.
 * - Keeps explicitly unimplemented operations, currently `cpuTime`, outside stable admission.
 *
 * How:
 * - Delegates runtime-dependent operations to the typed `hxrt.sys.NativeSys` boundary.
 * - That boundary converts normal Rust `Result` failures into Haxe-visible values and reserves
 *   typed `haxe.io.Error` payloads for standard streams.
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
	 * - Upstream Haxe contract for `Sys.getEnv` is nullable (`Null<String>`): missing keys must
	 *   round-trip as `null`, not empty strings.
	 *
	 * What:
	 * - Returns the variable value when present, otherwise `null`.
	 * - Invalid names throw a catchable Haxe `String` instead of reaching a Rust panic boundary.
	 *
	 * How:
	 * - Delegates to typed runtime binding `hxrt::sys::get_env`, which returns `Option<String>`
	 *   at the native boundary and maps back to Haxe nullability.
	 */
	public static function getEnv(s:String):Null<String> {
		return NativeSys.getEnv(s);
	}

	/**
	 * Set or remove an environment variable.
	 *
	 * Why:
	 * - Rust's environment mutation API panics on malformed names/values even though these strings
	 *   are ordinary application input at the Haxe boundary.
	 *
	 * What:
	 * - Invalid names or NUL-containing values throw a catchable Haxe `String`.
	 * - This operation remains experimental for the stable contract. On non-Windows hosts it is
	 *   valid only while the process is provably single-threaded and before foreign libraries can
	 *   read the process environment concurrently.
	 *
	 * How:
	 * - `v == null` removes the variable, otherwise sets it.
	 * - The runtime validates the platform-independent invalid forms before calling `std::env`.
	 * - Prefer child-process-specific environment APIs for concurrent production programs.
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

	/**
	 * Change the process working directory.
	 *
	 * Why:
	 * - Missing, inaccessible, and invalid paths are normal recoverable OS failures.
	 *
	 * What:
	 * - Changes cwd on success and throws a catchable Haxe `String` on failure.
	 *
	 * How:
	 * - The runtime converts `std::env::set_current_dir`'s `Result` through the shared portable
	 *   failure boundary; it never exposes a Rust `unwrap()` panic.
	 */
	public static function setCwd(path:String):Void {
		NativeSys.setCwd(path);
	}

	public static function systemName():String {
		return NativeSys.systemName();
	}

	/**
	 * Run a shell command or direct executable and wait for its exit code.
	 *
	 * Why:
	 * - With `args`, Rust launches the executable directly and launch itself can fail before an exit
	 *   code exists. That must remain recoverable Haxe behavior.
	 *
	 * What:
	 * - `args == null` uses the host shell and returns its exit code.
	 * - A non-null `args` array uses direct spawn; spawn errors throw a catchable Haxe `String`.
	 *
	 * How:
	 * - `hxrt::sys::command` maps `std::process::Command::status()` errors through the shared portable
	 *   failure boundary rather than unwrapping them.
	 */
	public static function command(cmd:String, ?args:Array<String>):Int {
		return NativeSys.command(cmd, args);
	}

	public static function exit(code:Int):Void {
		NativeSys.exit(code);
	}

	public static function time():Float {
		return NativeSys.time();
	}

	/**
	 * Return CPU time used by the current process.
	 *
	 * Why:
	 * - Haxe defines this as consumed CPU time, which is observably different from wall-clock time.
	 * - Returning `Sys.time()` made sleeping appear to consume CPU and falsely presented this member
	 *   as implemented.
	 *
	 * What:
	 * - This operation remains explicitly experimental and currently throws a catchable error.
	 *
	 * How:
	 * - The compatibility manifest excludes this member from the qualified stable `Sys` contract.
	 * - A future implementation must use a validated per-process CPU clock on every admitted platform
	 *   before the operation can be promoted.
	 */
	public static function cpuTime():Float {
		throw "Sys.cpuTime is experimental on reflaxe.rust: process CPU time is not implemented";
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
