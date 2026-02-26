package rust;

/**
 * `rust.OsStringTools`
 *
 * Why
 * - `rust.OsString` conversion helpers are used in path/time snapshots (`rusty_path_time`) and
 *   other Rust-first interop flows.
 * - The previous implementation used inline `untyped __rust__`, which inflated metal fallback
 *   diagnostics.
 *
 * What
 * - A typed extern boundary backed by hand-written Rust helper modules.
 * - API remains unchanged (`fromString`, `toStringLossy`).
 *
 * How
 * - Profile-aware native modules keep string representation correct:
 *   - `os_string_tools.rs` for non-nullable Rust `String`.
 *   - `os_string_tools_nullable.rs` for `hxrt::string::HxString`.
 * - Callers cross the boundary through typed signatures and return immediately to typed code.
 */
#if rust_string_nullable
@:native("crate::os_string_tools_nullable::OsStringTools")
@:rustExtraSrc("rust/native/os_string_tools_nullable.rs")
#else
@:native("crate::os_string_tools::OsStringTools")
@:rustExtraSrc("rust/native/os_string_tools.rs")
#end
extern class OsStringTools {
	public static function fromString(s:String):OsString;
	public static function toStringLossy(s:Ref<OsString>):String;
}
