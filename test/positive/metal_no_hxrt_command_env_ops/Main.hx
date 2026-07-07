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

		var removeArgs = new Vec<String>();
		removeArgs.push("remove");
		var removeEnv = new CommandEnv();
		removeEnv.set("M48_REMOVE_ME", "should-not-leak");
		removeEnv.remove("M48_REMOVE_ME");
		removeEnv.set("M48_KEEP_ME", "kept");
		inspect(PathBufTools.fromString("./env_probe_bin"), removeArgs, removeEnv, "removed=;keep=kept");

		var clearArgs = new Vec<String>();
		clearArgs.push("clear");
		var clearEnv = new CommandEnv();
		clearEnv.set("M48_REMOVE_ME", "should-not-leak");
		clearEnv.clear();
		clearEnv.set("M48_KEEP_ME", "clear-kept");
		inspect(PathBufTools.fromString("./env_probe_bin"), clearArgs, clearEnv, "path=missing;keep=clear-kept");
	}

	static function inspect(program:rust.PathBuf, args:Vec<String>, env:CommandEnv, expected:String) {
		switch (NativeCommands.outputUtf8WithEnv(program, args, env)) {
			case Ok(output):
				inspectOutput(output, expected);
			case Err(_):
				failIfNonZero(1);
		}
	}

	static function inspectOutput(output:CommandOutput, expected:String) {
		failIfNonZero(output.statusCode());

		switch (output.stdoutUtf8()) {
			case Ok(stdout):
				failIfMismatch(stdout, expected);
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
