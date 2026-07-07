import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandOutput;
import rust.process.NativeCommands;

class Main {
	static function main() {
		var program = PathBufTools.fromString("rustc");
		var cwd = PathBufTools.fromString("..");
		var args = new Vec<String>();
		args.push("--crate-type=lib");
		args.push("--print=file-names");
		args.push("cwd_probe.rs");

		switch (NativeCommands.statusCodeInDir(program, args, cwd)) {
			case Ok(code):
				failIfNonZero(code);
			case Err(_):
				return;
		}

		switch (NativeCommands.outputUtf8InDir(program, args, cwd)) {
			case Ok(output):
				inspect(output);
			case Err(_):
				return;
		}
	}

	static function inspect(output:CommandOutput) {
		failIfNonZero(output.statusCode());

		switch (output.stdoutUtf8()) {
			case Ok(stdout):
				if (stdout == "") {
					return;
				}
			case Err(_):
				return;
		}

		switch (output.stderrUtf8()) {
			case Ok(stderr):
				if (stderr != "") {
					return;
				}
			case Err(_):
				return;
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
