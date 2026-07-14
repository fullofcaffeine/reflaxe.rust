import haxe.io.Eof;
import haxe.io.Error;

class Main {
	static function catchIo(operation:Void->Void):String {
		try {
			operation();
			return "not_caught";
		} catch (_:Error) {
			return "io_error";
		} catch (_:Dynamic) {
			return "wrong_error";
		}
	}

	static function printOutcome(out:haxe.io.Output, label:String, outcome:String):Void {
		out.writeString(label + "=" + outcome + "\n");
		out.writeString(label + "_continued=true\n");
		out.flush();
	}

	static function brokenStdout():Void {
		var outcome = catchIo(() -> {
			Sys.stdout().writeString("this write must observe the closed pipe");
			Sys.stdout().flush();
		});
		printOutcome(Sys.stderr(), "broken_stdout", outcome);
	}

	static function brokenSysPrint():Void {
		var outcome = catchIo(() -> {
			Sys.print("this print must observe the closed pipe");
			Sys.stdout().flush();
		});
		printOutcome(Sys.stderr(), "broken_sys_print", outcome);
	}

	static function brokenStderr():Void {
		var outcome = catchIo(() -> {
			Sys.stderr().writeString("this write must observe the closed pipe");
			Sys.stderr().flush();
		});
		printOutcome(Sys.stdout(), "broken_stderr", outcome);
	}

	static function stdinRead(label:String):Void {
		var outcome = "byte";
		try {
			Sys.stdin().readByte();
		} catch (_:Eof) {
			outcome = "eof";
		} catch (_:Error) {
			outcome = "io_error";
		} catch (_:Dynamic) {
			outcome = "wrong_error";
		}
		printOutcome(Sys.stdout(), label, outcome);
	}

	static function cpuTimeDisposition():Void {
		var outcome = "stable_value";
		try {
			Sys.cpuTime();
		} catch (_:Dynamic) {
			outcome = "experimental";
		}
		printOutcome(Sys.stdout(), "cpu_time", outcome);
	}

	static function missingDirectCommand():Void {
		var outcome = "not_caught";
		try {
			Sys.command("__reflaxe_rust_missing_direct_command__", []);
		} catch (_:String) {
			outcome = "caught";
		} catch (_:Dynamic) {
			outcome = "wrong_error";
		}
		printOutcome(Sys.stdout(), "missing_direct_command", outcome);
	}

	static function invalidEnvironmentName():Void {
		var invalidName = "REFLAXE" + String.fromCharCode(0) + "RUST";
		var getOutcome = "not_caught";
		try {
			Sys.getEnv(invalidName);
		} catch (_:String) {
			getOutcome = "caught";
		} catch (_:Dynamic) {
			getOutcome = "wrong_error";
		}
		printOutcome(Sys.stdout(), "invalid_get_env", getOutcome);

		var putOutcome = "not_caught";
		try {
			Sys.putEnv(invalidName, "value");
		} catch (_:String) {
			putOutcome = "caught";
		} catch (_:Dynamic) {
			putOutcome = "wrong_error";
		}
		printOutcome(Sys.stdout(), "invalid_put_env", putOutcome);

		var valueOutcome = "not_caught";
		try {
			Sys.putEnv("REFLAXE_RUST_INVALID_ENV_VALUE", "value" + String.fromCharCode(0));
		} catch (_:String) {
			valueOutcome = "caught";
		} catch (_:Dynamic) {
			valueOutcome = "wrong_error";
		}
		printOutcome(Sys.stdout(), "invalid_put_env_value", valueOutcome);
	}

	static function main():Void {
		var mode = Sys.args()[0];
		switch (mode) {
			case "broken-stdout": brokenStdout();
			case "broken-sys-print": brokenSysPrint();
			case "broken-stderr": brokenStderr();
			case "stdin-error": stdinRead("stdin_error");
			case "stdin-eof": stdinRead("stdin_eof");
			case "cpu-time": cpuTimeDisposition();
			case "missing-command": missingDirectCommand();
			case "invalid-env": invalidEnvironmentName();
			case _: throw "unknown portable Sys failure-contract mode: " + mode;
		}
	}
}
