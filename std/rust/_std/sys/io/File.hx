package sys.io;

import haxe.io.Bytes;
import rust.HxRef;
import hxrt.fs.FileHandle;

/**
	`sys.io.File` (Rust target implementation)

	Why
	- The upstream Haxe std declares `sys.io.File` as `extern`, expecting the target to provide a
	  concrete file API (including handle-based reading/writing via `FileInput` / `FileOutput`).
	- For production use we must avoid `unwrap()` panics on common IO failures; Haxe expects those
	  failures to be catchable exceptions.

	What
	- Implements the standard `sys.io.File` static API:
	  `getContent`, `saveContent`, `getBytes`, `saveBytes`,
	  `read`, `write`, `append`, `update`, and `copy`.

	How
	- Methods call a typed native helper bound through `@:rustExtraSrc`.
	- Errors throw a catchable Haxe exception payload (currently a `String` with the OS error
	  message; this can be refined to match other targets more closely later).
		- File handles are represented as `HxRef<hxrt.fs.FileHandle>` (runtime `HxRef<hxrt::fs::FileHandle>`)
	  and wrapped by `sys.io.FileInput` / `sys.io.FileOutput`.
**/
class File {
	public static function getContent(path:String):String {
		return FileNative.getContent(path);
	}

	public static function saveContent(path:String, content:String):Void {
		FileNative.saveContent(path, content);
	}

	public static function getBytes(path:String):Bytes {
		return FileNative.getBytes(path);
	}

	public static function saveBytes(path:String, bytes:Bytes):Void {
		FileNative.saveBytes(path, bytes);
	}

	public static function read(path:String, binary:Bool = true):FileInput {
		var _ = binary;
		var fh:HxRef<FileHandle> = FileNative.openRead(path);
		return new FileInput(fh);
	}

	public static function write(path:String, binary:Bool = true):FileOutput {
		var _ = binary;
		var fh:HxRef<FileHandle> = FileNative.openWriteTruncate(path);
		return new FileOutput(fh);
	}

	public static function append(path:String, binary:Bool = true):FileOutput {
		var _ = binary;
		var fh:HxRef<FileHandle> = FileNative.openAppend(path);
		return new FileOutput(fh);
	}

	public static function update(path:String, binary:Bool = true):FileOutput {
		var _ = binary;
		var fh:HxRef<FileHandle> = FileNative.openUpdate(path);
		return new FileOutput(fh);
	}

	public static function copy(srcPath:String, dstPath:String):Void {
		FileNative.copy(srcPath, dstPath);
	}
}

/**
	`sys.io.FileNative`

	Why:
	- `sys.io.File` is a std boundary used by broader sys/db/sys/io code.
	- Keeping filesystem calls in inline raw Rust makes strict metal reject otherwise typed user
	  programs.

	What:
	- Typed extern facade for the native Rust filesystem implementation.

	How:
	- Bound to `std/sys/io/native/file_native.rs` through `@:rustExtraSrc`.
	- The helper owns OS interaction and Haxe exception conversion.
**/
@:native("crate::file_native::FileNative")
@:rustExtraSrc("sys/io/native/file_native.rs")
private extern class FileNative {
	public static function getContent(path:String):String;
	public static function saveContent(path:String, content:String):Void;
	public static function getBytes(path:String):Bytes;
	public static function saveBytes(path:String, bytes:Bytes):Void;
	public static function openRead(path:String):HxRef<FileHandle>;
	public static function openWriteTruncate(path:String):HxRef<FileHandle>;
	public static function openAppend(path:String):HxRef<FileHandle>;
	public static function openUpdate(path:String):HxRef<FileHandle>;
	public static function copy(srcPath:String, dstPath:String):Void;
}
