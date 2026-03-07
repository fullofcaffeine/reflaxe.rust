/// `rust_string_tools_nullable` (portable nullable-string profile)
///
/// Typed helper module backing `rust.StringTools` when Haxe `String` lowers to
/// `hxrt::string::HxString`.
///
/// The `rust_` prefix is intentional. The generated crate already reserves
/// `crate::string_tools` for the emitted std `StringTools` override, so the native
/// `rust.StringTools` facade must live in its own distinct module.
#[derive(Debug)]
pub struct StringTools;

#[allow(non_snake_case)]
impl StringTools {
    pub fn contains(haystack: &hxrt::string::HxString, needle: &str) -> bool {
        haystack.contains(needle)
    }
}
