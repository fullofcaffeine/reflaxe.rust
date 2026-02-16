package sys.io;

import haxe.io.Bytes;
import rust.HxRef;
import hxrt.fs.FileHandle;

/**
	`sys.io.FileInput` (Rust target implementation)

	Why
	- The upstream Haxe std declares `sys.io.FileInput` as `extern` and expects the target runtime
	  to provide a concrete stream type.
	- On reflaxe.rust, we need a real file handle that stays open across calls, supports `seek/tell`,
	  and signals end-of-file via `haxe.io.Eof` (as expected by `haxe.io.Input` consumers).

	What
	- A `haxe.io.Input` backed by a Rust `std::fs::File`.
	- Constructed via `sys.io.File.read(...)`.

	How
	- Stores the OS file handle as `HxRef<rust.fs.NativeFile>` (runtime `Rc<RefCell<std::fs::File>>`).
	- IO errors are thrown as catchable Haxe exceptions (we throw a `String` message today).
	- EOF is represented by throwing `new haxe.io.Eof()`, matching other Haxe targets.
**/
class FileInput extends haxe.io.Input {
	private var handle:HxRef<FileHandle>;

	public function new(handle:HxRef<FileHandle>) {
		this.handle = handle;
	}

	private inline function getHandle():HxRef<FileHandle> {
		return handle;
	}

	override public function close():Void {
		untyped __rust__("{0}.borrow_mut().close()", getHandle());
	}

	override public function readByte():Int {
		var v:Int = untyped __rust__("{
				{0}.borrow_mut().read_byte()
			}", getHandle());
		if (v == -1)
			throw new haxe.io.Eof();
		return v;
	}

	override public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;

		var out:Int = untyped __rust__("{
				let mut buf = vec![0u8; {2} as usize];
				let n: i32 = {0}.borrow_mut().read_into(buf.as_mut_slice());
				if n == 0 {
					-1i32
				} else if n == -1i32 {
					-1i32
				} else {
					hxrt::bytes::write_from_slice(&{1}, {3}, &buf[0..(n as usize)]);
					n
				}
			}", getHandle(), s, len, pos);

		if (out == -1)
			throw new haxe.io.Eof();
		return out;
	}

	public function seek(p:Int, pos:FileSeek):Void {
		var h = getHandle();
		switch pos {
			case SeekBegin:
				untyped __rust__("{0}.borrow_mut().seek_from_start({1} as u64)", h, p);
			case SeekCur:
				untyped __rust__("{0}.borrow_mut().seek_from_current({1} as i64)", h, p);
			case SeekEnd:
				untyped __rust__("{0}.borrow_mut().seek_from_end({1} as i64)", h, p);
		}
	}

	public function tell():Int {
		return untyped __rust__("{0}.borrow_mut().tell()", getHandle());
	}

	public function eof():Bool {
		return untyped __rust__("{0}.borrow_mut().eof()", getHandle());
	}
}
