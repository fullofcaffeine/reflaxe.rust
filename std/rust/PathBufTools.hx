package rust;

/**
 * `rust.PathBufTools`
 *
 * Why
 * - `rust.PathBuf` helpers are used in metal-focused path/time snapshots and examples.
 * - The previous implementation relied on inline `untyped __rust__` for every operation,
 *   which surfaced as `ERaw` fallback noise in metal diagnostics.
 *
 * What
 * - A typed extern facade backed by hand-written Rust helper modules.
 * - The API remains the same (`fromString`, `join`, `push`, `toStringLossy`, `fileName`)
 *   while the native implementation lives under `std/rust/native/`.
 *
 * How
 * - `@:native(...)` + `@:rustExtraSrc(...)` binds this class to crate-local Rust modules.
 * - We keep profile-aware modules so `String` maps correctly in both modes:
 *   - `path_buf_tools.rs` for non-nullable Rust `String` mode.
 *   - `path_buf_tools_nullable.rs` for `hxrt::string::HxString` mode.
 * - Callers cross the native boundary via typed signatures and immediately return to typed code.
 */
#if rust_string_nullable
@:native("crate::path_buf_tools_nullable::PathBufTools")
@:rustExtraSrc("rust/native/path_buf_tools_nullable.rs")
#else
@:native("crate::path_buf_tools::PathBufTools")
@:rustExtraSrc("rust/native/path_buf_tools.rs")
#end
extern class PathBufTools {
	public static function fromString(s:String):PathBuf;
	public static function join(p:Ref<PathBuf>, child:String):PathBuf;
	public static function push(p:Ref<PathBuf>, child:String):PathBuf;
	public static function toStringLossy(p:Ref<PathBuf>):String;
	public static function fileName(p:Ref<PathBuf>):Option<String>;
}
