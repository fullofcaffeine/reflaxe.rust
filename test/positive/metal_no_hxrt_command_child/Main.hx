import rust.PathBufTools;
import rust.Result;
import rust.Vec;
import rust.process.CommandChild;
import rust.process.CommandError;
import rust.process.CommandSpec;
import rust.process.NativeCommands;

class Main {
	static function main() {
		buildLiveChildProbe();
		inspectLifecycleBoundary();
		inspectWriteCloseAndWait();
		inspectKillAndWait();
	}

	static function buildLiveChildProbe() {
		var rustc = PathBufTools.fromString("rustc");
		var cwd = PathBufTools.fromString("..");
		var args = new Vec<String>();
		args.push("-o");
		args.push("m54_cwd_dir/m54_live_child_probe");
		args.push("-");

		var spec = new CommandSpec(rustc, args);
		spec.inDir(cwd);
		spec.withStdin(liveChildProbeSource());

		switch (NativeCommands.statusCodeFromSpec(spec)) {
			case Ok(code):
				failIfNonZero(code);
			case Err(_):
				fail();
		}
	}

	static function inspectLifecycleBoundary() {
		var probe = PathBufTools.fromString("../m54_cwd_dir/m54_live_child_probe");
		var args = emptyArgs();
		var spec = new CommandSpec(probe, args);
		spec.withStdin("owned stdin belongs to status/output helpers\n");

		switch (NativeCommands.spawnChildFromSpec(spec)) {
			case Ok(_):
				fail();
			case Err(error):
				if (!error.isLifecycle() || error.isIo() || error.isUtf8() || error.isStdin()) {
					fail();
				}
				if (error.message() == "") {
					fail();
				}
		}
	}

	static function inspectWriteCloseAndWait() {
		var probe = PathBufTools.fromString("../m54_cwd_dir/m54_live_child_probe");
		var args = emptyArgs();
		var spec = new CommandSpec(probe, args);

		switch (NativeCommands.spawnChildFromSpec(spec)) {
			case Ok(child):
				writeThenWait(child);
			case Err(error):
				inspectNoLifecycleError(error);
		}
	}

	static function writeThenWait(child:CommandChild) {
		switch (child.writeStdinAndClose("m54-live-child\n")) {
			case Ok(wrote):
				if (!wrote) {
					fail();
				}
			case Err(error):
				inspectNoLifecycleError(error);
		}

		switch (child.wait()) {
			case Ok(code):
				failIfNonZero(code);
			case Err(error):
				inspectNoLifecycleError(error);
		}
	}

	static function inspectKillAndWait() {
		var probe = PathBufTools.fromString("../m54_cwd_dir/m54_live_child_probe");
		var args = emptyArgs();
		var spec = new CommandSpec(probe, args);

		switch (NativeCommands.spawnChildFromSpec(spec)) {
			case Ok(child):
				killThenWait(child);
			case Err(error):
				inspectNoLifecycleError(error);
		}
	}

	static function killThenWait(child:CommandChild) {
		switch (child.killAndWait()) {
			case Ok(code):
				if (code == 0) {
					fail();
				}
			case Err(error):
				inspectNoLifecycleError(error);
		}
	}

	static function inspectNoLifecycleError(error:CommandError) {
		if (error.isIo() || error.isUtf8() || error.isStdin() || error.isLifecycle()) {
			fail();
		}
		if (error.message() == "") {
			fail();
		}
	}

	static function liveChildProbeSource():String {
		return "use std::io::{self, Read};\n"
			+ "fn main() {\n"
			+ "    let mut input = String::new();\n"
			+ "    if io::stdin().read_to_string(&mut input).is_err() {\n"
			+ "        std::process::exit(5);\n"
			+ "    }\n"
			+ "    if input == \"m54-live-child\\n\" {\n"
			+ "        std::process::exit(0);\n"
			+ "    }\n"
			+ "    std::process::exit(9);\n"
			+ "}\n";
	}

	static function emptyArgs():Vec<String> {
		return new Vec<String>();
	}

	static function failIfNonZero(code:Int) {
		if (code != 0) {
			fail();
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
