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
	- Stores the handle as `HxRef<hxrt.fs.FileHandle>` so it is cloneable from Haxe while the runtime
	  owns the non-cloneable `std::fs::File` and can drop it on `close()`.
	- Handle operations call a typed native helper bound through `@:rustExtraSrc`.
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
		FileHandleNative.close(getHandle());
	}

	override public function writeByte(c:Int):Void {
		FileHandleNative.writeByte(getHandle(), c);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;

		return FileHandleNative.writeBytes(getHandle(), s, pos, len);
	}

	override public function flush():Void {
		FileHandleNative.flush(getHandle());
	}

	public function seek(p:Int, pos:FileSeek):Void {
		var h = getHandle();
		switch pos {
			case SeekBegin:
				FileHandleNative.seekFromStart(h, p);
			case SeekCur:
				FileHandleNative.seekFromCurrent(h, p);
			case SeekEnd:
				FileHandleNative.seekFromEnd(h, p);
		}
	}

	public function tell():Int {
		return FileHandleNative.tell(getHandle());
	}
}

@:native("crate::file_native::FileNative")
@:rustExtraSrc("sys/io/native/file_native.rs")
private extern class FileHandleNative {
	public static function close(handle:HxRef<FileHandle>):Void;
	public static function writeByte(handle:HxRef<FileHandle>, byte:Int):Void;
	public static function writeBytes(handle:HxRef<FileHandle>, bytes:Bytes, pos:Int, len:Int):Int;
	public static function flush(handle:HxRef<FileHandle>):Void;
	public static function seekFromStart(handle:HxRef<FileHandle>, pos:Int):Void;
	public static function seekFromCurrent(handle:HxRef<FileHandle>, offset:Int):Void;
	public static function seekFromEnd(handle:HxRef<FileHandle>, offset:Int):Void;
	public static function tell(handle:HxRef<FileHandle>):Int;
}
