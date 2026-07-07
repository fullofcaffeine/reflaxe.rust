import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandEnv;
import rust.process.CommandOutput;
import rust.process.NativeCommands;

class Main {
	static function main() {
		var rustc = PathBufTools.fromString("rustc");
		var compileArgs = new Vec<String>();
		compileArgs.push("../env_probe.rs");
		compileArgs.push("-o");
		compileArgs.push("./env_probe_bin");

		switch (NativeCommands.statusCode(rustc, compileArgs)) {
			case Ok(code):
				failIfNonZero(code);
			case Err(_):
				failIfNonZero(1);
		}

		var program = PathBufTools.fromString("./env_probe_bin");
		var args = new Vec<String>();
		var env = new CommandEnv();
		env.set("M47_NATIVE_COMMAND_ENV", "native-env-ok");

		switch (NativeCommands.outputUtf8WithEnv(program, args, env)) {
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
				failIfMismatch(stdout, "native-env-ok");
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
