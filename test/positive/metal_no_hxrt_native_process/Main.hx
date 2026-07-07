import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.NativeCommands;

class Main {
	static function main() {
		var program = PathBufTools.fromString("rustc");
		var args = new Vec<String>();
		args.push("--version");

		switch (NativeCommands.statusCode(program, args)) {
			case Ok(code):
				if (code != 0) {
					return;
				}
			case Err(_):
				return;
		}

		switch (NativeCommands.stdoutUtf8(program, args)) {
			case Ok(stdout):
				if (stdout == "") {
					return;
				}
			case Err(_):
				return;
		}
	}
}
