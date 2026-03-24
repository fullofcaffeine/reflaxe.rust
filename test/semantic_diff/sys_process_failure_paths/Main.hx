import StringTools;
import sys.io.Process;

class Main {
	static function main() {
		var isWindows = Sys.systemName() == "Windows";
		var shell = isWindows ? "cmd" : "sh";
		var scriptArgs = isWindows ? ["/C", "echo out & echo err 1>&2 & exit /B 7"] : ["-c", "printf out; printf err 1>&2; exit 7"];

		var proc = new Process(shell, scriptArgs);
		var out = StringTools.trim(proc.stdout.readAll().toString());
		var err = StringTools.trim(proc.stderr.readAll().toString());
		var code = proc.exitCode(true);
		proc.close();

		Sys.println('out=' + out);
		Sys.println('err=' + err);
		Sys.println('code=' + code);

		var sleepArgs = isWindows ? ["/C", "ping -n 6 127.0.0.1 >NUL"] : ["-c", "sleep 5"];
		var sleeper = new Process(shell, sleepArgs);
		var killedHandled = false;
		try {
			sleeper.kill();
			var killed = sleeper.exitCode(true);
			killedHandled = killed != 0;
		} catch (_:Dynamic) {
			killedHandled = true;
		}
		sleeper.close();
		Sys.println('killed_handled=' + killedHandled);
	}
}
