/// `string_tools` (non-nullable string profile)
///
/// Typed helper module backing `rust.StringTools` when Haxe `String` lowers to owned Rust
/// `String`.
#[derive(Debug)]
pub struct StringTools;

#[allow(non_snake_case)]
impl StringTools {
    pub fn contains(haystack: &String, needle: &str) -> bool {
        haystack.contains(needle)
    }
}
