/// `rust_string_tools` (non-nullable string profile)
///
/// Typed helper module backing `rust.StringTools` when Haxe `String` lowers to owned Rust
/// `String`.
///
/// The `rust_` prefix is intentional. The generated crate already reserves
/// `crate::string_tools` for the emitted std `StringTools` override, so the native
/// `rust.StringTools` facade must live in its own distinct module.
#[derive(Debug)]
pub struct StringTools;

#[allow(non_snake_case)]
impl StringTools {
    pub fn contains(haystack: &String, needle: &str) -> bool {
        haystack.contains(needle)
    }
}
