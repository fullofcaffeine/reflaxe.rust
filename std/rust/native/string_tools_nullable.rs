/// `string_tools_nullable` (portable nullable-string profile)
///
/// Typed helper module backing `rust.StringTools` when Haxe `String` lowers to
/// `hxrt::string::HxString`.
#[derive(Debug)]
pub struct StringTools;

#[allow(non_snake_case)]
impl StringTools {
    pub fn contains(haystack: &hxrt::string::HxString, needle: &str) -> bool {
        haystack.contains(needle)
    }
}
