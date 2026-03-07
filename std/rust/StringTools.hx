package rust;

/**
 * `rust.StringTools`
 *
 * Why
 * - Rust-first snapshots (`rusty_borrow_ref`, `rusty_str_slice`) rely on minimal borrowed-string
 *   helpers.
 * - The previous implementation used inline `untyped __rust__`, which contributed `ERaw` fallback
 *   entries in metal diagnostics.
 *
 * What
 * - A typed extern facade backed by crate-local Rust helper modules.
 * - Existing API is preserved (`contains(haystack, needle)`).
 *
 * How
 * - Profile-aware modules preserve string representation contracts:
 *   - `rust_string_tools.rs` for non-nullable Rust `String`.
 *   - `rust_string_tools_nullable.rs` for `hxrt::string::HxString`.
 * - The module names intentionally include the `rust_` prefix so this native helper
 *   cannot collide with the generated std `StringTools` module (`crate::string_tools`)
 *   emitted from `std/StringTools.cross.hx`.
 * - Callers stay typed (`Ref<String>` + `Str`) with no raw injection fallback.
 */
#if rust_string_nullable
@:native("crate::rust_string_tools_nullable::StringTools")
@:rustExtraSrc("rust/native/rust_string_tools_nullable.rs")
#else
@:native("crate::rust_string_tools::StringTools")
@:rustExtraSrc("rust/native/rust_string_tools.rs")
#end
extern class StringTools {
	public static function contains(haystack:Ref<String>, needle:Str):Bool;
}
