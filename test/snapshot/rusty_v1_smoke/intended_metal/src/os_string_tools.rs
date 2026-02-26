/// `os_string_tools` (non-nullable string profile)
///
/// Typed helper module backing `rust.OsStringTools` when Haxe `String` lowers to
/// owned Rust `String`.
#[derive(Debug)]
pub struct OsStringTools;

#[allow(non_snake_case)]
impl OsStringTools {
    pub fn fromString(s: String) -> std::ffi::OsString {
        std::ffi::OsString::from(s)
    }

    pub fn toStringLossy(s: &std::ffi::OsString) -> String {
        s.to_string_lossy().to_string()
    }
}
