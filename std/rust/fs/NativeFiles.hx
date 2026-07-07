package rust.fs;

import rust.PathBuf;
import rust.Ref;
import rust.Result;

/**
	`rust.fs.NativeFiles`

	Why
	- Portable `sys.io.File` preserves Haxe `Input` / `Output` handle semantics and therefore uses
	  `hxrt.fs.FileHandle`.
	- Metal code sometimes needs the opposite contract: direct Rust file operations over
	  `std::path::PathBuf` without pretending to be Haxe's portable file API.
	- A typed facade keeps app code away from `untyped __rust__` while still letting generated Rust
	  call `std::fs` / `std::io`-shaped helpers.

	What
	- A Rust-native file helper surface for the first M43 file/path slice.
	- Methods return `rust.Result<..., String>` for fallible operations so callers stay in explicit
	  Rust-style error handling instead of portable Haxe exceptions.
	- This is not a replacement for `sys.io.File`; it is a metal/native facade with a different
	  source contract.

	How
	- `@:native("crate::native_file_tools::NativeFiles")` binds to a small Rust helper module.
	- `@:rustExtraSrc("rust/native/native_file_tools.rs")` copies that helper into generated crates.
	- Paths are passed as `rust.Ref<PathBuf>` so Haxe callsites can pass a `PathBuf` while generated
	  Rust uses borrowed `&PathBuf`.
	- In `metal + rust_no_hxrt`, these helpers should not require `hxrt`; policy fixtures prove that
	  no bundled runtime dependency or `hxrt::` path is emitted for the current subset.
**/
@:native("crate::native_file_tools::NativeFiles")
@:rustExtraSrc("rust/native/native_file_tools.rs")
extern class NativeFiles {
	public static function writeString(path:Ref<PathBuf>, content:String):Result<Bool, String>;
	public static function readString(path:Ref<PathBuf>):Result<String, String>;
	public static function exists(path:Ref<PathBuf>):Bool;
	public static function removeFile(path:Ref<PathBuf>):Result<Bool, String>;
}
