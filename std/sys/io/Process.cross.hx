package sys.io;

import haxe.io.Bytes;
import hxrt.process.NativeProcess;
import hxrt.process.ProcessHandle;
import rust.HxRef;

/**
	`sys.io.Process` (Rust target implementation)

	Why
	- Upstream Haxe std declares `sys.io.Process` as `extern`, so sys-capable targets must provide a
	  working implementation for running subprocesses and communicating via pipes.

	What
	- Spawns a process immediately and exposes `stdin`, `stdout`, `stderr` streams.
	- Supports `getPid()`, `exitCode(block)`, `kill()`, and `close()`.

	How
	- Uses a runtime handle `HxRef<hxrt.process.ProcessHandle>` backed by `hxrt::process::Process`
	  (stores `std::process::Child` + piped stdio).
	- IO failures are thrown as catchable Haxe exceptions (`hxrt::exception`).
**/
class Process {
	private var handle:HxRef<ProcessHandle>;

	/**
		Why
		- Upstream Haxe exposes `stdin`/`stdout`/`stderr` as public fields. On this target we
		  implement them as properties so the generated Rust struct does not need to
		  store trait objects (`dyn InputTrait` / `dyn OutputTrait`).

		What
		- Allocates stream wrappers that share the same underlying process handle.

		How
		- Each access returns a new wrapper object around the same `handle`.
		- This avoids storing polymorphic IO trait objects inside the `Process` struct.
	**/
	public var stdout(get, null):haxe.io.Input;

	public var stderr(get, null):haxe.io.Input;
	public var stdin(get, null):haxe.io.Output;

	public function new(cmd:String, ?args:Array<String>, ?detached:Bool) {
		var argsProvided = args != null;
		handle = NativeProcess.spawn(cmd, argsProvided ? args : [], detached, argsProvided);
	}

	private function get_stdout():haxe.io.Input {
		return new ProcessStdout(handle);
	}

	private function get_stderr():haxe.io.Input {
		return new ProcessStderr(handle);
	}

	private function get_stdin():haxe.io.Output {
		return new ProcessStdin(handle);
	}

	public function getPid():Int {
		return NativeProcess.pid(handle);
	}

	public function exitCode(block:Bool = true):Null<Int> {
		return block ? NativeProcess.waitExitCode(handle) : NativeProcess.tryWaitExitCode(handle);
	}

	public function close():Void {
		NativeProcess.closeHandle(handle);
	}

	public function kill():Void {
		NativeProcess.kill(handle);
	}
}

/**
	`sys.io.ProcessStdin` (internal)

	`haxe.io.Output` wrapper around a child process stdin pipe.
**/
private class ProcessStdin extends haxe.io.Output {
	private var handle:HxRef<ProcessHandle>;

	public function new(handle:HxRef<ProcessHandle>) {
		this.handle = handle;
	}

	override public function writeByte(c:Int):Void {
		var b = Bytes.alloc(1);
		b.set(0, c);
		writeBytes(b, 0, 1);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;
		return NativeProcess.writeStdin(handle, s, pos, len);
	}

	override public function flush():Void {
		NativeProcess.flushStdin(handle);
	}

	override public function close():Void {
		NativeProcess.closeStdin(handle);
	}
}

/**
	`sys.io.ProcessStdout` (internal)

	`haxe.io.Input` wrapper around a child process stdout pipe.
**/
private class ProcessStdout extends haxe.io.Input {
	private var handle:HxRef<ProcessHandle>;

	public function new(handle:HxRef<ProcessHandle>) {
		this.handle = handle;
	}

	override public function readByte():Int {
		var b = Bytes.alloc(1);
		var n = readBytes(b, 0, 1);
		if (n == 0)
			throw new haxe.io.Eof();
		return b.get(0);
	}

	override public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;

		var out = NativeProcess.readStdout(handle, s, pos, len);

		if (out < 0)
			throw new haxe.io.Eof();
		return out;
	}
}

/**
	`sys.io.ProcessStderr` (internal)

	`haxe.io.Input` wrapper around a child process stderr pipe.
**/
private class ProcessStderr extends haxe.io.Input {
	private var handle:HxRef<ProcessHandle>;

	public function new(handle:HxRef<ProcessHandle>) {
		this.handle = handle;
	}

	override public function readByte():Int {
		var b = Bytes.alloc(1);
		var n = readBytes(b, 0, 1);
		if (n == 0)
			throw new haxe.io.Eof();
		return b.get(0);
	}

	override public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;

		var out = NativeProcess.readStderr(handle, s, pos, len);

		if (out < 0)
			throw new haxe.io.Eof();
		return out;
	}
}
