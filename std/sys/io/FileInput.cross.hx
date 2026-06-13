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
	- Stores the OS file handle as `HxRef<hxrt.fs.FileHandle>` so it is cloneable from Haxe while
	  the runtime owns the non-cloneable `std::fs::File`.
	- Handle operations call a typed native helper bound through `@:rustExtraSrc`.
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
		FileHandleNative.close(getHandle());
	}

	override public function readByte():Int {
		var v:Int = FileHandleNative.readByte(getHandle());
		if (v == -1)
			throw new haxe.io.Eof();
		return v;
	}

	override public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;

		var out:Int = FileHandleNative.readBytes(getHandle(), s, pos, len);

		if (out == -1)
			throw new haxe.io.Eof();
		return out;
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

	public function eof():Bool {
		return FileHandleNative.eof(getHandle());
	}
}

@:native("crate::file_native::FileNative")
@:rustExtraSrc("sys/io/native/file_native.rs")
private extern class FileHandleNative {
	public static function close(handle:HxRef<FileHandle>):Void;
	public static function readByte(handle:HxRef<FileHandle>):Int;
	public static function readBytes(handle:HxRef<FileHandle>, bytes:Bytes, pos:Int, len:Int):Int;
	public static function seekFromStart(handle:HxRef<FileHandle>, pos:Int):Void;
	public static function seekFromCurrent(handle:HxRef<FileHandle>, offset:Int):Void;
	public static function seekFromEnd(handle:HxRef<FileHandle>, offset:Int):Void;
	public static function tell(handle:HxRef<FileHandle>):Int;
	public static function eof(handle:HxRef<FileHandle>):Bool;
}
