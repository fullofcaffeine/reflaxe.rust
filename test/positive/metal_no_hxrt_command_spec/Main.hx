import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandEnv;
import rust.process.CommandOutput;
import rust.process.CommandSpec;
import rust.process.NativeCommands;

class Main {
	static function main() {
		var rustc = PathBufTools.fromString("rustc");
		var cwd = PathBufTools.fromString("..");
		var env = commandEnv();

		var statusArgs = statusRustcArgs();
		var statusSpec = new CommandSpec(rustc, statusArgs);
		statusSpec.inDir(cwd);
		statusSpec.withEnv(env);
		statusSpec.withStdin(statusRustSource());

		switch (NativeCommands.statusCodeFromSpec(statusSpec)) {
			case Ok(code):
				failIfNonZero(code);
			case Err(_):
				failIfNonZero(1);
		}

		var outputArgs = outputRustcArgs();
		var outputSpec = new CommandSpec(rustc, outputArgs);
		outputSpec.inDir(cwd);
		outputSpec.withEnv(env);
		outputSpec.withStdin(outputRustSource());

		switch (NativeCommands.outputUtf8FromSpec(outputSpec)) {
			case Ok(output):
				inspect(output);
			case Err(_):
				failIfNonZero(1);
		}
	}

	static function commandEnv():CommandEnv {
		var env = new CommandEnv();
		env.set("M52_REMOVE", "should-not-leak");
		env.remove("M52_REMOVE");
		env.set("M52_KEEP", "command-spec-ok");
		return env;
	}

	static function statusRustcArgs():Vec<String> {
		var args = new Vec<String>();
		args.push("--crate-type=lib");
		args.push("--crate-name");
		args.push("m52_command_spec_probe");
		args.push("-o");
		args.push("m52_cwd_dir/m52_status_probe.rlib");
		args.push("-");
		return args;
	}

	static function outputRustcArgs():Vec<String> {
		var args = new Vec<String>();
		args.push("--crate-type=lib");
		args.push("--crate-name");
		args.push("m52_command_spec_probe_user");
		args.push("--extern");
		args.push("m52_command_spec_probe=m52_cwd_dir/m52_status_probe.rlib");
		args.push("--print=file-names");
		args.push("-");
		return args;
	}

	static function statusRustSource():String {
		return "const KEEP: &str = env!(\"M52_KEEP\");\n"
			+ "const _: () = match option_env!(\"M52_REMOVE\") { None => (), Some(_) => panic!(\"remove leaked\"), };\n"
			+ "pub fn marker() -> &'static str { KEEP }\n";
	}

	static function outputRustSource():String {
		return "extern crate m52_command_spec_probe;\n"
			+ "const KEEP: &str = env!(\"M52_KEEP\");\n"
			+ "const _: () = match option_env!(\"M52_REMOVE\") { None => (), Some(_) => panic!(\"remove leaked\"), };\n"
			+ "pub fn marker() -> &'static str { KEEP }\n";
	}

	static function inspect(output:CommandOutput) {
		failIfNonZero(output.statusCode());

		switch (output.stdoutUtf8()) {
			case Ok(stdout):
				failIfMismatch(stdout, "libm52_command_spec_probe_user.rlib\n");
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
