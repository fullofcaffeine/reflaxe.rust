package reflaxe.rust;

#if macro
import haxe.Exception;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import sys.FileSystem;
import sys.io.File;
import eval.luv.Buffer;
import eval.luv.File as LuvFile;
import eval.luv.File.FileMode;
import eval.luv.File.FileOpenFlag;
import eval.luv.File.FileSync;
import eval.luv.Handle;
import eval.luv.Loop;
import eval.luv.Pipe;
import eval.luv.Process;
import eval.luv.Result;
import eval.luv.Signal;
import eval.luv.Stream;
import eval.luv.Timer;
import eval.luv.UVError;
import reflaxe.rust.SupportCrateAdmissionHelperLocator.SupportCrateAdmissionHelperLocation;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionClasspathBinding;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionDeclaration;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionProtocolError;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionRequest;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionResponse;
import reflaxe.rust.SupportCrateRequestPlan.SupportCrateRequestPlan;

/** Closed local reasons why the package-owned admission helper did not produce authority. */
enum SupportCrateAdmissionRunFailure {
	HelperInvalid;
	StartFailed;
	TimedOut;
	PipeFailed;
	ExitFailed;
	StderrRejected;
	ProtocolRejected;
}

/** The helper either returns one fully decoded response or no source authority. */
enum SupportCrateAdmissionRunResult {
	Completed(response:SupportCrateAdmissionResponse);
	Failed(reason:SupportCrateAdmissionRunFailure);
}

private final class SupportCrateAdmissionReadState {
	public final bytes = new BytesBuffer();
	public var total = 0;
	public var exceededLimit = false;
	public var failed = false;
	public var closed = false;

	public function new() {}

	public function append(buffer:Buffer, limit:Int):Void {
		var count = buffer.size();
		var previousTotal = total;
		total += count;
		if (previousTotal < limit) {
			var retained = count;
			if (total > limit)
				retained -= total - limit;
			if (retained > 0)
				bytes.addBytes(buffer.toBytes(), 0, retained);
		}
		if (total > limit)
			exceededLimit = true;
	}
}

/**
	Runs the exact package-owned source-admission helper once per compiler request.

	Haxe 4.3 does not permit creating threads inside a macro. The runner therefore
	uses the compiler's eval/libuv event loop. stdin, stdout, stderr, process exit,
	and the deadline remain active together, so a full pipe cannot deadlock Haxe.
	Every buffer is bounded. Any process or protocol uncertainty discards all bytes.
**/
final class SupportCrateAdmissionRunner {
	static inline final MAX_HELPER_BYTES = 4 * 1024 * 1024;
	static inline final MAX_STDERR_BYTES = 64 * 1024;
	static inline final WALL_MILLISECONDS = 15 * 1000;

	public static function run(location:SupportCrateAdmissionHelperLocation, plan:SupportCrateRequestPlan,
		activeClasspaths:Array<String>):SupportCrateAdmissionRunResult {
		if (!validHelper(location))
			return Failed(HelperInvalid);

		var request = requestFor(plan, activeClasspaths);
		var requestBytes:Bytes;
		try {
			requestBytes = SupportCrateAdmissionProtocol.encodeRequest(request);
		} catch (_:SupportCrateAdmissionProtocolError) {
			return Failed(ProtocolRejected);
		}
		var execution = execute(location.executablePath, requestBytes, WALL_MILLISECONDS);
		if (execution.failure != null)
			return Failed(execution.failure);
		try {
			return Completed(SupportCrateAdmissionProtocol.decodeResponse(execution.stdout, request.classpaths().length,
				request.declarations().length));
		} catch (_:SupportCrateAdmissionProtocolError) {
			return Failed(ProtocolRejected);
		}
	}

	static function execute(executablePath:String, requestBytes:Bytes, wallMilliseconds:Int):{
		stdout:Bytes,
		failure:Null<SupportCrateAdmissionRunFailure>
	} {
		var loop = switch Loop.init() {
			case Ok(value): value;
			case Error(_): return failedExecution(StartFailed);
		};
		var stdinPipe = switch Pipe.init(loop) {
			case Ok(value): value;
			case Error(_):
				loop.close();
				return failedExecution(StartFailed);
		};
		var stdoutPipe = switch Pipe.init(loop) {
			case Ok(value): value;
			case Error(_):
				closeHandle(stdinPipe);
				loop.run(DEFAULT);
				loop.close();
				return failedExecution(StartFailed);
		};
		var stderrPipe = switch Pipe.init(loop) {
			case Ok(value): value;
			case Error(_):
				closeHandle(stdinPipe);
				closeHandle(stdoutPipe);
				loop.run(DEFAULT);
				loop.close();
				return failedExecution(StartFailed);
		};
		var timer = switch Timer.init(loop) {
			case Ok(value): value;
			case Error(_):
				closeHandle(stdinPipe);
				closeHandle(stdoutPipe);
				closeHandle(stderrPipe);
				loop.run(DEFAULT);
				loop.close();
				return failedExecution(StartFailed);
		};

		var stdout = new SupportCrateAdmissionReadState();
		var stderr = new SupportCrateAdmissionReadState();
		var pipeFailed = false;
		var timedOut = false;
		var exitCode:Null<Int> = null;
		var terminationSignal:Null<Int> = null;
		var process:Null<Process> = null;
		var finishIfComplete:Void->Void = () -> {
			if (exitCode != null && stdout.closed && stderr.closed)
				stopAndCloseTimer(timer);
		};
		var options:eval.luv.Process.ProcessOptions = {
			redirect: [
				Process.toParentPipe(Process.stdin, stdinPipe, true, false, false),
				Process.toParentPipe(Process.stdout, stdoutPipe, false, true, false),
				Process.toParentPipe(Process.stderr, stderrPipe, false, true, false)
			],
			onExit: (_, status, signal) -> {
				exitCode = status.toInt();
				terminationSignal = signal;
				if (process != null)
					closeHandle(process);
				finishIfComplete();
			}
		};
		process = switch Process.spawn(loop, executablePath, [], options) {
			case Ok(value): value;
			case Error(_):
				closeHandle(stdinPipe);
				closeHandle(stdoutPipe);
				closeHandle(stderrPipe);
				closeHandle(timer);
				loop.run(DEFAULT);
				loop.close();
				return failedExecution(StartFailed);
		};

		try {
			#if support_crate_admission_test_throw_after_spawn
			throw new Exception("injected post-spawn failure");
			#end
			startRead(stdoutPipe, stdout, SupportCrateAdmissionProtocol.MAX_RESPONSE_BYTES, finishIfComplete);
			startRead(stderrPipe, stderr, MAX_STDERR_BYTES, finishIfComplete);
			var requestBuffer = Buffer.fromBytes(requestBytes);
			Stream.write(stdinPipe, [requestBuffer], (result, _) -> {
				switch result {
					case Error(_): pipeFailed = true;
					case Ok(_):
				}
				Stream.shutdown(stdinPipe, shutdownResult -> {
					switch shutdownResult {
						case Error(_): pipeFailed = true;
						case Ok(_):
					}
					closeHandle(stdinPipe);
					finishIfComplete();
				});
			});
			switch timer.start(() -> {
				timedOut = true;
				if (process != null && exitCode == null && !killProcess(process))
					pipeFailed = true;
				closeHandle(stdinPipe);
				closeHandle(stdoutPipe);
				closeHandle(stderrPipe);
				stopAndCloseTimer(timer);
			}, wallMilliseconds) {
				case Error(_):
					pipeFailed = true;
					if (exitCode == null)
						killProcess(process);
					closeHandle(stdinPipe);
					closeHandle(stdoutPipe);
					closeHandle(stderrPipe);
					stopAndCloseTimer(timer);
				case Ok(_):
			}

			loop.run(DEFAULT);
		} catch (_:Exception) {
			if (process != null && exitCode == null)
				killProcess(process);
			closeHandle(stdinPipe);
			closeHandle(stdoutPipe);
			closeHandle(stderrPipe);
			stopAndCloseTimer(timer);
			if (process != null)
				closeHandle(process);
			try {
				loop.run(DEFAULT);
			} catch (_:Exception) {}
			try {
				loop.close();
			} catch (_:Exception) {}
			return failedExecution(PipeFailed);
		}
		loop.close();
		if (timedOut)
			return failedExecution(TimedOut);
		if (pipeFailed || stdout.failed || stderr.failed || !stdout.closed || !stderr.closed)
			return failedExecution(PipeFailed);
		if (exitCode == null || exitCode != 0 || terminationSignal == null || terminationSignal != 0)
			return failedExecution(ExitFailed);
		if (stderr.exceededLimit || stderr.total != 0)
			return failedExecution(StderrRejected);
		if (stdout.exceededLimit)
			return failedExecution(ProtocolRejected);
		return {stdout: stdout.bytes.getBytes(), failure: null};
	}

	static function startRead(pipe:Pipe, state:SupportCrateAdmissionReadState, limit:Int, onClosed:Void->Void):Void {
		Stream.readStart(pipe, result -> switch result {
			case Ok(buffer):
				if (buffer.size() > 0)
					state.append(buffer, limit);
			case Error(UV_EOF):
				state.closed = true;
				Stream.readStop(pipe);
				closeHandle(pipe);
				onClosed();
			case Error(_):
				state.failed = true;
				state.closed = true;
				Stream.readStop(pipe);
				closeHandle(pipe);
				onClosed();
		});
	}

	static function stopAndCloseTimer(timer:Timer):Void {
		if (!Handle.isClosing(timer)) {
			timer.stop();
			closeHandle(timer);
		}
	}

	static function killProcess(process:Process):Bool {
		return switch Process.killPid(process.pid(), SIGKILL) {
			case Ok(_): true;
			case Error(_): false;
		};
	}

	static function closeHandle(handle:Handle):Void {
		if (!Handle.isClosing(handle))
			Handle.close(handle, () -> {});
	}

	static function failedExecution(reason:SupportCrateAdmissionRunFailure):{
		stdout:Bytes,
		failure:Null<SupportCrateAdmissionRunFailure>
	} {
		return {stdout: Bytes.alloc(0), failure: reason};
	}

	static function requestFor(plan:SupportCrateRequestPlan, activeClasspaths:Array<String>):SupportCrateAdmissionRequest {
		var classpathValues = activeClasspaths.copy();
		if (classpathValues.length == 0)
			classpathValues.push("");
		var classpaths = [for (index in 0...classpathValues.length)
			new SupportCrateAdmissionClasspathBinding(index, classpathValues[index])];
		var requests = plan.requests();
		var declarations = [for (index in 0...requests.length)
			new SupportCrateAdmissionDeclaration(index, requests[index].sourceRootSegments())];
		return new SupportCrateAdmissionRequest(classpaths, declarations);
	}

	static function validHelper(location:SupportCrateAdmissionHelperLocation):Bool {
		try {
			if (!FileSystem.exists(location.executablePath) || FileSystem.isDirectory(location.executablePath))
				return false;
			var opened = switch FileSync.open(location.executablePath, [RDONLY, NOFOLLOW]) {
				case Ok(value): value;
				case Error(_): return false;
			};
			var regular = switch FileSync.fstat(opened) {
				case Ok(value): LuvFile.testMode([IFREG], value.mode);
				case Error(_): false;
			};
			FileSync.close(opened);
			if (!regular)
				return false;
			var stat = FileSystem.stat(location.executablePath);
			if (stat.size <= 0 || stat.size > MAX_HELPER_BYTES || (stat.mode & 0x40) == 0 || (stat.mode & 0x12) != 0)
				return false;
			var bytes = File.getBytes(location.executablePath);
			return bytes.length == stat.size && Sha256.make(bytes).toHex() == location.expectedSha256;
		} catch (_:Exception) {
			return false;
		}
	}
}
#end
