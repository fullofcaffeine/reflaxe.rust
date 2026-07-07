import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandEnv;
import rust.process.CommandOutput;
import rust.process.NativeCommands;

class Main {
	static function main() {
		var program = PathBufTools.fromString("rustc");
		var cwd = PathBufTools.fromString("..");
		var args = new Vec<String>();
		args.push("--crate-type=lib");
		args.push("--print=file-names");
		args.push("cwd_env_probe.rs");

		var env = new CommandEnv();
		env.set("M49_REMOVE", "should-not-leak");
		env.remove("M49_REMOVE");
		env.set("M49_KEEP", "cwd-env-ok");

		switch (NativeCommands.statusCodeInDirWithEnv(program, args, cwd, env)) {
			case Ok(code):
				failIfNonZero(code);
			case Err(_):
				failIfNonZero(1);
		}

		switch (NativeCommands.outputUtf8InDirWithEnv(program, args, cwd, env)) {
			case Ok(output):
				inspect(output);
			case Err(_):
				failIfNonZero(1);
		}
	}

	static function inspect(output:CommandOutput) {
		failIfNonZero(output.statusCode());

		switch (output.stdoutUtf8()) {
			case Ok(stdout):
				if (stdout == "") {
					failIfNonZero(1);
				}
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
