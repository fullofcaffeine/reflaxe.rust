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
	- Methods are implemented via internal `__rust__` injections (framework-only).
	- Errors throw a catchable Haxe exception payload (currently a `String` with the OS error
	  message; this can be refined to match other targets more closely later).
		- File handles are represented as `HxRef<hxrt.fs.FileHandle>` (runtime `HxRef<hxrt::fs::FileHandle>`)
	  and wrapped by `sys.io.FileInput` / `sys.io.FileOutput`.
**/
class File {
	public static function getContent(path: String): String {
		return untyped __rust__(
			"match std::fs::read_to_string({0}.as_str()) {
				Ok(s) => s,
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}",
			path
		);
	}

	public static function saveContent(path: String, content: String): Void {
		untyped __rust__(
			"match std::fs::write({0}.as_str(), {1}) {
				Ok(()) => (),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}",
			path,
			content
		);
	}

	public static function getBytes(path: String): Bytes {
		return untyped __rust__(
				"{
					let data = match std::fs::read({0}.as_str()) {
						Ok(b) => b,
						Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
					};
					crate::HxRc::new(crate::HxRefCell::new(hxrt::bytes::Bytes::from_vec(data)))
				}",
				path
			);
	}

	public static function saveBytes(path: String, bytes: Bytes): Void {
		untyped __rust__(
			"{
				let b = {1}.borrow();
				match std::fs::write({0}.as_str(), b.as_slice()) {
					Ok(()) => (),
					Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
				}
			}",
			path,
			bytes
		);
	}

	public static function read(path: String, binary: Bool = true): FileInput {
		var _ = binary;
		var fh: HxRef<FileHandle> = untyped __rust__("hxrt::fs::open_read({0}.as_str())", path);
		return new FileInput(fh);
	}

	public static function write(path: String, binary: Bool = true): FileOutput {
		var _ = binary;
		var fh: HxRef<FileHandle> = untyped __rust__("hxrt::fs::open_write_truncate({0}.as_str())", path);
		return new FileOutput(fh);
	}

	public static function append(path: String, binary: Bool = true): FileOutput {
		var _ = binary;
		var fh: HxRef<FileHandle> = untyped __rust__("hxrt::fs::open_append({0}.as_str())", path);
		return new FileOutput(fh);
	}

	public static function update(path: String, binary: Bool = true): FileOutput {
		var _ = binary;
		var fh: HxRef<FileHandle> = untyped __rust__("hxrt::fs::open_update({0}.as_str())", path);
		return new FileOutput(fh);
	}

	public static function copy(srcPath: String, dstPath: String): Void {
		untyped __rust__(
			"match std::fs::copy({0}.as_str(), {1}.as_str()) {
				Ok(_) => (),
				Err(e) => hxrt::exception::throw(hxrt::dynamic::from(format!(\"{}\", e))),
			}",
			srcPath,
			dstPath
		);
	}
}
