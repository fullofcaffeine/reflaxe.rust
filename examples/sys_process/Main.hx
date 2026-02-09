import sys.io.Process;

class Main {
	static function main() {
		// Start a process and verify we can communicate.
		var cmd: String;
		var args: Array<String>;

		if (Sys.systemName() == "Windows") {
			cmd = "cmd";
			args = ["/C", "more"];
		} else {
			cmd = "sh";
			args = ["-c", "cat"];
		}

		var p = new Process(cmd, args);
		p.stdin.writeString("hello");
		p.stdin.close();

		var out = p.stdout.readAll().toString();
		if (out != "hello") throw "stdout mismatch: '" + out + "'";

		var code = p.exitCode(true);
		if (code == null || code != 0) throw "exitCode mismatch: " + code;

		p.close();

		// Non-blocking exitCode should return null while running.
		var p2 = new Process(cmd, args);
		var early = p2.exitCode(false);
		// It's possible (but unlikely) the process already exited; accept both.
		if (early != null && early != 0) throw "unexpected early exitCode: " + early;
		p2.kill();
		p2.close();

		Sys.println("ok");
	}
}
