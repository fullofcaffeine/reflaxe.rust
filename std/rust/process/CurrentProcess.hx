package rust.process;

import rust.Result;
import rust.Vec;

/**
 * Runtime-free access to the current process's narrow protocol boundary.
 *
 * Why
 *
 * A Rust-native compiler helper or language server often communicates through
 * binary stdin and stdout. Portable `Sys` and `haxe.io` preserve the complete
 * Haxe stream contract and therefore correctly use `hxrt`. Metal applications
 * need a smaller option when they explicitly choose Rust-native ownership.
 *
 * What
 *
 * This facade can count process arguments, read one bounded stdin chunk, write
 * one bounded byte vector to stdout, write one bounded UTF-8 diagnostic to
 * stderr, and terminate with an explicit status. It does not expose files,
 * environment mutation, shell execution, reusable stream handles, or raw OS
 * errors.
 *
 * How
 *
 * The facade binds to a small safe-Rust module that owns each temporary
 * standard-stream lock. Byte vectors use `rust.Vec<Int>` and every value is
 * checked before conversion to `u8`. Reads and writes are limited to 1 MiB per
 * call. An empty successful read means EOF. All other normal failures return a
 * closed `CurrentProcessError` value.
 */
@:native("crate::current_process_tools::CurrentProcess")
@:rustExtraSrc("rust/native/current_process_tools.rs")
extern class CurrentProcess {
	/** Return the user argument count, without the executable name. */
	@:native("user_argument_count")
	public static function userArgumentCount():Result<Int, CurrentProcessError>;

	/** Read at most `maxBytes`. An empty successful vector means EOF. */
	@:native("read_stdin_chunk")
	public static function readStdinChunk(maxBytes:Int):Result<Vec<Int>, CurrentProcessError>;

	/** Validate and write all bytes, then flush stdout. */
	@:native("write_stdout")
	public static function writeStdout(bytes:Vec<Int>):Result<Void, CurrentProcessError>;

	/** Write and flush one bounded UTF-8 diagnostic. */
	@:native("write_stderr_utf8")
	public static function writeStderrUtf8(message:String):Result<Void, CurrentProcessError>;

	/** Terminate immediately with the requested process status. */
	@:native("exit")
	public static function exit(code:Int):Void;
}
