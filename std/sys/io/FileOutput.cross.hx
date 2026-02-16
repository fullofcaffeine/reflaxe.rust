package sys.io;

import haxe.io.Bytes;
import rust.HxRef;
import hxrt.fs.FileHandle;

/**
	`sys.io.FileOutput` (Rust target implementation)

	Why
	- Upstream Haxe std declares this type as `extern` and expects the target to provide a concrete
	  `haxe.io.Output` backed by a file handle.
	- Portable Haxe code expects `sys.io.File.write/append/update` to return an output that supports
	  `seek/tell` and integrates with `haxe.io.Output` APIs (`writeByte`, `writeBytes`, `flush`).

	What
	- A `haxe.io.Output` backed by a Rust `std::fs::File`.
	- Constructed via `sys.io.File.write/append/update(...)`.

	How
	- Stores the handle as `HxRef<rust.fs.NativeFile>` (runtime `Rc<RefCell<std::fs::File>>`) so it is
	  cloneable and can be dropped on `close()`.
	- IO errors are thrown as catchable Haxe exceptions (currently thrown as a `String` message).
**/
class FileOutput extends haxe.io.Output {
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

	override public function writeByte(c:Int):Void {
		untyped __rust__("{
				let buf = [({1} & 0xFF) as u8];
				{0}.borrow_mut().write_all(&buf)
			}", getHandle(), c);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;

		return untyped __rust__("{
				let b = {0}.borrow();
				let data = b.as_slice();
				let start = {1} as usize;
				let end = ({1} + {2}) as usize;
				{3}.borrow_mut().write_all(&data[start..end]);
				{2} as i32
			}", s, pos, len, getHandle());
	}

	override public function flush():Void {
		untyped __rust__("{0}.borrow_mut().flush()", getHandle());
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
}
