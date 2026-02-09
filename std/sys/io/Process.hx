package sys.io;

import haxe.io.Bytes;
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
		private var handle: HxRef<ProcessHandle>;

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
		public var stdout(get, null): haxe.io.Input;
		public var stderr(get, null): haxe.io.Input;
		public var stdin(get, null): haxe.io.Output;

		public function new(cmd: String, ?args: Array<String>, ?detached: Bool) {
			handle = untyped __rust__(
				"{
					let det: bool = {2}.unwrap_or(false);
					if {1}.is_some() {
						let args_vec: Vec<String> = {1}.as_ref().unwrap().to_vec();
						hxrt::process::spawn({0}.as_str(), Some(args_vec), det)
					} else {
						// When args are not provided, `cmd` may include arguments and/or shell builtins.
						// Match the upstream docs by running through the platform shell.
						if cfg!(windows) {
							hxrt::process::spawn(
								\"cmd\",
								Some(vec![String::from(\"/C\"), {0}.clone()]),
								det
							)
						} else {
							hxrt::process::spawn(
								\"sh\",
								Some(vec![String::from(\"-c\"), {0}.clone()]),
								det
							)
						}
					}
				}",
				cmd,
				args,
				detached
			);
		}

		private function get_stdout(): haxe.io.Input {
			return new ProcessStdout(handle);
		}

		private function get_stderr(): haxe.io.Input {
			return new ProcessStderr(handle);
		}

		private function get_stdin(): haxe.io.Output {
			return new ProcessStdin(handle);
		}

		public function getPid(): Int {
			return untyped __rust__("{0}.borrow().pid()", handle);
		}

		public function exitCode(block: Bool = true): Null<Int> {
			if (block) {
				return untyped __rust__("Some({0}.borrow_mut().wait_exit_code())", handle);
			} else {
				return untyped __rust__(
					"{
						let v = {0}.borrow_mut().try_wait_exit_code();
					match v { Some(x) => Some(x), None => None }
				}",
				handle
			);
		}
	}

	public function close(): Void {
		untyped __rust__("{0}.borrow_mut().close()", handle);
	}

	public function kill(): Void {
		untyped __rust__("{0}.borrow_mut().kill()", handle);
	}
}

/**
	`sys.io.ProcessStdin` (internal)

	`haxe.io.Output` wrapper around a child process stdin pipe.
**/
private class ProcessStdin extends haxe.io.Output {
	private var handle: HxRef<ProcessHandle>;

	public function new(handle: HxRef<ProcessHandle>) {
		this.handle = handle;
	}

	override public function writeByte(c: Int): Void {
		var b = Bytes.alloc(1);
		b.set(0, c);
		writeBytes(b, 0, 1);
	}

	override public function writeBytes(s: Bytes, pos: Int, len: Int): Int {
		if (pos < 0 || len < 0 || pos + len > s.length) throw haxe.io.Error.OutsideBounds;
		if (len == 0) return 0;
		untyped __rust__(
			"{
				let b = {0}.borrow();
				let data = b.as_slice();
				let start = {1} as usize;
				let end = ({1} + {2}) as usize;
				{3}.borrow_mut().write_stdin(&data[start..end]);
			}",
			s,
			pos,
			len,
			handle
		);
		return len;
	}

	override public function flush(): Void {
		untyped __rust__("{0}.borrow_mut().flush_stdin()", handle);
	}

	override public function close(): Void {
		untyped __rust__("{0}.borrow_mut().close_stdin()", handle);
	}
}

/**
	`sys.io.ProcessStdout` (internal)

	`haxe.io.Input` wrapper around a child process stdout pipe.
**/
private class ProcessStdout extends haxe.io.Input {
	private var handle: HxRef<ProcessHandle>;

	public function new(handle: HxRef<ProcessHandle>) {
		this.handle = handle;
	}

	override public function readByte(): Int {
		var b = Bytes.alloc(1);
		var n = readBytes(b, 0, 1);
		if (n == 0) throw new haxe.io.Eof();
		return b.get(0);
	}

	override public function readBytes(s: Bytes, pos: Int, len: Int): Int {
		if (pos < 0 || len < 0 || pos + len > s.length) throw haxe.io.Error.OutsideBounds;
		if (len == 0) return 0;

		var out: Int = untyped __rust__(
			"{
				let mut buf = vec![0u8; {2} as usize];
				let n: i32 = {0}.borrow_mut().read_stdout(buf.as_mut_slice());
				if n == -1i32 {
					0i32
				} else {
					hxrt::bytes::write_from_slice(&{1}, {3}, &buf[0..(n as usize)]);
					n
				}
			}",
			handle,
			s,
			len,
			pos
		);

		if (out == 0) throw new haxe.io.Eof();
		return out;
	}
}

/**
	`sys.io.ProcessStderr` (internal)

	`haxe.io.Input` wrapper around a child process stderr pipe.
**/
private class ProcessStderr extends haxe.io.Input {
	private var handle: HxRef<ProcessHandle>;

	public function new(handle: HxRef<ProcessHandle>) {
		this.handle = handle;
	}

	override public function readByte(): Int {
		var b = Bytes.alloc(1);
		var n = readBytes(b, 0, 1);
		if (n == 0) throw new haxe.io.Eof();
		return b.get(0);
	}

	override public function readBytes(s: Bytes, pos: Int, len: Int): Int {
		if (pos < 0 || len < 0 || pos + len > s.length) throw haxe.io.Error.OutsideBounds;
		if (len == 0) return 0;

		var out: Int = untyped __rust__(
			"{
				let mut buf = vec![0u8; {2} as usize];
				let n: i32 = {0}.borrow_mut().read_stderr(buf.as_mut_slice());
				if n == -1i32 {
					0i32
				} else {
					hxrt::bytes::write_from_slice(&{1}, {3}, &buf[0..(n as usize)]);
					n
				}
			}",
			handle,
			s,
			len,
			pos
		);

		if (out == 0) throw new haxe.io.Eof();
		return out;
	}
}
