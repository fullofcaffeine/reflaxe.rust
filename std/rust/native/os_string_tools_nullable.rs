/// `os_string_tools_nullable` (portable nullable-string profile)
///
/// Typed helper module backing `rust.OsStringTools` when Haxe `String` lowers to
/// `hxrt::string::HxString`.
#[derive(Debug)]
pub struct OsStringTools;

#[allow(non_snake_case)]
impl OsStringTools {
    pub fn fromString(s: hxrt::string::HxString) -> std::ffi::OsString {
        std::ffi::OsString::from(s.as_str())
    }

    pub fn toStringLossy(s: &std::ffi::OsString) -> hxrt::string::HxString {
        hxrt::string::HxString::from(s.to_string_lossy().to_string())
    }
}
