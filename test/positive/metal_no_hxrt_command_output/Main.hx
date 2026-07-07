import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandOutput;
import rust.process.NativeCommands;

class Main {
	static function main() {
		var program = PathBufTools.fromString("rustc");
		var args = new Vec<String>();
		args.push("--version");

		switch (NativeCommands.outputUtf8(program, args)) {
			case Ok(output):
				inspect(output);
			case Err(_):
				return;
		}
	}

	static function inspect(output:CommandOutput) {
		if (output.statusCode() != 0) {
			return;
		}

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
}
