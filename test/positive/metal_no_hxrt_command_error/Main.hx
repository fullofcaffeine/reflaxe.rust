import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandError;
import rust.process.CommandOutput;
import rust.process.CommandSpec;
import rust.process.NativeCommands;

class Main {
	static function main() {
		inspectMissingCommandError();
		buildInvalidUtf8Probe();
		inspectUtf8Error();
	}

	static function inspectMissingCommandError() {
		var missing = PathBufTools.fromString("m53-command-error-missing-executable");
		var args = emptyArgs();
		var spec = new CommandSpec(missing, args);

		switch (NativeCommands.statusCodeDetailedFromSpec(spec)) {
			case Ok(_):
				fail();
			case Err(error):
				inspectIoError(error);
		}
	}

	static function buildInvalidUtf8Probe() {
		var rustc = PathBufTools.fromString("rustc");
		var cwd = PathBufTools.fromString("..");
		var args = new Vec<String>();
		args.push("-o");
		args.push("m53_cwd_dir/m53_invalid_utf8_probe");
		args.push("-");

		var spec = new CommandSpec(rustc, args);
		spec.inDir(cwd);
		spec.withStdin(invalidUtf8ProbeSource());

		switch (NativeCommands.statusCodeFromSpec(spec)) {
			case Ok(code):
				failIfNonZero(code);
			case Err(_):
				fail();
		}
	}

	static function inspectUtf8Error() {
		var probe = PathBufTools.fromString("../m53_cwd_dir/m53_invalid_utf8_probe");
		var args = emptyArgs();
		var spec = new CommandSpec(probe, args);

		switch (NativeCommands.outputUtf8DetailedFromSpec(spec)) {
			case Ok(output):
				inspectInvalidOutput(output);
			case Err(_):
				fail();
		}
	}

	static function inspectInvalidOutput(output:CommandOutput) {
		failIfNonZero(output.statusCode());

		switch (output.stdoutUtf8Detailed()) {
			case Ok(_):
				fail();
			case Err(error):
				inspectUtf8DecodeError(error);
		}

		switch (output.stderrUtf8Detailed()) {
			case Ok(stderr):
				failIfMismatch(stderr, "");
			case Err(_):
				fail();
		}
	}

	static function inspectIoError(error:CommandError) {
		if (!error.isIo() || error.isUtf8() || error.isStdin()) {
			fail();
		}
		if (error.message() == "") {
			fail();
		}
	}

	static function inspectUtf8DecodeError(error:CommandError) {
		if (!error.isUtf8() || error.isIo() || error.isStdin()) {
			fail();
		}
		if (error.message() == "") {
			fail();
		}
	}

	static function invalidUtf8ProbeSource():String {
		return "use std::io::Write;\n"
			+ "fn main() {\n"
			+ "    std::io::stdout().write_all(&[0xff, 0xfe]).unwrap();\n"
			+ "}\n";
	}

	static function emptyArgs():Vec<String> {
		return new Vec<String>();
	}

	static function failIfMismatch(actual:String, expected:String) {
		if (actual != expected) {
			fail();
		}
	}

	static function failIfNonZero(code:Int) {
		if (code != 0) {
			trap(code);
		}
	}

	static function fail() {
		trap(1);
	}

	static function trap(code:Int) {
		var zero = code - code;
		var trap = 1 % zero;
		if (trap == -1) {
			return;
		}
	}
}
