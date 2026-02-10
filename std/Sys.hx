/**
 * Rust target implementation of core `Sys` APIs.
 *
 * Intentionally minimal for now (Milestone 8 acceptance coverage).
 */
class Sys {
	public static function print(v: Dynamic): Void {
		untyped __rust__("{ print!(\"{}\", {0}); }", v);
	}

	public static function println(v: Dynamic): Void {
		untyped __rust__("{ println!(\"{}\", {0}); }", v);
	}

	public static function args(): Array<String> {
		return untyped __rust__("hxrt::array::Array::<String>::from_vec(std::env::args().skip(1).collect::<Vec<String>>())");
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
	public static function getEnv(s: String): String {
		return untyped __rust__(
			"std::env::var({0}.as_str()).ok().unwrap_or_else(|| String::new())",
			s
		);
	}

	/**
	 * Set or remove an environment variable.
	 *
	 * How:
	 * - `v == null` removes the variable, otherwise sets it.
	 */
	public static function putEnv(s: String, v: Null<String>): Void {
		if (v == null) {
			untyped __rust__("{ std::env::remove_var({0}.as_str()); }", s);
		} else {
			// `v` is typed as `Null<String>` which lowers to `Option<String>` in Rust.
			// We already checked for `null` above, so unwrap here in Rust to get the inner `String`.
			untyped __rust__("{ std::env::set_var({0}.as_str(), {1}.as_ref().unwrap().as_str()); }", s, v);
		}
	}

	/**
	 * Return the current environment as a map.
	 *
	 * What:
	 * - Returns a `Map<String, String>` with the environment variables at call time.
	 *
	 * How:
	 * - Uses `std::env::vars` and builds a `haxe.ds.StringMap`.
	 */
	public static function environment(): Map<String, String> {
		return untyped __rust__(
			"{
				let m = crate::haxe_ds_string_map::StringMap::<String>::new();
				for (k, v) in std::env::vars() {
					crate::haxe_ds_string_map::StringMap::set(&m, k, v);
				}
				m
			}"
		);
	}

	/** Suspend execution for the given duration in seconds. */
	public static function sleep(seconds: Float): Void {
		untyped __rust__(
			"{ std::thread::sleep(std::time::Duration::from_millis(({0} * 1000.0) as u64)); }",
			seconds
		);
	}

	/** Not implemented yet for the Rust target (returns `false`). */
	public static function setTimeLocale(loc: String): Bool {
		var _ = loc;
		return false;
	}

	public static function getCwd(): String {
		return untyped __rust__("std::env::current_dir().unwrap().to_string_lossy().to_string()");
	}

	public static function setCwd(path: String): Void {
		untyped __rust__("{ std::env::set_current_dir({0}.as_str()).unwrap(); }", path);
	}

	public static function systemName(): String {
		return untyped __rust__(
			"match std::env::consts::OS {
				\"windows\" => String::from(\"Windows\"),
				\"linux\" => String::from(\"Linux\"),
				\"macos\" => String::from(\"Mac\"),
				\"freebsd\" => String::from(\"BSD\"),
				\"netbsd\" => String::from(\"BSD\"),
				\"openbsd\" => String::from(\"BSD\"),
				_ => String::from(std::env::consts::OS),
			}"
		);
	}

	public static function command(cmd: String, ?args: Array<String>): Int {
		if (args == null) {
			// Best-effort: run through `sh -c` so shell builtins work (matches Haxe docs).
			return untyped __rust__(
				"std::process::Command::new(\"sh\").arg(\"-c\").arg({0}.as_str()).status().unwrap().code().unwrap_or(1) as i32",
				cmd
			);
		}
		return untyped __rust__(
			"{
				let mut c = std::process::Command::new({0}.as_str());
				let args_ = {1};
				let mut i: i32 = 0;
				while i < args_.len() as i32 {
					let a = args_.get_unchecked(i as usize);
					c.arg(a);
					i = i + 1;
				}
				c.status().unwrap().code().unwrap_or(1) as i32
			}",
			cmd,
			args
		);
	}

	public static function exit(code: Int): Void {
		untyped __rust__("std::process::exit({0})", code);
	}

	public static function time(): Float {
		return untyped __rust__(
			"{
				use std::time::{SystemTime, UNIX_EPOCH};
				let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
				(now.as_secs_f64()) as f64
			}"
		);
	}

	/** POC: use wall-clock time for now (not CPU time). */
	public static function cpuTime(): Float {
		return time();
	}

	public static function executablePath(): String {
		return programPath();
	}

	public static function programPath(): String {
		return untyped __rust__(
			"std::env::current_exe().unwrap().to_string_lossy().to_string()"
		);
	}

	public static function getChar(echo: Bool): Int {
		var c = stdin().readByte();
		if (echo) stdout().writeByte(c);
		return c;
	}

	public static function stdin(): haxe.io.Input {
		return new sys.io.Stdin();
	}

	public static function stdout(): haxe.io.Output {
		return new sys.io.Stdout();
	}

	public static function stderr(): haxe.io.Output {
		return new sys.io.Stderr();
	}
}
