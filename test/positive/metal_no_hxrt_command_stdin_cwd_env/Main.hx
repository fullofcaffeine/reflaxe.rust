import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandEnv;
import rust.process.CommandOutput;
import rust.process.NativeCommands;

class Main {
	static function main() {
		var rustc = PathBufTools.fromString("rustc");
		var cwd = PathBufTools.fromString("..");
		var env = commandEnv();
		var statusStdin = statusRustSource();

		var statusArgs = statusRustcArgs();
		statusArgs.push("-o");
		statusArgs.push("m51_cwd_dir/m51_status_probe.rlib");
		statusArgs.push("-");

		switch (NativeCommands.statusCodeInDirWithEnvAndStdin(rustc, statusArgs, cwd, env, statusStdin)) {
			case Ok(code):
				failIfNonZero(code);
			case Err(_):
				failIfNonZero(1);
		}

		var outputStdin = outputRustSource();
		var outputArgs = outputRustcArgs();
		outputArgs.push("--print=file-names");
		outputArgs.push("-");

		switch (NativeCommands.outputUtf8InDirWithEnvAndStdin(rustc, outputArgs, cwd, env, outputStdin)) {
			case Ok(output):
				inspect(output);
			case Err(_):
				failIfNonZero(1);
		}
	}

	static function commandEnv():CommandEnv {
		var env = new CommandEnv();
		env.set("M51_REMOVE", "should-not-leak");
		env.remove("M51_REMOVE");
		env.set("M51_KEEP", "stdin-cwd-env-ok");
		return env;
	}

	static function statusRustcArgs():Vec<String> {
		var args = new Vec<String>();
		args.push("--crate-type=lib");
		args.push("--crate-name");
		args.push("m51_stdin_cwd_env_probe");
		return args;
	}

	static function outputRustcArgs():Vec<String> {
		var args = new Vec<String>();
		args.push("--crate-type=lib");
		args.push("--crate-name");
		args.push("m51_stdin_cwd_env_probe_user");
		args.push("--extern");
		args.push("m51_stdin_cwd_env_probe=m51_cwd_dir/m51_status_probe.rlib");
		return args;
	}

	static function statusRustSource():String {
		return "const KEEP: &str = env!(\"M51_KEEP\");\n"
			+ "const _: () = match option_env!(\"M51_REMOVE\") { None => (), Some(_) => panic!(\"remove leaked\"), };\n"
			+ "pub fn marker() -> &'static str { KEEP }\n";
	}

	static function outputRustSource():String {
		return "extern crate m51_stdin_cwd_env_probe;\n"
			+ "const KEEP: &str = env!(\"M51_KEEP\");\n"
			+ "const _: () = match option_env!(\"M51_REMOVE\") { None => (), Some(_) => panic!(\"remove leaked\"), };\n"
			+ "pub fn marker() -> &'static str { KEEP }\n";
	}

	static function inspect(output:CommandOutput) {
		failIfNonZero(output.statusCode());

		switch (output.stdoutUtf8()) {
			case Ok(stdout):
				failIfMismatch(stdout, "libm51_stdin_cwd_env_probe_user.rlib\n");
			case Err(_):
				failIfNonZero(1);
		}

		switch (output.stderrUtf8()) {
			case Ok(stderr):
				failIfMismatch(stderr, "");
			case Err(_):
				failIfNonZero(1);
		}
	}

	static function failIfMismatch(actual:String, expected:String) {
		if (actual != expected) {
			failIfNonZero(1);
		}
	}

	static function failIfNonZero(code:Int) {
		if (code != 0) {
			var zero = code - code;
			var trap = 1 % zero;
			if (trap == -1) {
				return;
			}
		}
	}
}
